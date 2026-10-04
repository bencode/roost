;; A Scheme editor as a component: CodeMirror, created in an effect and destroyed when
;; the component unmounts.
(define-module (views code)
  #:pure
  #:export (code-editor)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hooks) #:select (use-effect use-ref))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools editor) #:select (make-editor editor-set-text! editor-select!)))

;; view: a ref the parent owns; it holds the CodeMirror view, to read or change the
;; text. keys: (key . command) pairs; a command receives the text. names returns the
;; names to complete; wrap? wraps long lines. The editor is made once; it calls the latest
;; keys and names.
(define (code-editor attributes)
  (let-props attributes (view (text "") keys names (placeholder "") (class "code") (wrap? #f))
    (let ((parent (use-ref #f))
          (latest (use-ref #f)))
      (use-effect (lambda () (js/set! latest "current" (cons keys names))))
      (use-effect
       (lambda ()
         (let ((editor (make-editor (js/ref parent "current")
                                    (js/ref js/global "document")
                                    (map (lambda (key)
                                           (cons (car key)
                                                 (lambda (text)
                                                   ((cdr (assoc (car key) (car (js/ref latest "current"))))
                                                    text))))
                                         keys)
                                    (lambda () ((cdr (js/ref latest "current"))))
                                    placeholder
                                    wrap?)))
           (editor-set-text! editor text)
           (editor-select! editor 0 0)
           (js/set! view "current" editor)
           (lambda ()
             (js/set! view "current" #f)
             (js/method editor "destroy"))))
       '())
      (h/div (props #:class class #:ref parent)))))
