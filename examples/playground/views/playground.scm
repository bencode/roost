;; The playground: the module's editor, the REPL under it, and the preview beside them,
;; with a toolbar and a status line.
(define-module (views playground)
  #:pure
  #:export (playground)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost hooks) #:select (use-state use-effect use-ref))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools editor) #:select (editor-text editor-set-text! editor-select!))
  #:use-module (lab workspace)
  #:use-module (lab draft)
  #:use-module ((views code) #:select (code-editor))
  #:use-module ((views repl) #:select (repl-pane input-entry output-entry error-entry))
  #:use-module ((views split) #:select (split-handle)))

(define starters '("counter" "todos" "clock" "router"))
(define source-url "https://github.com/bencode/roost")

(define (now) (js/method (js/ref js/global "performance") "now"))
(define (reload-page!) (js/method (js/ref js/global "location") "reload"))
(define (percent ratio) (string-append (number->string (* 100 ratio)) "%"))

(define (button label title on-click)
  (h/button (props #:type "button" #:title title #:on-click (lambda (event) (on-click))) label))

;; The text to start from: a shared link's code, else the draft, else a starter. A link
;; replaces a different draft only when the reader agrees.
(define (initial-text k)
  (let ((shared (shared-text))
        (draft (load-draft)))
    (clear-shared!)
    (cond
     ((and shared
           (or (not draft)
               (string=? draft shared)
               (js/method js/global "confirm" "Replace your draft with the shared code?")))
      (k shared))
     (draft (k draft))
     (else (fetch-starter (car starters) k)))))

(define (playground attributes)
  (let-props attributes (workspace)
    (let-values (((entries set-entries!) (use-state '()))
                 ((status set-status!) (use-state (cons 'busy "loading the module")))
                 ((tab set-tab!) (use-state 'code))
                 ((layout set-layout!) (use-state load-layout)))
      (let ((editor (use-ref #f)))
        (define (log! . new) (set-entries! (lambda (entries) (append entries new))))
        (define (text) (editor-text (js/ref editor "current")))

        (define (run! text)
          (let* ((start (now))
                 (result (workspace-run! workspace text))
                 (ms (exact (round (- (now) start)))))
            (save-draft! text)
            (case (vector-ref result 0)
              ((ok) (set-status! (cons 'ready (string-append "ran " (number->string (vector-ref result 1))
                                                             " forms · " (number->string ms) " ms"))))
              ((error)
               (let ((span (vector-ref result 1)))
                 (set-status! (cons 'error "the module raised an error"))
                 (log! (error-entry (vector-ref result 2)))
                 (when span (editor-select! (js/ref editor "current") (car span) (cdr span)))))
              ((reload) (reload-page!)))))

        (define (load! text)
          (editor-set-text! (js/ref editor "current") text)
          (editor-select! (js/ref editor "current") 0 0)
          (run! text))

        (define (eval! text)
          (let* ((prompt (workspace-prompt workspace))
                 (result (workspace-eval! workspace text)))
            (log! (input-entry prompt text)
                  (output-entry (vector-ref result 0) (vector-ref result 1)))))

        (define (share!)
          (js/method (js/ref js/global "navigator" "clipboard") "writeText" (share-url (text)))
          (set-status! (cons 'ready "link copied: it carries the code")))

        (define (reset!)
          (save-draft! (text))
          (reload-page!))

        (use-effect (lambda () (initial-text load!)) '())

        (h/div
         (props #:class (string-append "playground tab-" (symbol->string tab))
                #:style (props #:grid-template-columns (string-append (percent (car layout)) " 6px 1fr")))
         (h/header
          (props #:class "toolbar")
          (h/span (props #:class "brand") "λ roost/playground")
          (h/select (props #:aria-label "Starter"
                           #:value ""
                           #:on-change (lambda (event)
                                         (fetch-starter (js/ref event "target" "value") load!)))
                    (h/option (props #:value "" #:disabled #t) "starters…")
                    (map (lambda (name) (h/option (props #:key name #:value name) name)) starters))
          (button "▶ run" "Run the module (Mod-Enter)" (lambda () (run! (text))))
          (button "⇪ share" "Copy a link that carries the code" share!)
          (button "↺ reset" "Reload: clears the preview's state" reset!)
          (h/nav (props #:class "tabs")
                 (map (lambda (name)
                        (h/button (props #:key (symbol->string name)
                                         #:type "button"
                                         #:class (if (eq? tab name) "on" "")
                                         #:on-click (lambda (event) (set-tab! name)))
                                  (symbol->string name)))
                      '(code repl preview)))
          (h/a (props #:class "source" #:href source-url) "github"))
         (h/div
          (props #:class "left"
                 #:style (props #:grid-template-rows (string-append (percent (cdr layout)) " 6px 1fr")))
          (component code-editor
                     (props #:view editor
                            #:class "code module"
                            #:names (lambda () (workspace-names workspace))
                            #:keys (list (cons "Mod-Enter" run!) (cons "Mod-s" run!))))
          (component split-handle
                     (props #:direction 'rows
                            #:on-ratio (lambda (ratio) (set-layout! (cons (car layout) ratio)))
                            #:on-done (lambda () (save-layout! layout))))
          (component repl-pane
                     (props #:entries entries
                            #:prompt (workspace-prompt workspace)
                            #:names (lambda () (workspace-names workspace))
                            #:on-eval eval!)))
         (component split-handle
                    (props #:direction 'columns
                           #:on-ratio (lambda (ratio) (set-layout! (cons ratio (cdr layout))))
                           #:on-done (lambda () (save-layout! layout))))
         ;; The module renders into #root; React never renders children into it.
         (h/main (props #:class "preview") (h/div (props #:id "root")))
         (h/footer
          (props #:class (string-append "status " (symbol->string (car status))))
          (h/span (props #:class "light") "●")
          (h/span (cdr status))
          (h/span (props #:class "spacer"))
          (h/span "interpreted · Hoot")))))))
