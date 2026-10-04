;; Live development. A development shell compiles Roost with Hoot's run-time module
;; system; the application's modules are loaded from source by the interpreter, so
;; saving one evaluates its definitions again in the running page.
(define-module (roost dev)
  #:pure
  #:export (dev-program)
  #:use-module (scheme base)
  #:use-module ((hoot modules) #:select (the-root-module resolve-module current-module-loader))
  #:use-module ((hoot hackable) #:select (load-module))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools modules) #:select (sources record-source! reload!))
  #:use-module ((roost devtools session) #:select (make-session))
  #:use-module ((roost devtools commands) #:select (repl-commands))
  #:use-module ((roost devtools remote) #:select (connect-terminals!)))

(define (module-path name)
  (let loop ((parts (map symbol->string name)) (path ""))
    (if (null? parts)
        path
        (loop (cdr parts) (string-append path "/" (car parts))))))

;; Loads application modules from the development server at base: <base>/repl/load/a/b.
;; The request is synchronous, so the REPL can load a module while it evaluates.
(define (load-from-server base)
  (lambda (root name)
    (let ((request (js/new (js/ref js/global "XMLHttpRequest"))))
      (js/method request "open" "GET" (string-append base "/repl/load" (module-path name)) #f)
      (js/method request "send")
      (unless (<= 200 (js/ref request "status") 299)
        (error "roost dev: cannot load module" name))
      (call-with-values (lambda () (record-source! name (js/ref request "responseText")))
        (lambda (forms spans) (load-module root forms))))))

;; Returns the shell's start: load the main module, whose body renders the page, then
;; connect terminal REPLs through the development server. Each starts in the main module.
(define (start base main-module)
  (lambda ()
    (let* ((origin (js/ref js/global "location" "origin"))
           (loader (load-from-server (string-append origin base))))
      (parameterize ((current-module-loader loader))
        (resolve-module (the-root-module) main-module #:load? #t))
      (let ((module (resolve-module (the-root-module) main-module)))
        (connect-terminals!
         ;; http://host → ws://host, https://host → wss://host
         (string-append "ws" (substring origin 4 (string-length origin)) base "/repl")
         (lambda () (make-session module (lambda (value) #f) (repl-commands sources) loader)))))))

;; The development shell's program: (values start reload!).
(define (dev-program base main-module)
  (values (start base main-module) reload!))
