;; Live development. A development shell compiles Roost with Hoot's run-time module
;; system; the application's modules are loaded from source by the interpreter, so
;; saving one evaluates its definitions again in the running page.
(define-module (roost dev)
  #:pure
  #:export (dev-program)
  #:use-module (scheme base)
  #:use-module (scheme write)
  #:use-module ((hoot modules) #:select (the-root-module resolve-module module-local-variable
                                         current-module-loader))
  #:use-module ((hoot hackable) #:select (load-module))
  #:use-module ((hoot eval) #:select (eval))
  #:use-module ((hoot read) #:select (read read-syntax))
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

;; Loads application modules from the development server: <server>/repl/load/a/b.
(define (load-from-server root name)
  (let ((response (fetch (build-request
                          (string->uri (string-append (current-repl-server) "/repl/load"
                                                      (module-path name)))))))
    (unless (<= 200 (response-code response) 299)
      (error "roost dev: cannot load module" name))
    (load-module root (read-forms (response-body response)))))

;; The application's modules, as text, from <server>/modules.
(define (module-names)
  (let ((response (fetch (build-request (string->uri (string-append (current-repl-server) "/modules"))))))
    (unless (<= 200 (response-code response) 299)
      (error "roost dev: cannot list modules"))
    (map (lambda (name)
           (let ((port (open-output-string)))
             (write name port)
             (get-output-string port)))
         (read (response-body response)))))

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
         (mount-devtools! (module-names))
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
