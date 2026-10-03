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
  #:use-module ((hoot read) #:select (read read-syntax))
  #:use-module ((hoot ports) #:select (port-line port-column))
  #:use-module ((hoot error-handling) #:select (format-exception))
  #:use-module ((hoot syntax-objects) #:select (syntax->datum syntax-sourcev))
  #:use-module ((roost react) #:select (transfer-component! refresh-roots!))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools) #:select (mount-devtools!))
  #:use-module ((roost devtools sources) #:select (make-module-source module-source-name))
  #:use-module ((roost devtools completion) #:select (defined-names)))

;; Offsets in text where each line starts.
(define (line-starts text)
  (let loop ((i 0) (starts '(0)))
    (cond
     ((= i (string-length text)) (list->vector (reverse starts)))
     ((char=? (string-ref text i) #\newline) (loop (+ i 1) (cons (+ i 1) starts)))
     (else (loop (+ i 1) starts)))))

;; The top-level forms of text, as syntax, with each one's (start . end) offsets in it.
;; A form without a source position starts where the previous one ended.
(define (read-forms text)
  (let ((port (open-input-string text))
        (starts (line-starts text)))
    (define (offset line column) (+ (vector-ref starts line) column))
    (let loop ((forms '()) (spans '()) (previous-end 0))
      (let ((form (read-syntax port)))
        (if (eof-object? form)
            (values (reverse forms) (reverse spans))
            (let ((source (syntax-sourcev form))
                  (end (offset (port-line port) (port-column port))))
              (loop (cons form forms)
                    (cons (cons (if (vector? source)
                                    (offset (vector-ref source 1) (vector-ref source 2))
                                    previous-end)
                                end)
                          spans)
                    end)))))))

(define (module-path name)
  (let loop ((parts (map symbol->string name)) (path ""))
    (if (null? parts)
        path
        (loop (cdr parts) (string-append path "/" (car parts))))))

;; Each application module's source as it last loaded or reloaded, newest first.
(define loaded-sources '())

(define (sources) loaded-sources)

;; Reads a module's source and records it; returns its forms, as syntax.
(define (record-source! name text)
  (call-with-values (lambda () (read-forms text))
    (lambda (forms spans)
      (set! loaded-sources
            (cons (make-module-source name (map syntax->datum forms) text spans)
                  (filter (lambda (source) (not (equal? (module-source-name source) name)))
                          loaded-sources)))
      forms)))

;; Loads application modules from the development server at base: <base>/repl/load/a/b.
;; The request is synchronous, so the REPL can load a module while it evaluates.
(define (load-from-server base)
  (lambda (root name)
    (let ((request (js/new (js/ref js/global "XMLHttpRequest"))))
      (js/method request "open" "GET" (string-append base "/repl/load" (module-path name)) #f)
      (js/method request "send")
      (unless (<= 200 (js/ref request "status") 299)
        (error "roost dev: cannot load module" name))
      (load-module root (record-source! name (js/ref request "responseText"))))))

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

;; Returns the shell's start: load the main module, whose body renders the page, then
;; mount the REPL panel and connect terminal REPLs through the development server.
(define (start base main-module)
  (lambda ()
    (let* ((origin (js/ref js/global "location" "origin"))
           (loader (load-from-server (string-append origin base))))
      (parameterize ((current-module-loader loader))
        (resolve-module (the-root-module) main-module #:load? #t))
      (mount-devtools! (resolve-module (the-root-module) main-module)
                       sources loader hiccup-node? render-preview
                       ;; http://host → ws://host, https://host → wss://host
                       (string-append "ws" (substring origin 4 (string-length origin)) base "/repl")))))

(define (binding module name)
  (let ((variable (module-local-variable module name)))
    (and variable (variable))))

;; A record type that exists already is kept: values in the running application are
;; instances of it. The development server reloads the page when a record changes.
(define (existing-record-type? module datum)
  (and (pair? datum)
       (eq? (car datum) 'define-record-type)
       (pair? (cdr datum))
       (symbol? (cadr datum))
       (module-local-variable module (cadr datum))))

;; Evaluates a saved module's definitions in the running module. Components keep their
;; React types, so mounted ones keep their state and show the new definitions.
(define (reload! source)
  (let* ((modname (cadr (read (open-input-string source))))   ; (define-module NAME ...)
         (forms (record-source! modname source))
         (module (resolve-module (the-root-module) modname))
         (body (filter (lambda (form) (not (existing-record-type? module (syntax->datum form))))
                       (cdr forms)))
         (names (defined-names (map syntax->datum body)))
         (old (map (lambda (name) (binding module name)) names)))
    (for-each (lambda (form) (eval form module)) body)
    (for-each (lambda (name old)
                (let ((new (binding module name)))
                  (when (and (procedure? old) (procedure? new))
                    (transfer-component! old new))))
              names old)
    (refresh-roots!)))

;; The development shell's program: (values start reload!).
(define (dev-program base main-module)
  (values (start base main-module) reload!))
