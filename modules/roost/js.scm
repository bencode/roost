(define-library (roost js)
  (export global module (rename js-ref ref) (rename js-set! set!) method new function function?
          array object from-scheme to-scheme typeof value?
          (rename js-error? error?) (rename js-error-value error-value)
          property-name set-node-converter!)
  (import (scheme base)
          (scheme char)
          (scheme lazy)
          (scheme write)
          (only (guile) keyword->symbol)
          (hoot ffi)
          (hoot hashtables)
          (hoot inline-wasm)
          (roost props))
  (begin
    ;; Kernel imports (js/roost-kernel.js). Results are always extern; Scheme values that
    ;; went out opaquely are recognised again inside Wasm by scheme-value?.
    (define-foreign %module "roost" "module" (ref string) -> (ref null extern))
    (define-foreign %get "roost" "get" (ref null extern) (ref string) -> (ref null extern))
    (define-foreign %set! "roost" "set" (ref null extern) (ref string) (ref null extern) -> (ref null extern))
    (define-foreign %object "roost" "object" -> (ref extern))
    (define-foreign %array "roost" "array" -> (ref extern))
    (define-foreign %push! "roost" "push" (ref extern) (ref null extern) -> none)
    (define-foreign %apply "roost" "apply" (ref null extern) (ref null extern) (ref extern) -> (ref null extern))
    (define-foreign %construct "roost" "construct" (ref null extern) (ref extern) -> (ref null extern))
    (define-foreign %thrown "roost" "thrown" (ref null extern) -> i32)
    (define-foreign %last-error "roost" "lastError" -> (ref null extern))
    (define-foreign %fn "roost" "fn" (ref extern) i32 -> (ref extern))
    (define-foreign %type-of "roost" "typeOf" (ref null extern) -> (ref string))
    (define-foreign %to-number "roost" "toNumber" (ref null extern) -> f64)
    (define-foreign %to-string "roost" "toString" (ref null extern) -> (ref string))
    (define-foreign %to-boolean "roost" "toBoolean" (ref null extern) -> i32)
    (define-foreign %opaque "roost" "opaque" (ref eq) -> (ref extern))
    (define-foreign %string "roost" "string" (ref string) -> (ref extern))
    (define-foreign %number "roost" "number" f64 -> (ref extern))
    (define-foreign %boolean "roost" "boolean" i32 -> (ref extern))
    (define-foreign %undefined "roost" "undefined" -> (ref null extern))

    (define (scheme-value? x)
      (%inline-wasm
       '(func (param $x (ref null extern)) (result (ref eq))
          (if (ref eq) (ref.test $heap-object (any.convert_extern (local.get $x)))
              (then (ref.i31 (i32.const 17)))
              (else (ref.i31 (i32.const 1)))))
       x))

    (define (unwrap x)
      (%inline-wasm
       '(func (param $x (ref null extern)) (result (ref eq))
          (ref.cast $heap-object (any.convert_extern (local.get $x))))
       x))

    (define (undefined? x) (string=? "undefined" (%type-of x)))
    (define (nullish? x) (member (%type-of x) '("undefined" "null")))

    ;; JavaScript exceptions become Scheme conditions so guard and dynamic-wind work.
    (define-record-type <js-error>
      (make-js-error value)
      js-error?
      (value js-error-value))

    (define (checked result)
      (if (= 1 (%thrown result))
          (raise (make-js-error (%last-error)))
          result))

    ;; '(), chars and eof are i31 immediates that JavaScript would see as numbers, so
    ;; they travel inside canonical boxes.
    (define-record-type <boxed>
      (make-boxed value)
      boxed?
      (value boxed-value))

    (define empty-list-box (make-boxed '()))
    (define eof-box (make-boxed (eof-object)))
    (define char-boxes (make-eqv-hashtable))

    (define (box-immediate v)
      (cond
       ((null? v) empty-list-box)
       ((eof-object? v) eof-box)
       (else (or (hashtable-ref char-boxes v #f)
                 (let ((box (make-boxed v)))
                   (hashtable-set! char-boxes v box)
                   box)))))

    ;; Hoot evaluates library bodies at expansion time in Guile, where FFI calls are not
    ;; available, so every top-level value that needs JavaScript is created lazily.
    ;; js/global is a marker that ->js turns into globalThis.
    (define-record-type <global> (make-global) global?)
    (define global (make-global))
    (define global-object (delay (%module "global")))
    (define max-safe-integer 9007199254740991)
    (define unspecified (if #f #f))

    (define (args->array values convert)
      (let ((array (%array)))
        (for-each (lambda (v) (%push! array (convert v))) values)
        array))

    (define (method-call object name args)
      (checked (%apply (%get object name) object (args->array args (lambda (x) x)))))

    ;; Function identity lives in JavaScript WeakMaps keyed by the opaque procedure or
    ;; function, so procedures created during render can be collected.
    (define (make-weak-map)
      (checked (%construct (%get (force global-object) "WeakMap") (%array))))
    (define (weak-ref map key)
      (let ((found (method-call map "get" (list key))))
        (and (not (undefined? found)) found)))
    (define (weak-set! map key value) (method-call map "set" (list key value)))

    (define js-origins (delay (make-weak-map)))   ; wrapper procedure -> original JS function
    (define js-wrappers (delay (make-weak-map)))  ; JS function -> canonical procedure
    (define js-functions (delay (make-weak-map))) ; procedure -> its one JS function

    ;; Arguments a callback receives: the first `length` when declared, otherwise all
    ;; of them without trailing undefined (React calls components as (props, undefined)).
    (define (frame-arguments args length)
      (let* ((total (exact (%to-number (%get args "length"))))
             (count (if length
                        (min length total)
                        (let trim ((n total))
                          (if (and (> n 0) (undefined? (%get args (number->string (- n 1)))))
                              (trim (- n 1))
                              n)))))
        (let loop ((i (- count 1)) (acc '()))
          (if (< i 0)
              acc
              (loop (- i 1) (cons (->scheme (%get args (number->string i))) acc))))))

    ;; A Scheme exception raised inside a callback becomes a JavaScript Error thrown to
    ;; the caller; an exception that came from JavaScript is rethrown unchanged.
    (define (condition-message condition)
      (let ((port (open-output-string)))
        (if (error-object? condition)
            (begin
              (display (error-object-message condition) port)
              (for-each (lambda (irritant) (display " " port) (write irritant port))
                        (error-object-irritants condition)))
            (write condition port))
        (get-output-string port)))

    (define (condition->js condition)
      (if (js-error? condition)
          (js-error-value condition)
          (let ((error (checked (%construct (%get (force global-object) "Error")
                                            (args->array (list (condition-message condition)) ->js)))))
            (%set! error "schemeCondition" (->js condition))
            error)))

    (define (make-function proc length)
      (%fn (procedure->external
            (lambda (frame)
              (guard (condition
                      (#t (%set! frame "error" (condition->js condition))
                          (%set! frame "failed" (%boolean 1))))
                (call-with-values
                    (lambda () (apply proc (frame-arguments (%get frame "args") length)))
                  (lambda results
                    ;; Zero or several values return undefined; (values) is valid Scheme.
                    (when (and (pair? results) (null? (cdr results)))
                      (%set! frame "result" (->js (car results)))))))))
           (or length 0)))

    ;; A procedure has exactly one JavaScript function; its first conversion fixes the
    ;; declared length. Later conversions without a length reuse it.
    (define (procedure->js proc length)
      (let ((key (%opaque proc)))
        (or (weak-ref (force js-origins) key)
            (let ((existing (weak-ref (force js-functions) key)))
              (cond
               ((not existing)
                (let ((fn (make-function proc length)))
                  (weak-set! (force js-functions) key fn)
                  (weak-set! (force js-wrappers) fn key)
                  fn))
               ((or (not length) (= length (exact (%to-number (%get existing "length")))))
                existing)
               (else
                (error "js/function: procedure already has a JavaScript function of another length"
                       length)))))))

    (define (js-function->procedure fn)
      (let ((found (weak-ref (force js-wrappers) fn)))
        (if found
            (unwrap found)
            (let ((proc (lambda args (call fn (%undefined) args))))
              (weak-set! (force js-wrappers) fn (%opaque proc))
              (weak-set! (force js-origins) (%opaque proc) fn)
              proc))))

    ;; Shallow conversion, used by every call.
    (define (->js v)
      (cond
       ((external? v) v)
       ((global? v) (force global-object))
       ((procedure? v) (procedure->js v #f))
       ((string? v) (%string v))
       ((exact-integer? v)
        (if (<= (abs v) max-safe-integer)
            (%number v)
            (error "js: integer outside the JavaScript safe range" v)))
       ((real? v) (%number v))
       ((boolean? v) (%boolean (if v 1 0)))
       ((eq? v unspecified) (%undefined))
       ((or (null? v) (char? v) (eof-object? v)) (%opaque (box-immediate v)))
       (else (%opaque v))))

    (define (->scheme x)
      (let ((type (%type-of x)))
        (cond
         ((string=? type "number")
          (let ((n (%to-number x)))
            (if (and (integer? n) (<= (abs n) max-safe-integer)) (exact n) n)))
         ((string=? type "string") (%to-string x))
         ((string=? type "boolean") (= 1 (%to-boolean x)))
         ((or (string=? type "undefined") (string=? type "null")) #f)
         ((string=? type "function") (js-function->procedure x))
         ((scheme-value? x)
          (let ((v (unwrap x)))
            (if (boxed? v) (boxed-value v) v)))
         (else x))))

    (define (call fn self args)
      (->scheme (checked (%apply fn self (args->array args ->js)))))

    (define (key->string key)
      (if (string? key) key (number->string key)))

    (define (module name)
      (let ((value (%module name)))
        (when (undefined? value)
          (error "js/module: module is not registered" name))
        (->scheme value)))

    ;; Property access from the public API; getters and setters may throw.
    (define (get-checked object key)
      (checked (%get object (key->string key))))

    (define (js-ref object key . keys)
      (let loop ((value (->js object)) (key key) (keys keys))
        (let ((next (get-checked value key)))
          (cond
           ((null? keys) (->scheme next))
           ((nullish? next) (error "js/ref: property is null or undefined" key))
           (else (loop next (car keys) (cdr keys)))))))

    (define (js-set! object key value)
      (checked (%set! (->js object) (key->string key) (->js value)))
      unspecified)

    (define (method object name . args)
      (let* ((target (->js object))
             (fn (get-checked target name)))
        (unless (string=? "function" (%type-of fn))
          (error "js/method: not a function" name))
        (call fn target args)))

    (define (new constructor . args)
      (->scheme (checked (%construct (->js constructor) (args->array args ->js)))))

    (define (function proc length)
      (procedure->js proc length))

    (define (function? v)
      (and (procedure? v) (weak-ref (force js-origins) (%opaque v)) #t))

    (define (array . values)
      (args->array values ->js))

    (define (object . keys-and-values)
      (let ((result (%object)))
        (let loop ((rest keys-and-values))
          (unless (null? rest)
            (%set! result (car rest) (->js (cadr rest)))
            (loop (cddr rest))))
        result))

    (define (typeof object . keys)
      (let ((value (if (null? keys)
                       (->js object)
                       (let loop ((value (->js object)) (keys keys))
                         (let ((next (get-checked value (car keys))))
                           (if (null? (cdr keys)) next (loop next (cdr keys))))))))
        (if (and (not (member (%type-of value) '("number" "string" "boolean" "undefined" "null" "function")))
                 (scheme-value? value))
            "scheme"
            (%type-of value))))

    (define (value? v) (or (external? v) (global? v)))

    (define (property-name keyword)
      (let loop ((chars (string->list (symbol->string (keyword->symbol keyword))))
                 (upcase? #f)
                 (acc '()))
        (cond
         ((null? chars) (list->string (reverse acc)))
         ((char=? (car chars) #\-) (loop (cdr chars) #t acc))
         (else (loop (cdr chars) #f
                     (cons (if upcase? (char-upcase (car chars)) (car chars)) acc))))))

    ;; Set by (roost react) so that from-scheme turns Hiccup nodes into React elements
    ;; without (roost js) depending on React.
    (define node-converter #f)
    (define (set-node-converter! convert) (set! node-converter convert))

    (define (from-scheme v)
      (cond
       ((list? v) (args->array v from-scheme))
       ((props? v)
        (let ((result (%object)))
          (for-each (lambda (entry)
                      (%set! result (property-name (car entry)) (from-scheme (cdr entry))))
                    (props-entries v))
          result))
       ((vector? v)
        (if node-converter
            (->js (node-converter v))
            (args->array (vector->list v) from-scheme)))
       (else (->js v))))

    (define (to-scheme x)
      (let ((value (if (external? x) x (->js x))))
        (if (and (string=? "object" (%type-of value))
                 (not (scheme-value? value))
                 (call (%get (%get (force global-object) "Array") "isArray") (%undefined) (list value)))
            (let loop ((i (- (exact (%to-number (%get value "length"))) 1)) (acc '()))
              (if (< i 0)
                  acc
                  (loop (- i 1) (cons (to-scheme (%get value (number->string i))) acc))))
            (->scheme value))))))
