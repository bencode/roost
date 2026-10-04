;; The playground's evaluation: one module written in the editor, run as a whole, and a
;; REPL session in it. Nothing here uses React.
(define-module (lab workspace)
  #:pure
  #:export (make-workspace workspace-run! workspace-eval! workspace-prompt workspace-names)
  #:use-module (scheme base)
  #:use-module ((scheme write) #:select (write))
  #:use-module ((hoot modules) #:select (the-root-module current-module-loader))
  #:use-module ((hoot hackable) #:select (load-module))
  #:use-module ((hoot syntax-objects) #:select (syntax->datum))
  #:use-module ((hoot exceptions) #:select (exception-with-origin? exception-origin
                                            exception-with-message? exception-message
                                            exception-with-irritants? exception-irritants))
  #:use-module ((roost devtools modules) #:select (read-forms sources record-source! module-structure
                                                   evaluate!))
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
;;   #(ok count)                          count forms ran
;;   #(error kind span summary detail)    kind: read, load (the header), or run; span: the
;;                                        failing form's (start . end), or #f
;;   #(reload)                            the header or a record type changed: the page
;;                                        must reload
(define (workspace-run! workspace text)
  (parameterize ((current-module-loader loader))
    (attempt 'read #f (lambda () (call-with-values (lambda () (read-forms text)) cons))
      (lambda (read)
        (let ((forms (car read))
              (spans (cdr read)))
          (if (or (null? forms) (not (module-header? (syntax->datum (car forms)))))
              (vector 'error 'load #f "the module starts with (define-module (playground) …)" "")
              (run-module! workspace text forms spans)))))))

(define (run-module! workspace text forms spans)
  (record-source! (cadr (syntax->datum (car forms))) text)
  (let ((structure (module-structure forms))
        (module (workspace-module workspace)))
    (cond
     ((not module)
      (attempt 'load (car spans) (lambda () (load-module (the-root-module) (list (car forms))))
        (lambda (module)
          (set-workspace-module! workspace module)
          (set-workspace-structure! workspace structure)
          (set-workspace-session! workspace
                                  (make-session module hiccup-node? (repl-commands sources) loader))
          (run-body module forms spans))))
     ((equal? structure (workspace-structure workspace)) (run-body module forms spans))
     (else (vector 'reload)))))

(define (run-body module forms spans)
  (attempt 'run #f (lambda () (evaluate! module (cdr forms)))
    (lambda (failure)
      (if failure
          (problem 'run (list-ref spans (+ (car failure) 1)) (cdr failure))
          (vector 'ok (length forms))))))

;; Runs thunk; hands its value to k, or returns the problem it raised.
(define-record-type <raised>
  (raised problem)
  raised?
  (problem raised-problem))

(define (attempt kind span thunk k)
  (let ((result (guard (e (#t (raised (problem kind span e)))) (thunk))))
    (if (raised? result) (raised-problem result) (k result))))

(define (problem kind span e)
  (vector 'error kind span (summary e) (exception-text e)))

;; One line: where, what, and with which values, such as "car: type check failed 1".
(define (summary e)
  (let ((origin (and (exception-with-origin? e) (exception-origin e)))
        (message (and (exception-with-message? e) (exception-message e)))
        (irritants (if (exception-with-irritants? e) (exception-irritants e) '())))
    (if message
        (string-append (if origin (string-append (written origin) ": ") "")
                       (fill-in message irritants))
        (first-condition (exception-text e)))))

;; Some messages are format strings: each ~A or ~S takes the next irritant; the irritants
;; left over follow the message.
(define (fill-in message irritants)
  (let loop ((i 0) (irritants irritants) (parts '()))
    (let ((directive (string-search-from message "~" i)))
      (cond
       ((and directive
             (< (+ directive 1) (string-length message))
             (memv (string-ref message (+ directive 1)) '(#\A #\a #\S #\s))
             (pair? irritants))
        (loop (+ directive 2) (cdr irritants)
              (cons* (written (car irritants)) (substring message i directive) parts)))
       (else
        (apply string-append
               (reverse (append (map (lambda (irritant) (string-append " " (written irritant)))
                                     (reverse irritants))
                                (cons (substring message i (string-length message)) parts)))))))))

(define (cons* a b rest) (cons a (cons b rest)))

(define (written value)
  (if (string? value)
      value
      (let ((port (open-output-string)))
        (write value port)
        (get-output-string port))))

;; The first condition of format-exception's text: "  1. #<&undefined-variable …>".
(define (first-condition text)
  (let* ((start (string-search text "1. "))
         (from (if start (+ start 3) 0))
         (end (or (string-search-from text "\n" from) (string-length text))))
    (substring text from end)))

(define (string-search text part) (string-search-from text part 0))

(define (string-search-from text part from)
  (let ((n (string-length text)) (m (string-length part)))
    (let loop ((i from))
      (cond
       ((> (+ i m) n) #f)
       ((string=? part (substring text i (+ i m))) i)
       (else (loop (+ i 1)))))))

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
