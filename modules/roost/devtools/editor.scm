;; A Scheme editor: CodeMirror 6, driven from Scheme through (roost js).
(define-module (roost devtools editor)
  #:pure
  #:export (make-editor editor-text editor-set-text! editor-select! editor-focus!)
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

;; Selects text from start to end (offsets) and scrolls it into view.
(define (editor-select! view start end)
  (js/method view "dispatch"
             (js/object "selection" (js/object "anchor" start "head" end)
                        "scrollIntoView" #t)))

;; A binding whose command always handles the key; the command receives the text.
(define (binding key command)
  (js/object "key" key "run" (js/function (lambda (view) (command (editor-text view)) #t) 1)))

;; Creates the editor in parent, its styles going into root (a shadow root or the
;; document). keys: (key . command) pairs, such as ("Mod-Enter" . run!), taking
;; precedence over the default keys; each command receives the editor's text. names
;; returns the names to complete. Returns the CodeMirror view.
(define (make-editor parent root keys names placeholder)
  (let* ((view (view-module))
         (keymap (js/ref view "keymap"))
         (EditorView (js/ref view "EditorView"))
         (own-keys (js/method keymap "of"
                              (apply js/array (map (lambda (key) (binding (car key) (cdr key))) keys))))
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
              (js/method (js/ref (js/module "@codemirror/state") "Prec") "highest" own-keys)
              (js/method (commands) "history")
              (js/method view "drawSelection")
              (js/method view "placeholder" placeholder)
              (js/ref EditorView "lineWrapping")
              (js/method (js/ref (language) "StreamLanguage") "define" scheme)
              (js/method (language) "syntaxHighlighting"
                         (js/ref (js/module "@lezer/highlight") "classHighlighter"))
              (js/method (language) "bracketMatching")
              (js/method (autocomplete) "closeBrackets")
              (js/method (autocomplete) "autocompletion"
                         (js/object "override" (js/array (completion-source names))))
              (js/method keymap "of" default-keys))))))
