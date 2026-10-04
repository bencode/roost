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
  #:use-module ((roost devtools editor) #:select (editor-text editor-set-text! editor-select!
                                                  editor-focus!))
  #:use-module (lab workspace)
  #:use-module (lab draft)
  #:use-module ((views code) #:select (code-editor))
  #:use-module ((views repl) #:select (repl-pane input-entry output-entry problem-entry
                                       resolve-problems))
  #:use-module ((views split) #:select (split-handle)))

(define starters '("counter" "todos" "clock" "router"))
(define source-url "https://github.com/bencode/roost")

(define (now) (js/method (js/ref js/global "performance") "now"))
(define (reload-page!) (js/method (js/ref js/global "location") "reload"))
(define (percent ratio) (string-append (number->string (* 100 ratio)) "%"))

;; "12:03:04"
(define (clock-time)
  (js/method (js/method (js/new (js/ref js/global "Date")) "toTimeString") "slice" 0 8))

(define (mac?) (js/method (js/ref js/global "navigator" "platform") "startsWith" "Mac"))

;; "line:column" of offset in text, both from 1.
(define (line-column text offset)
  (let loop ((i 0) (line 1) (column 1))
    (cond
     ((= i offset) (string-append (number->string line) ":" (number->string column)))
     ((char=? (string-ref text i) #\newline) (loop (+ i 1) (+ line 1) 1))
     (else (loop (+ i 1) line (+ column 1))))))

(define (button label title on-click)
  (h/button (props #:type "button" #:title title #:on-click (lambda (event) (on-click))) label))

;; The text to start from: a shared link's code, else the draft, else a starter. A link
;; replaces a different draft only when the reader agrees. on-shared receives a link's
;; code, which does not run until the reader runs it: it can call any JavaScript.
(define (initial-text on-shared on-own on-fail)
  (let ((shared (shared-text))
        (draft (load-draft)))
    (clear-shared!)
    (cond
     ((and shared
           (or (not draft)
               (string=? draft shared)
               (js/method js/global "confirm" "Replace your draft with the shared code?")))
      (on-shared shared))
     (draft (on-own draft))
     (else (fetch-starter (car starters) on-own on-fail)))))

;; starter: the starter picked last, or "" when the code came from elsewhere.
(define (toolbar attributes)
  (let-props attributes (starter tab on-starter on-run on-share on-reset on-tab)
    (h/header
     (props #:class "toolbar")
     (h/span (props #:class "brand") (h/b "λ") " roost/playground")
     (h/select (props #:aria-label "Starter"
                      #:value starter
                      #:on-change (lambda (event) (on-starter (js/ref event "target" "value"))))
               (h/option (props #:value "" #:disabled #t) "starters…")
               (map (lambda (name) (h/option (props #:key name #:value name) name)) starters))
     (h/button (props #:type "button" #:class "primary" #:title "Run the module" #:on-click (lambda (event) (on-run)))
               "run" (h/kbd (if (mac?) "⌘↵" "Ctrl↵")))
     (button "share" "Copy a link that carries the code" on-share)
     (button "reset" "Reload the page: clears the preview's state" on-reset)
     (h/nav (props #:class "tabs")
            (map (lambda (name)
                   (h/button (props #:key (symbol->string name)
                                    #:type "button"
                                    #:class (if (eq? tab name) "on" "")
                                    #:on-click (lambda (event) (on-tab name)))
                             (symbol->string name)))
                 '(code repl preview)))
     (h/a (props #:class "source" #:href source-url) "github"))))

;; The module renders into #root; React never renders children into it. stale: #f, or
;; why the preview is out of date: run (a failed run left the last good render) or render
;; (React dropped the page a component failed in).
(define (preview-pane attributes)
  (let-props attributes (stale rendered)
    (h/main
     (props #:class (if stale "preview stale" "preview"))
     (h/div (props #:class "preview-bar")
            (h/span (props #:class "dot"))
            (h/span "preview · #root")
            (h/span (props #:class "spacer"))
            (h/span (cond ((eq? stale 'render) "render failed: fix it and run")
                          (stale "last good render")
                          (rendered (string-append "rendered " rendered))
                          (else ""))))
     (h/div (props #:class "canvas") (h/div (props #:id "root"))))))

(define (status-bar attributes)
  (let-props attributes (status)
    (h/footer
     (props #:class (string-append "status " (symbol->string (car status)))
            #:role "status"
            #:aria-live "polite")
     (h/span (props #:class "dot"))
     (h/span (props #:class "message") (cdr status))
     (h/span (props #:class "spacer"))
     (h/span "interpreted · Hoot"))))

(define (playground attributes)
  (let-props attributes (workspace)
    (let-values (((entries set-entries!) (use-state '()))
                 ((status set-status!) (use-state (cons 'busy "loading the module")))
                 ((tab set-tab!) (use-state 'code))
                 ((layout set-layout!) (use-state load-layout))
                 ((starter set-starter!) (use-state ""))
                 ((stale set-stale!) (use-state #f))
                 ((rendered set-rendered!) (use-state #f)))
      (let ((editor (use-ref #f)))
        (define (log! . new) (set-entries! (lambda (entries) (append entries new))))
        (define (current-text) (editor-text (js/ref editor "current")))

        (define (locate! span)
          (editor-select! (js/ref editor "current") (car span) (cdr span))
          (editor-focus! (js/ref editor "current")))

        (define (fail! kind summary detail span text)
          (set-stale! (if (eq? kind 'render) 'render 'run))
          (set-status! (cons 'error (string-append (symbol->string kind) " error: " summary)))
          (log! (problem-entry kind (and span (line-column text (car span))) span summary detail))
          (when span (locate! span)))

        (define (run! text)
          (let* ((start (now))
                 (result (workspace-run! workspace text))
                 (ms (number->string (exact (round (- (now) start))))))
            (save-draft! text)
            (case (vector-ref result 0)
              ((ok)
               (set-stale! #f)
               (set-rendered! (string-append (clock-time) " · " ms " ms"))
               (set-entries! resolve-problems)
               (set-status! (cons 'ready (string-append "ran " (number->string (vector-ref result 1))
                                                        " forms · " ms " ms"))))
              ((error) (fail! (vector-ref result 1) (vector-ref result 3) (vector-ref result 4)
                              (vector-ref result 2) text))
              ((reload) (reload-page!)))))

        (define (show! text)
          (editor-set-text! (js/ref editor "current") text)
          (editor-select! (js/ref editor "current") 0 0))

        (define (load! text)
          (show! text)
          (run! text))

        (define (starter-failed! message)
          (set-status! (cons 'error (string-append "cannot load the starter: " message))))

        (define (pick-starter! name)
          (set-starter! name)
          (fetch-starter name load! starter-failed!))

        (define (eval! text)
          (let* ((prompt (workspace-prompt workspace))
                 (result (workspace-eval! workspace text)))
            (log! (input-entry prompt text)
                  (output-entry (vector-ref result 0) (vector-ref result 1)))))

        (define (share!)
          (let ((copied (js/method (js/ref js/global "navigator" "clipboard") "writeText"
                                   (share-url (current-text)))))
            ;; writeText resolves to undefined, which a callback without a length does
            ;; not receive; this one takes it.
            (js/method (js/method copied "then"
                                  (js/function (lambda (result)
                                                 (set-status! (cons 'ready "link copied: it carries the code")))
                                               1))
                       "catch"
                       (lambda (error)
                         (js/method (js/ref js/global "console") "error" "playground: cannot copy the link" error)
                         (set-status! (cons 'error "cannot copy the link"))))))

        (define (reset!)
          (save-draft! (current-text))
          (reload-page!))

        (use-effect (lambda ()
                      (initial-text (lambda (text)
                                      (show! text)
                                      (set-status! (cons 'ready "shared code: read it, then run")))
                                    load!
                                    starter-failed!))
                    '())

        ;; Components fail while React renders them, outside any run: report those too.
        (use-effect (lambda ()
                      (let ((on-error (lambda (event)
                                        (fail! 'render (js/ref event "message") "" #f ""))))
                        (js/method js/global "addEventListener" "error" on-error)
                        (lambda () (js/method js/global "removeEventListener" "error" on-error))))
                    '())

        (h/div
         (props #:class (string-append "playground tab-" (symbol->string tab))
                #:style (props #:grid-template-columns (string-append (percent (car layout)) " 6px 1fr")))
         (component toolbar (props #:starter starter #:tab tab
                                   #:on-starter pick-starter! #:on-run (lambda () (run! (current-text)))
                                   #:on-share share! #:on-reset reset! #:on-tab set-tab!))
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
                            #:on-eval eval!
                            #:on-locate locate!)))
         (component split-handle
                    (props #:direction 'columns
                           #:on-ratio (lambda (ratio) (set-layout! (cons ratio (cdr layout))))
                           #:on-done (lambda () (save-layout! layout))))
         (component preview-pane (props #:stale stale #:rendered rendered))
         (component status-bar (props #:status status)))))))
