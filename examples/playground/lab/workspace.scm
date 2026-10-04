;; The playground's evaluation: one module written in the editor, run as a whole, and a
;; REPL session in it. Nothing here uses React.
(define-module (lab workspace)
  #:pure
  #:export (make-workspace workspace-run! workspace-eval! workspace-prompt workspace-names)
  #:use-module (scheme base)
  #:use-module ((scheme read) #:select (read))
  #:use-module ((hoot modules) #:select (the-root-module current-module-loader))
  #:use-module ((hoot hackable) #:select (load-module))
  #:use-module ((roost devtools modules) #:select (sources record-source! module-structure evaluate!))
  #:use-module ((roost devtools preview) #:select (hiccup-node? exception-text))
  #:use-module ((roost devtools session) #:select (make-session session-run! session-prompt
                                                   session-module session-defined-names))
  #:use-module ((roost devtools commands) #:select (repl-commands))
  #:use-module ((roost devtools sources) #:select (source-forms-of))
  #:use-module ((roost devtools completion) #:select (visible-names)))

;; module: the running module, once its header has loaded; structure: its header and
;; record types, which running it again cannot change; session: the REPL in it.
(define-record-type <workspace>
  (%make-workspace module structure session)
  workspace?
  (module workspace-module set-workspace-module!)
  (structure workspace-structure set-workspace-structure!)
  (session workspace-session set-workspace-session!))

(define (make-workspace) (%make-workspace #f #f #f))

;; Only the libraries compiled into the playground can be imported.
(define (loader root name)
  (error "playground: only the bundled libraries can be imported:" name))

(define (module-header? datum)
  (and (pair? datum) (eq? (car datum) 'define-module) (pair? (cdr datum))))

;; Runs text, a whole module. Returns one of:
;;   #(ok count)            count forms ran
;;   #(error span message)  span: the failing form's (start . end), or #f
;;   #(reload)              the header or a record type changed: the page must reload
(define (workspace-run! workspace text)
  (guard (e (#t (vector 'error #f (exception-text e))))
    (parameterize ((current-module-loader loader))
      (let ((name (let ((port (open-input-string text)))
                    (let ((first (read port)))
                      (unless (and (not (eof-object? first)) (module-header? first))
                        (error "playground: the module starts with (define-module (playground) …)"))
                      (cadr first)))))
        (call-with-values (lambda () (record-source! name text))
          (lambda (forms spans)
            (let ((structure (module-structure forms)))
              (cond
               ((not (workspace-module workspace))
                (let ((module (load-module (the-root-module) (list (car forms)))))
                  (set-workspace-module! workspace module)
                  (set-workspace-structure! workspace structure)
                  (set-workspace-session! workspace
                                          (make-session module hiccup-node? (repl-commands sources) loader))
                  (finish (evaluate! module (cdr forms)) forms spans)))
               ((equal? structure (workspace-structure workspace))
                (finish (evaluate! (workspace-module workspace) (cdr forms)) forms spans))
               (else (vector 'reload))))))))))

(define (finish failure forms spans)
  (if failure
      (vector 'error (list-ref spans (+ (car failure) 1)) (exception-text (cdr failure)))
      (vector 'ok (length forms))))

;; Evaluates REPL input in the module. Returns #(output previews), as session-run!.
(define (workspace-eval! workspace text)
  (let ((session (workspace-session workspace)))
    (if session
        (session-run! session text)
        (vector "Run the module first: Mod-Enter in the editor.\n" '()))))

(define (workspace-prompt workspace)
  (let ((session (workspace-session workspace)))
    (if session (session-prompt session) "> ")))

;; The names the module sees, and those the REPL defined, for completion.
(define (workspace-names workspace)
  (let ((session (workspace-session workspace)))
    (if session
        (visible-names (source-forms-of (sources) (session-module session))
                       (session-defined-names session))
        '())))
