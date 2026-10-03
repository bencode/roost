;; A Hoot REPL session driven by text: the same REPL as the terminal's, with its
;; meta-commands (,m ,use ,d ,bt ,q) and its debugging levels, run synchronously so a
;; page can feed it input and show its output.
(define-module (roost devtools session)
  #:pure
  #:export (make-session session-run! session-prompt session-module session-defined-names)
  #:use-module (scheme base)
  #:use-module (scheme write)
  #:use-module ((hoot modules) #:select (module-name))
  #:use-module ((hoot repl) #:select (make-repl make-repl-environment repl-read
                                      repl-eval-with-error-handling repl-prompt repl-welcome
                                      repl-depth repl-environment repl-environment-module
                                      current-repl repl-quit-exception? meta-expression?))
  #:use-module ((hoot error-handling) #:select (format-exception))
  #:use-module ((hoot syntax-objects) #:select (syntax? syntax->datum))
  #:use-module ((roost devtools completion) #:select (defined-names)))

;; previewable?: values to hand back instead of printing, such as nodes a page can
;; render. defined: names (strings) the session's input has defined.
(define-record-type <session>
  (%make-session repl previewable? defined)
  session?
  (repl session-repl)
  (previewable? session-previewable?)
  (defined session-defined-names set-session-defined-names!))

;; module: the module to start in.
(define (make-session module previewable?)
  (%make-session (make-repl #:environment (make-repl-environment #:module module))
                 previewable?
                 '()))

(define (session-prompt session) (repl-prompt (session-repl session)))

;; The name of the module the session evaluates in, such as (store cart).
(define (session-module session)
  (module-name (repl-environment-module (repl-environment (session-repl session)))))

(define unspecified (if #f #f))

;; Reads the next expression, or the end of the input. Input that does not read is
;; reported, as the terminal REPL does, and ends the input.
(define (read-next repl input)
  (guard (e (#t (display "While reading input:\n")
                (format-exception e (current-output-port))
                (eof-object)))
    (repl-read repl input)))

(define (note-definitions! session exp)
  (unless (meta-expression? exp)
    (let ((datum (if (syntax? exp) (syntax->datum exp) exp)))
      (set-session-defined-names! session
                                  (append (map symbol->string (defined-names (list datum)))
                                          (session-defined-names session))))))

;; Evaluates each expression of text. Returns #(output previews): the text the REPL
;; printed, and the previewable values, last first.
(define (session-run! session text)
  (let ((repl (session-repl session))
        (input (open-input-string text))
        (output (open-output-string))
        (previews '()))
    (define (print! value)
      (cond
       ((eq? value unspecified) #f)
       (((session-previewable? session) value)
        (set! previews (cons value previews))
        (display "=> #<preview>\n"))
       (else (display "=> ") (write value) (newline))))
    (parameterize ((current-output-port output)
                   (current-repl repl))
      (let loop ()
        (let ((exp (read-next repl input)))
          (unless (eof-object? exp)
            (let ((depth (repl-depth repl)))
              (call-with-values
                  (lambda ()
                    (guard (e ((repl-quit-exception? e)
                               (display "Already at the top level.\n")
                               (values)))
                      (repl-eval-with-error-handling repl exp)))
                (lambda values (for-each print! values)))
              ;; An error enters a debugging level; say so, as the terminal REPL does.
              (if (> (repl-depth repl) depth)
                  (begin (display (repl-welcome repl)) (newline))
                  (note-definitions! session exp)))
            (loop)))))
    (vector (get-output-string output) previews)))
