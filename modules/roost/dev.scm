;; Live development. A development shell compiles Roost with Hoot's run-time module
;; system; the application's modules are loaded from source by the interpreter, so
;; saving one evaluates its definitions again in the running page.
(define-module (roost dev)
  #:pure
  #:export (dev-program)
  #:use-module (scheme base)
  #:use-module ((hoot lists) #:select (filter))
  #:use-module ((hoot modules) #:select (the-root-module resolve-module module-local-variable
                                         current-module-loader))
  #:use-module ((hoot hackable) #:select (load-module))
  #:use-module ((hoot eval) #:select (eval))
  #:use-module ((hoot read) #:select (read-syntax))
  #:use-module ((hoot error-handling) #:select (format-exception))
  #:use-module ((hoot syntax-objects) #:select (syntax->datum))
  #:use-module ((hoot web-repl) #:select (current-repl-server run-web-repl))
  #:use-module ((fibers promises) #:select (call-with-async-result))
  #:use-module ((web fetch) #:select (fetch))
  #:use-module ((web request) #:select (build-request))
  #:use-module ((web response) #:select (response-code response-body))
  #:use-module ((web uri) #:select (string->uri))
  #:use-module ((roost react) #:select (transfer-component! refresh-roots!))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools) #:select (mount-devtools!)))

(define (read-forms port)
  (let loop ((forms '()))
    (let ((form (read-syntax port)))
      (if (eof-object? form)
          (reverse forms)
          (loop (cons form forms))))))

(define (module-path name)
  (let loop ((parts (map symbol->string name)) (path ""))
    (if (null? parts)
        path
        (loop (cdr parts) (string-append path "/" (car parts))))))

;; Each application module's top-level forms, as read when it last loaded or reloaded:
;; the REPL panel completes names from them.
(define loaded-forms '())

(define (record-forms! name forms)
  (set! loaded-forms (cons (cons name (map syntax->datum forms))
                           (filter (lambda (entry) (not (equal? (car entry) name))) loaded-forms))))

(define (module-forms name)
  (let ((entry (assoc name loaded-forms)))
    (and entry (cdr entry))))

;; Loads application modules from the development server: <server>/repl/load/a/b.
(define (load-from-server root name)
  (let ((response (fetch (build-request
                          (string->uri (string-append (current-repl-server) "/repl/load"
                                                      (module-path name)))))))
    (unless (<= 200 (response-code response) 299)
      (error "roost dev: cannot load module" name))
    (let ((forms (read-forms (response-body response))))
      (record-forms! name forms)
      (load-module root forms))))

;; Hiccup nodes are vectors whose first element is a tag or a component; the REPL
;; panel renders them rather than printing them.
(define (hiccup-node? value)
  (and (vector? value)
       (> (vector-length value) 0)
       (let ((type (vector-ref value 0)))
         (or (string? type) (procedure? type) (js/value? type)))))

(define (exception-text e)
  (let ((port (open-output-string)))
    (format-exception e port)
    (get-output-string port)))

;; The panel's previews render with React, in a root made on first use. Converting a
;; node walks its whole tree at once, so a malformed node fails at once; components
;; fail while React renders, in onUncaughtError.
(define preview-root #f)
(define report-preview-error (lambda (message) #f))

(define (render-preview value element report)
  (set! report-preview-error report)
  (unless preview-root
    (set! preview-root
          (js/method (js/module "react-dom/client") "createRoot" element
                     (js/object "onUncaughtError"
                                (js/function (lambda (error info)
                                               (report-preview-error (js/ref error "message")))
                                             2)))))
  (guard (e (#t (js/method preview-root "render" #f) (report (exception-text e))))
    (js/method preview-root "render" (js/from-scheme value))))

;; Returns a procedure for Hoot's call_async: load the main module, whose body
;; renders the page, mount the REPL panel, then serve REPL clients.
(define (start base main-module)
  (lambda (resolved rejected)
    (call-with-async-result
     resolved rejected
     (lambda ()
       (parameterize ((current-repl-server
                       (string-append (js/ref js/global "location" "origin") base))
                      (current-module-loader load-from-server))
         (resolve-module (the-root-module) main-module #:load? #t)
         (mount-devtools! (resolve-module (the-root-module) main-module)
                          module-forms hiccup-node? render-preview)
         (run-web-repl))))))

(define (form-head datum)
  (and (pair? datum) (car datum)))

;; The name a top-level form defines, if any.
(define (defined-name datum)
  (and (eq? (form-head datum) 'define)
       (pair? (cdr datum))
       (let ((target (cadr datum)))
         (cond
          ((symbol? target) target)
          ((and (pair? target) (symbol? (car target))) (car target))
          (else #f)))))

(define (binding module name)
  (let ((variable (module-local-variable module name)))
    (and variable (variable))))

;; A record type that exists already is kept: values in the running application are
;; instances of it. The development server reloads the page when a record changes.
(define (existing-record-type? module datum)
  (and (eq? (form-head datum) 'define-record-type)
       (pair? (cdr datum))
       (symbol? (cadr datum))
       (module-local-variable module (cadr datum))))

;; Evaluates a saved module's definitions in the running module. Components keep their
;; React types, so mounted ones keep their state and show the new definitions.
(define (reload! source)
  (let* ((forms (read-forms (open-input-string source)))
         (header (syntax->datum (car forms)))
         (module (resolve-module (the-root-module) (cadr header)))
         (body (filter-forms module (cdr forms)))
         (names (let loop ((forms body) (names '()))
                  (if (null? forms)
                      names
                      (let ((name (defined-name (syntax->datum (car forms)))))
                        (loop (cdr forms) (if name (cons name names) names))))))
         (old (map (lambda (name) (binding module name)) names)))
    (record-forms! (cadr header) forms)
    (for-each (lambda (form) (eval form module)) body)
    (for-each (lambda (name old)
                (let ((new (binding module name)))
                  (when (and (procedure? old) (procedure? new))
                    (transfer-component! old new))))
              names old)
    (refresh-roots!)))

(define (filter-forms module forms)
  (let loop ((forms forms) (kept '()))
    (cond
     ((null? forms) (reverse kept))
     ((existing-record-type? module (syntax->datum (car forms))) (loop (cdr forms) kept))
     (else (loop (cdr forms) (cons (car forms) kept))))))

;; The development shell's program: (values start reload!).
(define (dev-program base main-module)
  (values (start base main-module) reload!))
