(define-module (roost react)
  #:pure
  #:export (render-root)
  #:use-module (scheme base)
  #:use-module (scheme char)
  #:use-module (scheme lazy)
  #:use-module ((hoot keywords) #:select (keyword->symbol))
  #:use-module (hoot ffi)
  #:use-module (hoot hashtables)
  #:use-module (hoot inline-wasm)
  #:use-module (roost props)
  #:use-module ((roost js) #:prefix js/))

;; Each render walks the Hiccup tree and drives the builder in js/roost-react.js
;; through direct calls with fixed parameter types, so React elements are assembled
;; in JavaScript without the generic conversions of (roost js).
(define-foreign %setup "roostReact" "setup" (ref null extern) (ref null extern) -> none)
(define-foreign %begin "roostReact" "begin" -> i32)
(define-foreign %finish "roostReact" "finish" -> (ref null extern))
(define-foreign %reset "roostReact" "reset" i32 -> none)
(define-foreign %open-element "roostReact" "openElement" (ref null extern) -> none)
(define-foreign %open-tag "roostReact" "openElement" (ref string) -> none)
(define-foreign %open-object "roostReact" "openObject" -> none)
(define-foreign %open-array "roostReact" "openArray" -> none)
(define-foreign %close-item "roostReact" "closeItem" -> none)
(define-foreign %close-field "roostReact" "closeField" (ref null extern) -> none)
(define-foreign %field-string "roostReact" "field" (ref null extern) (ref string) -> none)
(define-foreign %field-number "roostReact" "field" (ref null extern) f64 -> none)
(define-foreign %field-value "roostReact" "field" (ref null extern) (ref null extern) -> none)
(define-foreign %field-scheme "roostReact" "field" (ref null extern) (ref eq) -> none)
(define-foreign %field-bool "roostReact" "fieldBool" (ref null extern) i32 -> none)
(define-foreign %field-handler "roostReact" "fieldHandler" (ref null extern) (ref eq) -> none)
(define-foreign %item-string "roostReact" "item" (ref string) -> none)
(define-foreign %item-number "roostReact" "item" f64 -> none)
(define-foreign %item-value "roostReact" "item" (ref null extern) -> none)
(define-foreign %item-bool "roostReact" "itemBool" i32 -> none)
(define-foreign %remember "roostReact" "remember" (ref eq) (ref string) -> none)
(define-foreign %open-tag-text "roostReact" "openTagText" (ref eq) -> i32)
(define-foreign %field-text "roostReact" "fieldText" (ref null extern) (ref eq) -> i32)
(define-foreign %item-text "roostReact" "itemText" (ref eq) -> i32)

;; Immutable strings (literals) are passed as objects; the builder keeps their
;; JavaScript text in a WeakMap, so each converts once. Mutable strings may change,
;; so they always convert.
(define (mutable-string? s)
  (%inline-wasm
   '(func (param $s (ref eq)) (result (ref eq))
      (if (ref eq) (ref.test $mutable-string (local.get $s))
          (then (ref.i31 (i32.const 17)))
          (else (ref.i31 (i32.const 1)))))
   s))

(define (by-identity s pass)
  (when (= 0 (pass s))
    (%remember s s)
    (pass s)))

(define (open-tag tag)
  (if (mutable-string? tag)
      (%open-tag tag)
      (by-identity tag %open-tag-text)))

;; Two or more trailing children of a component. Forwarded through a Fragment so
;; React treats them as static children (no key checks), unlike dynamic lists.
(define-record-type <static-children>
  (make-static-children items)
  static-children?
  (items static-children-items))

;; Lazy: Hoot evaluates library bodies at expansion time, where JavaScript is absent.
;; dispatch receives a DOM event handler passed through as an opaque Scheme value.
(define (dispatch procedure . args) (apply procedure args))
(define react (delay (js/module "react")))
(define fragment (delay (js/ref (force react) "Fragment")))
(define builder
  (delay (begin (%setup (force react) (js/function dispatch #f)) #t)))

;; One React type per render procedure, keyed by the procedure itself in a weak
;; table so render procedures created on the fly can be collected. React calls
;; components as (props, undefined); length 1 passes only props.
(define component-types (delay (js/make-weak-table)))

(define (render->react-type render)
  (let ((types (force component-types)))
    (or (js/weak-table-ref types render #f)
        (let ((type (js/function
                     (lambda (js-props)
                       (render-tree (render (js/ref js-props "roostProps"))))
                     1)))
          (js/weak-table-set! types render type)
          type))))

(define (render-tree node)
  (force builder)
  (let ((depth (%begin))
        (done? #f))
    (dynamic-wind
     (lambda () #f)
     (lambda ()
       (emit-child node #f)
       (let ((result (%finish)))
         (set! done? #t)
         result))
     (lambda () (unless done? (%reset depth))))))

(js/set-node-converter! render-tree)

;;; Names: computed once per keyword (keywords are interned), kept as JS strings.

(define (name-cache rule)
  (let ((table (make-eq-hashtable)))
    (lambda (keyword)
      (or (hashtable-ref table keyword #f)
          (let ((name (js/scheme->js (rule (symbol->string (keyword->symbol keyword))))))
            (hashtable-set! table keyword name)
            name)))))

(define (string-prefix? prefix s)
  (and (<= (string-length prefix) (string-length s))
       (string=? prefix (substring s 0 (string-length prefix)))))

(define (camel name)
  (let loop ((chars (string->list name)) (upcase? #f) (acc '()))
    (cond
     ((null? chars) (list->string (reverse acc)))
     ((char=? (car chars) #\-) (loop (cdr chars) #t acc))
     (else (loop (cdr chars) #f
                 (cons (if upcase? (char-upcase (car chars)) (car chars)) acc))))))

;; React's names for DOM elements and JavaScript components alike.
(define dom-name
  (name-cache
   (lambda (name)
     (cond
      ((string=? name "class") "className")
      ((string=? name "for") "htmlFor")
      ((or (string-prefix? "aria-" name) (string-prefix? "data-" name)) name)
      (else (camel name))))))

(define style-name
  (name-cache (lambda (name) (if (string-prefix? "--" name) name (camel name)))))

(define object-name (name-cache camel))

(define (event-name? keyword)
  (string-prefix? "on-" (symbol->string (keyword->symbol keyword))))

;;; Children: the same rules whether a child becomes an item or a named field.

(define max-safe-integer 9007199254740991)

(define (number->js n)
  (if (and (exact-integer? n) (> (abs n) max-safe-integer))
      (error "js: integer outside the JavaScript safe range" n)
      n))

;; A value goes either into the children of the open element or array (name #f), or
;; into a named field of the open element or object.
(define (put-string name s)
  (cond
   ((mutable-string? s) (if name (%field-string name s) (%item-string s)))
   (name (by-identity s (lambda (s) (%field-text name s))))
   (else (by-identity s %item-text))))
(define (put-number name n) (if name (%field-number name (number->js n)) (%item-number (number->js n))))
(define (put-bool name b) (if name (%field-bool name (if b 1 0)) (%item-bool (if b 1 0))))
(define (put-value name v) (if name (%field-value name (js/scheme->js v)) (%item-value (js/scheme->js v))))
(define (close-into name) (if name (%close-field name) (%close-item)))

(define (emit-child child name)
  (cond
   ((and (vector? child) (> (vector-length child) 0)) (emit-node child) (close-into name))
   ((string? child) (put-string name child))
   ((real? child) (put-number name child))
   ((boolean? child) (put-bool name child))
   ((js/value? child) (put-value name child))
   ((list? child) (%open-array) (emit-children child) (close-into name))
   ((static-children? child)
    (%open-element (force fragment))
    (emit-children (static-children-items child))
    (close-into name))
   (else (error "node->react: unsupported child" child))))

(define (emit-children children)
  (for-each (lambda (child) (emit-child child #f)) children))

;; Opens the element for a node and fills it; the caller closes it.
(define (emit-node node)
  (let-values (((attributes children) (split-contents node)))
    (let ((type (vector-ref node 0)))
      (cond
       ((string? type)
        (open-tag type)
        (for-each emit-dom-prop (entries attributes))
        (emit-children children))
       ((or (js/value? type) (js/function? type))
        (%open-element (js/scheme->js type))
        (for-each emit-js-prop (entries attributes))
        (emit-children children))
       ((procedure? type) (emit-component type attributes children))
       (else (error "node->react: unsupported node type" type))))))

(define (split-contents node)
  (let ((contents (cdr (vector->list node))))
    (if (and (pair? contents) (props? (car contents)))
        (values (car contents) (cdr contents))
        (values #f contents))))

(define (entries attributes)
  (if attributes (props-entries attributes) '()))

;;; Components

;; Trailing children become #:children: none keeps the explicit value, one is kept as
;; is, several form a static collection. #:key goes to React, not to the component.
(define (emit-component render attributes children)
  (let* ((given (entries attributes))
         (key (assq #:key given))
         (forwarded
          (cond
           ((null? children) #f)
           ((null? (cdr children)) (car children))
           (else (make-static-children children))))
         (component-props
          (if (and (not key) (null? children) attributes)
              attributes
              (entries->props
               (append (without-keys given (if (null? children) '(#:key) '(#:key #:children)))
                       (if (null? children) '() (list (cons #:children forwarded))))))))
    (%open-element (render->react-type render))
    (%field-scheme (dom-name #:roost-props) component-props)
    (when key
      (put-key (cdr key)))))

(define (entries->props entries)
  (apply props (apply append (map (lambda (e) (list (car e) (cdr e))) entries))))

(define (without-keys entries keys)
  (let loop ((rest entries) (acc '()))
    (cond
     ((null? rest) (reverse acc))
     ((memq (caar rest) keys) (loop (cdr rest) acc))
     (else (loop (cdr rest) (cons (car rest) acc))))))

;; React turns a numeric key into its decimal string itself, so integers pass as is.
(define (put-key value)
  (cond
   ((string? value) (put-string (dom-name #:key) value))
   ((and (exact-integer? value) (<= (abs value) max-safe-integer)) (put-number (dom-name #:key) value))
   ((exact-integer? value) (put-string (dom-name #:key) (number->string value)))
   (else (error "node->react: key must be a string or an exact integer" value))))

;;; Props

;; DOM event handlers pass the procedure through and get a fresh function per render,
;; like inline handlers in JSX; every other procedure keeps a canonical function.
(define (emit-dom-prop entry)
  (let ((key (car entry)) (value (cdr entry)))
    (cond
     ((eq? key #:key) (put-key value))
     ((eq? key #:children) (emit-child value (dom-name key)))
     ((eq? key #:style) (emit-style value))
     ((string? value) (put-string (dom-name key) value))
     ((real? value) (%field-number (dom-name key) (number->js value)))
     ((boolean? value) (%field-bool (dom-name key) (if value 1 0)))
     ((procedure? value)
      (if (event-name? key)
          (%field-handler (dom-name key) value)
          (%field-value (dom-name key) (js/scheme->js value))))
     ((js/value? value) (%field-value (dom-name key) (js/scheme->js value)))
     (else (error "node->react: unsupported DOM property value" value)))))

(define (emit-style style)
  (unless (props? style)
    (error "node->react: #:style must be a props value" style))
  (%open-object)
  (for-each (lambda (entry)
              (let ((value (cdr entry)))
                (cond
                 ((string? value) (put-string (style-name (car entry)) value))
                 ((real? value) (%field-number (style-name (car entry)) (number->js value)))
                 (else (error "node->react: unsupported style value" value)))))
            (props-entries style))
  (%close-field (dom-name #:style)))

;; Props of JavaScript components are plain JavaScript data, as with js/from-scheme,
;; named as on DOM nodes.
(define (emit-js-prop entry)
  (let ((key (car entry)) (value (cdr entry)))
    (if (and (eq? key #:style) (props? value))
        (emit-style value)
        (emit-data value (dom-name key)))))

;; name #f puts the value into the open array.
(define (emit-data value name)
  (cond
   ((list? value) (%open-array) (for-each (lambda (item) (emit-data item #f)) value) (close-into name))
   ((props? value) (emit-object value) (close-into name))
   ((vector? value) (emit-child value name))
   ((string? value) (put-string name value))
   ((real? value) (put-number name value))
   ((boolean? value) (put-bool name value))
   (else (put-value name value))))

(define (emit-object attributes)
  (%open-object)
  (for-each (lambda (entry) (emit-data (cdr entry) (object-name (car entry))))
            (props-entries attributes)))

(define (render-root node element-id)
  (let* ((document (js/ref js/global "document"))
         (create-root (js/ref (js/module "react-dom/client") "createRoot"))
         (root (create-root (js/method document "getElementById" element-id))))
    (js/method root "render" (render-tree node))
    root))
