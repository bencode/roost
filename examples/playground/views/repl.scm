;; The REPL pane: a log of what ran and what it printed, and an input that evaluates in
;; the playground's module. Values that are Hiccup render in the log.
(define-module (views repl)
  #:pure
  #:export (repl-pane input-entry output-entry problem-entry resolve-problems)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost hooks) #:select (use-state use-effect use-ref))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools editor) #:select (editor-set-text!))
  #:use-module ((roost devtools preview) #:select (render-isolated))
  #:use-module ((views code) #:select (code-editor)))

(define history-limit 100)

;; kind: input, output, or error (the REPL's own report). previews: values to render, last
;; first.
(define-record-type <entry>
  (make-entry kind text previews)
  entry?
  (kind entry-kind)
  (text entry-text)
  (previews entry-previews))

;; A problem with the module or a component. kind: read, load, run, or render; where:
;; "line:column", or #f; span: what to select in the editor, or #f; detail: the full
;; conditions; resolved?: a later run succeeded.
(define-record-type <problem>
  (make-problem kind where span summary detail resolved?)
  problem?
  (kind problem-kind)
  (where problem-where)
  (span problem-span)
  (summary problem-summary)
  (detail problem-detail)
  (resolved? problem-resolved?))

(define (problem-entry kind where span summary detail)
  (make-problem kind where span summary detail #f))

(define (resolve-problems entries)
  (map (lambda (entry)
         (if (problem? entry)
             (make-problem (problem-kind entry) (problem-where entry) (problem-span entry)
                           (problem-summary entry) (problem-detail entry) #t)
             entry))
       entries))

(define (input-entry prompt text) (make-entry 'input (string-append prompt text) '()))

;; What the REPL printed; it reports its own errors in the text.
(define (output-entry text previews)
  (make-entry (if (or (js/method text "includes" "Scheme error:")
                      (js/method text "includes" "While reading input:"))
                  'error
                  'output)
              text previews))

;; A value rendered in a React root of its own, so a failing component stays in its entry.
(define (preview-node attributes)
  (let-props attributes (value)
    (let ((element (use-ref #f))
          (error-text (use-ref #f)))
      (use-effect
       (lambda ()
         (let ((root (render-isolated value (js/ref element "current")
                                      (lambda (message)
                                        (js/set! (js/ref error-text "current") "textContent" message)))))
           ;; React cannot unmount a root while it renders another; wait until it is done.
           (lambda () (js/method js/global "setTimeout" (lambda () (js/method root "unmount")) 0))))
       (list value))
      (h/div (props #:class "preview-value")
             (h/div (props #:ref element))
             (h/pre (props #:class "error" #:ref error-text))))))

;; on-locate receives a span to select in the editor.
(define (problem-view attributes)
  (let-props attributes (problem on-locate)
    (h/div
     (props #:class (if (problem-resolved? problem) "entry problem resolved" "entry problem"))
     (h/div (props #:class "problem-line")
            (h/span (props #:class "problem-kind") (symbol->string (problem-kind problem)) " error")
            (and (problem-where problem)
                 (h/button (props #:type "button"
                                  #:class "where"
                                  #:title "Show it in the editor"
                                  #:on-click (lambda (event) (on-locate (problem-span problem))))
                           (problem-where problem)))
            (h/span (props #:class "problem-summary") (problem-summary problem)))
     (and (not (string=? "" (problem-detail problem)))
          (h/details (h/summary "conditions") (h/pre (problem-detail problem)))))))

(define (entry-view attributes)
  (let-props attributes (entry)
    (h/div (props #:class (string-append "entry entry-" (symbol->string (entry-kind entry))))
           (and (not (string=? "" (entry-text entry)))
                (h/pre (entry-text entry)))
           (map (lambda (value i) (component preview-node (props #:key i #:value value)))
                (reverse (entry-previews entry))
                (iota (length (entry-previews entry)))))))

(define (iota n)
  (let loop ((i (- n 1)) (numbers '()))
    (if (< i 0) numbers (loop (- i 1) (cons i numbers)))))

(define (take items n)
  (if (or (= n 0) (null? items)) '() (cons (car items) (take (cdr items) (- n 1)))))

;; on-eval receives the input's text; on-locate a problem's span. Mod-↑ and Mod-↓ walk
;; through the inputs run.
(define (repl-pane attributes)
  (let-props attributes (entries prompt names on-eval on-locate)
    (let-values (((history set-history!) (use-state '()))
                 ((cursor set-cursor!) (use-state #f)))
      (let ((input (use-ref #f))
            (log (use-ref #f)))
        (define (run! text)
          (unless (string=? "" (js/method text "trim"))
            (on-eval text)
            (set-history! (take (cons text (if (and (pair? history) (string=? text (car history)))
                                               (cdr history)
                                               history))
                                history-limit))
            (set-cursor! #f)
            (editor-set-text! (js/ref input "current") "")))
        ;; -1 goes back in the history, 1 forward; past the newest input, it empties.
        (define (browse! step)
          (let* ((count (length history))
                 (next (cond
                        ((= count 0) #f)
                        ((not cursor) (and (< step 0) 0))
                        (else (let ((i (- cursor step))) (and (>= i 0) (min i (- count 1))))))))
            (set-cursor! next)
            (editor-set-text! (js/ref input "current") (if next (list-ref history next) ""))))
        (use-effect (lambda ()
                      (let ((element (js/ref log "current")))
                        (js/set! element "scrollTop" (js/ref element "scrollHeight"))))
                    (list entries))
        (h/section
         (props #:class "repl")
         (h/div (props #:class "log" #:ref log)
                (h/div (props #:class "entry intro")
                       (h/pre "The REPL runs in the module. Mod-Enter evaluates; "
                              "Mod-↑/↓ walk the history; ,help lists commands."))
                (map (lambda (entry i)
                       (if (problem? entry)
                           (component problem-view (props #:key i #:problem entry #:on-locate on-locate))
                           (component entry-view (props #:key i #:entry entry))))
                     entries (iota (length entries))))
         (h/div (props #:class "prompt-line")
                (h/span (props #:class "prompt") prompt)
                (component code-editor
                           (props #:view input
                                  #:class "code repl-input"
                                  #:placeholder "expression, then Mod-Enter"
                                  #:wrap? #t
                                  #:names names
                                  #:keys (list (cons "Mod-Enter" run!)
                                               (cons "Mod-ArrowUp" (lambda (text) (browse! -1)))
                                               (cons "Mod-ArrowDown" (lambda (text) (browse! 1))))))))))))
