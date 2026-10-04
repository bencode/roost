;; A Scheme editor: CodeMirror 6, driven from Scheme through (roost js).
(define-module (roost devtools editor)
  #:pure
  #:export (make-editor editor-text editor-set-text! editor-select! editor-focus!)
  #:use-module (scheme base)
  #:use-module (scheme lazy)
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools completion) #:select (completion-source)))

(define (view-module) (js/module "@codemirror/view"))
(define (commands) (js/module "@codemirror/commands"))
(define (language) (js/module "@codemirror/language"))
(define (autocomplete) (js/module "@codemirror/autocomplete"))
(define (highlight) (js/module "@lezer/highlight"))

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

;; Highlighting. CodeMirror's Scheme mode tags define and car alike, and leaves #:keys
;; and bracket depth untagged; this wraps its tokenizer to tell them apart.

(define special-forms
  '("define" "define-module" "define-record-type" "define-syntax" "define-values" "lambda"
    "case-lambda" "let" "let*" "letrec" "letrec*" "let-values" "let*-values" "let-props" "if"
    "cond" "case" "when" "unless" "and" "or" "begin" "do" "quote" "quasiquote" "set!" "guard"
    "parameterize" "syntax-rules" "else" "import"))

;; Tags the Scheme mode has no names for: #:keys, and brackets by depth. Lazy, as every
;; JavaScript value here: Hoot evaluates library bodies at expansion time.
(define extra-tags
  (delay (let ((define-tag (lambda () (js/method (js/ref (highlight) "Tag") "define"))))
           (js/object "keywordArg" (define-tag)
                      "paren0" (define-tag) "paren1" (define-tag)
                      "paren2" (define-tag) "paren3" (define-tag)))))

(define keyword-arg-pattern
  (delay (js/new (js/ref js/global "RegExp") "^#:[^\\s()\\[\\];\"]+")))

;; How many brackets are open: the Scheme mode keeps them in a linked stack.
(define (open-brackets state)
  (let loop ((frame (js/ref state "indentStack")) (n 0))
    (if frame (loop (js/ref frame "prev") (+ n 1)) n)))

;; An opening bracket counts after the mode pushed it, a closing one before it popped.
(define (paren-style stream state)
  (let* ((open? (member (js/method stream "current") '("(" "[")))
         (level (if open? (- (open-brackets state) 1) (open-brackets state))))
    (string-append "paren" (number->string (modulo (max level 0) 4)))))

(define (tokenizer scheme-token)
  (js/function
   (lambda (stream state)
     (if (js/method stream "match" (force keyword-arg-pattern))
         "keywordArg"
         (let ((style (scheme-token stream state)))
           (cond
            ((equal? style "bracket") (paren-style stream state))
            ((and (member style '("builtin" "variable"))
                  (member (js/method stream "current") special-forms))
             "keyword")
            (else style)))))
   2))

(define scheme-language
  (delay (let ((scheme (js/ref (js/module "@codemirror/legacy-modes/mode/scheme") "scheme")))
           (js/method (js/ref (language) "StreamLanguage") "define"
                      (js/method (js/ref js/global "Object") "assign" (js/object) scheme
                                 (js/object "token" (tokenizer (js/ref scheme "token"))
                                            "tokenTable" (force extra-tags)))))))

;; Class names for the tokens, styled by the page: tok-keyword, tok-builtin, ...
(define scheme-highlighter
  (delay (let* ((tags (js/ref (highlight) "tags"))
                (tag (lambda (name) (js/ref tags name)))
                (extra (lambda (name) (js/ref (force extra-tags) name)))
                (rule (lambda (tag class) (js/object "tag" tag "class" class))))
           (js/method (highlight) "tagHighlighter"
                      (js/array (rule (tag "keyword") "tok-keyword")
                                (rule (js/method tags "standard" (tag "variableName")) "tok-builtin")
                                (rule (extra "keywordArg") "tok-keyword-arg")
                                (rule (tag "string") "tok-string")
                                (rule (tag "number") "tok-number")
                                (rule (tag "atom") "tok-atom")
                                (rule (tag "bool") "tok-atom")
                                (rule (tag "comment") "tok-comment")
                                (rule (tag "bracket") "tok-bracket")
                                (rule (extra "paren0") "tok-paren0")
                                (rule (extra "paren1") "tok-paren1")
                                (rule (extra "paren2") "tok-paren2")
                                (rule (extra "paren3") "tok-paren3"))))))

;; A binding whose command always handles the key; the command receives the text.
(define (binding key command)
  (js/object "key" key "run" (js/function (lambda (view) (command (editor-text view)) #t) 1)))

;; Creates the editor in parent, its styles going into root (a shadow root or the
;; document). keys: (key . command) pairs, such as ("Mod-Enter" . run!), taking
;; precedence over the default keys; each command receives the editor's text. names
;; returns the names to complete. wrap?: wrap long lines rather than scroll. Returns the
;; CodeMirror view.
(define (make-editor parent root keys names placeholder wrap?)
  (let* ((view (view-module))
         (keymap (js/ref view "keymap"))
         (EditorView (js/ref view "EditorView"))
         (own-keys (js/method keymap "of"
                              (apply js/array (map (lambda (key) (binding (car key) (cdr key))) keys))))
         (default-keys (js/method (js/ref (autocomplete) "closeBracketsKeymap") "concat"
                                  (js/ref (commands) "defaultKeymap")
                                  (js/ref (commands) "historyKeymap")
                                  (js/ref (autocomplete) "completionKeymap"))))
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
              (if wrap? (js/ref EditorView "lineWrapping") (js/array))
              (force scheme-language)
              (js/method (language) "syntaxHighlighting" (force scheme-highlighter))
              (js/method (language) "bracketMatching")
              (js/method (autocomplete) "closeBrackets")
              (js/method (autocomplete) "autocompletion"
                         (js/object "override" (js/array (completion-source names))))
              (js/method keymap "of" default-keys))))))
