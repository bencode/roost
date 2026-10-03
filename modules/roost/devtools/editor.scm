;; The REPL panel's input: CodeMirror 6, driven from Scheme through (roost js).
(define-module (roost devtools editor)
  #:pure
  #:export (make-editor editor-set-text! editor-focus!)
  #:use-module (scheme base)
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools completion) #:select (completion-source)))

(define (view-module) (js/module "@codemirror/view"))
(define (commands) (js/module "@codemirror/commands"))
(define (language) (js/module "@codemirror/language"))
(define (autocomplete) (js/module "@codemirror/autocomplete"))

(define (editor-text view) (js/method (js/ref view "state" "doc") "toString"))

(define (editor-set-text! view text)
  (js/method view "dispatch"
             (js/object "changes" (js/object "from" 0
                                             "to" (js/ref view "state" "doc" "length")
                                             "insert" text)
                        "selection" (js/object "anchor" (string-length text)))))

(define (editor-focus! view) (js/method view "focus"))

;; A binding whose command always handles the key.
(define (binding key command)
  (js/object "key" key "run" (js/function (lambda (view) (command view) #t) 1)))

;; Creates the editor in parent, its styles going into root (a shadow root).
;; on-run receives the text to evaluate, on-history -1 or 1, and names returns the
;; names to complete. Returns the CodeMirror view.
(define (make-editor parent root on-run on-history names)
  (let* ((view (view-module))
         (keymap (js/ref view "keymap"))
         (EditorView (js/ref view "EditorView"))
         (repl-keys (js/method keymap "of"
                               (js/array
                                (binding "Mod-Enter" (lambda (v) (on-run (editor-text v))))
                                (binding "Mod-ArrowUp" (lambda (v) (on-history -1)))
                                (binding "Mod-ArrowDown" (lambda (v) (on-history 1))))))
         (default-keys (js/method (js/ref (autocomplete) "closeBracketsKeymap") "concat"
                                  (js/ref (commands) "defaultKeymap")
                                  (js/ref (commands) "historyKeymap")
                                  (js/ref (autocomplete) "completionKeymap")))
         (scheme (js/ref (js/module "@codemirror/legacy-modes/mode/scheme") "scheme")))
    (js/new EditorView
            (js/object
             "parent" parent
             "root" root
             "extensions"
             (js/array
              (js/method (js/ref (js/module "@codemirror/state") "Prec") "highest" repl-keys)
              (js/method (commands) "history")
              (js/method view "drawSelection")
              (js/method view "placeholder" "(+ 1 2)   ,m (store cart)   Mod-Enter to run")
              (js/ref EditorView "lineWrapping")
              (js/method (js/ref (language) "StreamLanguage") "define" scheme)
              (js/method (language) "syntaxHighlighting"
                         (js/ref (js/module "@lezer/highlight") "classHighlighter"))
              (js/method (language) "bracketMatching")
              (js/method (autocomplete) "closeBrackets")
              (js/method (autocomplete) "autocompletion"
                         (js/object "override" (js/array (completion-source names))))
              (js/method keymap "of" default-keys))))))
