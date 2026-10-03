;; The REPL panel's editor: CodeMirror 6, driven from Scheme through (roost js).
;; CodeMirror owns its DOM; the component only gives it a container, creates the view
;; once, and keeps the view's text in step with the value it is given.
(define-module (roost devtools editor)
  #:pure
  #:export (editor)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hooks) #:select (use-effect use-ref))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools completion) #:select (completion-source)))

(define (view-module) (js/module "@codemirror/view"))
(define (state-module) (js/module "@codemirror/state"))
(define (commands) (js/module "@codemirror/commands"))
(define (language) (js/module "@codemirror/language"))
(define (autocomplete) (js/module "@codemirror/autocomplete"))

(define (text-of view) (js/method (js/ref view "state" "doc") "toString"))

(define (replace-text! view text)
  (js/method view "dispatch"
             (js/object "changes" (js/object "from" 0
                                             "to" (js/ref view "state" "doc" "length")
                                             "insert" text))))

;; A binding whose command always handles the key.
(define (binding key command)
  (js/object "key" key "run" (js/function (lambda (view) (command view) #t) 1)))

;; handlers: a ref holding #(on-change on-run on-history names), read at each event so
;; the view, created once, always calls the latest ones.
(define (make-view parent root text handlers)
  (define (handler index) (vector-ref (js/ref handlers "current") index))
  (let* ((view (view-module))
         (keymap (js/ref view "keymap"))
         (EditorView (js/ref view "EditorView"))
         (repl-keys (js/method keymap "of"
                               (js/array
                                (binding "Mod-Enter" (lambda (v) ((handler 1) (text-of v))))
                                (binding "Mod-ArrowUp" (lambda (v) ((handler 2) -1)))
                                (binding "Mod-ArrowDown" (lambda (v) ((handler 2) 1))))))
         (default-keys (js/method (js/ref (autocomplete) "closeBracketsKeymap") "concat"
                                  (js/ref (commands) "defaultKeymap")
                                  (js/ref (commands) "historyKeymap")
                                  (js/ref (autocomplete) "completionKeymap")))
         (scheme (js/ref (js/module "@codemirror/legacy-modes/mode/scheme") "scheme")))
    (js/new EditorView
            (js/object
             "parent" parent
             "root" root
             "doc" text
             "extensions"
             (js/array
              (js/method (js/ref (state-module) "Prec") "highest" repl-keys)
              (js/method (commands) "history")
              (js/method view "drawSelection")
              (js/method view "placeholder" "(+ 1 2)   Mod-Enter to run")
              (js/ref EditorView "lineWrapping")
              (js/method (js/ref (language) "StreamLanguage") "define" scheme)
              (js/method (language) "syntaxHighlighting"
                         (js/ref (js/module "@lezer/highlight") "classHighlighter"))
              (js/method (language) "bracketMatching")
              (js/method (autocomplete) "closeBrackets")
              (js/method (autocomplete) "autocompletion"
                         (js/object "override" (js/array (completion-source (lambda () ((handler 3)))))))
              (js/method keymap "of" default-keys)
              (js/method (js/ref EditorView "updateListener") "of"
                         (js/function (lambda (update)
                                        (when (js/ref update "docChanged")
                                          ((handler 0) (text-of (js/ref update "view")))))
                                      1)))))))

;; value: the text; on-change receives new text; on-run receives the text to evaluate;
;; on-history receives -1 or 1; names returns the names to complete; root is the
;; shadow root CodeMirror puts its styles into.
(define (editor attributes)
  (let-props attributes (value on-change on-run on-history names root)
    (let ((container (use-ref #f))
          (view (use-ref #f))
          (handlers (use-ref #f)))
      (js/set! handlers "current" (vector on-change on-run on-history names))
      (use-effect (lambda ()
                    (let ((created (make-view (js/ref container "current") root value handlers)))
                      (js/set! view "current" created)
                      (js/method created "focus")
                      (lambda () (js/method created "destroy"))))
                  '())
      (use-effect (lambda ()
                    (let ((current (js/ref view "current")))
                      (when (and current (not (string=? value (text-of current))))
                        (replace-text! current value))))
                  (list value))
      (h/div (props #:class "editor" #:ref container)))))
