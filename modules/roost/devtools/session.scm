;; A Hoot REPL session driven by text: the same REPL as the terminal's, with its
;; meta-commands (,m ,use ,d ,bt ,q) and its debugging levels, run synchronously so a
;; page can feed it input and show its output.
(define-module (roost devtools session)
  #:pure
  #:export (make-session session-run! session-prompt session-module session-defined-names)
  #:use-module (scheme base)
  #:use-module (scheme write)
  #:use-module ((hoot modules) #:select (module-name current-module-loader))
  #:use-module ((hoot repl) #:select (make-repl make-repl-environment repl-read
                                      repl-eval-with-error-handling repl-prompt repl-welcome
                                      repl-depth repl-environment repl-environment-module
                                      repl-environment-language make-repl-language
                                      repl-language-title repl-language-reader
                                      repl-language-evaluator repl-add-meta-command!
                                      current-repl repl-quit-exception? meta-expression?))
  #:use-module ((hoot error-handling) #:select (format-exception stack-height))
  #:use-module ((hoot syntax-objects) #:select (syntax? syntax->datum))
  #:use-module ((roost devtools completion) #:select (defined-names)))

;; previewable?: values to hand back instead of printing, such as nodes a page can
;; render. loader: the module loader while evaluating. defined: names (strings) the
;; session's input has defined. entry-height: the stack height where the last
;; evaluation began, so a backtrace can leave out the frames that led to it.
(define-record-type <session>
  (%make-session repl previewable? loader defined entry-height)
  session?
  (repl session-repl set-session-repl!)
  (previewable? session-previewable?)
  (loader session-loader)
  (defined session-defined-names set-session-defined-names!)
  (entry-height session-entry-height set-session-entry-height!))

;; Scheme, with an evaluator that notes the stack height where evaluation begins.
(define (noting-entry language session)
  (make-repl-language
   #:title (repl-language-title language)
   #:reader (repl-language-reader language)
   #:evaluator (lambda (exp module)
                 (set-session-entry-height! session (stack-height))
                 ((repl-language-evaluator language) exp module))))

;; module: the module to start in. commands: given the session's entry-height and
;; defined-names thunks, the meta-commands to add (replacing built-in ones of the
;; same name).
(define (make-session module previewable? commands loader)
  (let* ((session (%make-session #f previewable? loader '() 0))
         (scheme (repl-environment-language (make-repl-environment)))
         (repl (make-repl #:environment
                          (make-repl-environment #:language (noting-entry scheme session)
                                                 #:module module))))
    (for-each (lambda (command) (repl-add-meta-command! repl command))
              (commands (lambda () (session-entry-height session))
                        (lambda () (session-defined-names session))))
    (set-session-repl! session repl)
    session))

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
      (for-each (lambda (name)
                  (unless (member name (session-defined-names session))
                    (set-session-defined-names! session (cons name (session-defined-names session)))))
                (map symbol->string (defined-names (list datum)))))))

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
        (display "=> ⟨hiccup⟩\n"))
       (else (display "=> ") (write value) (newline))))
    (parameterize ((current-output-port output)
                   (current-repl repl)
                   (current-module-loader (session-loader session)))
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
