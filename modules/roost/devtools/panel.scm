;; The REPL panel: a toggle button and a floating panel with a module selector, the
;; history of evaluations, a preview of Hiccup results, and an editor.
(define-module (roost devtools panel)
  #:pure
  #:export (devtools)
  #:use-module (scheme base)
  #:use-module ((hoot read) #:select (read))
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost hooks) #:select (use-state use-effect use-ref))
  #:use-module ((roost js) #:prefix js/)
  #:use-module (roost devtools evaluate)
  #:use-module (roost devtools storage)
  #:use-module ((roost devtools editor) #:select (editor))
  #:use-module ((roost devtools completion) #:select (visible-names source-defined-names)))

(define main-module "(roost-dev main)")
(define history-limit 100)

(define (module-label name) (if (string=? name main-module) "main" name))
(define (module-datum name) (read (open-input-string name)))
(define (window) js/global)
(define (event-value event) (js/ref event "target" "value"))

;;; History entries

;; node is the Hiccup result, if any; it is not stored, so restored entries have none.
(define-record-type <entry>
  (make-entry module source output value error node)
  entry?
  (module entry-module)
  (source entry-source)
  (output entry-output)
  (value entry-value)
  (error entry-error)
  (node entry-node))

(define (entry->js entry)
  (js/object "module" (entry-module entry)
             "source" (entry-source entry)
             "output" (entry-output entry)
             "value" (if (entry-node entry) "#<hiccup node>" (entry-value entry))
             "error" (entry-error entry)))

(define (js->entry object)
  (make-entry (js/ref object "module") (js/ref object "source") (js/ref object "output")
              (js/ref object "value") (js/ref object "error") #f))

(define (keep-last n items)
  (let ((extra (- (length items) n)))
    (if (> extra 0) (list-tail items extra) items)))

;;; Components

(define (entry-view attributes)
  (let-props attributes (entry selected? on-pick on-select)
    (h/div
     (props #:class "entry")
     (h/div
      (props #:class "head")
      (h/span (props #:class "source" #:title "Edit again"
                     #:on-click (lambda (event) (on-pick (entry-source entry))))
              (entry-source entry))
      (h/span (props #:class "module") (module-label (entry-module entry)))
      (h/button (props #:class "copy" #:title "Copy the source"
                       #:on-click (lambda (event) (copy-text! (entry-source entry))))
                "copy"))
     (and (entry-output entry) (not (string=? "" (entry-output entry)))
          (h/div (props #:class "output") (entry-output entry)))
     (cond
      ((entry-error entry) (h/pre (props #:class "error") (entry-error entry)))
      ((entry-node entry)
       (h/div (props #:class (if selected? "node selected" "node")
                     #:on-click (lambda (event) (on-select entry)))
              "=> #<hiccup node> preview"))
      ((and (entry-value entry) (not (string=? "" (entry-value entry))))
       (h/div (props #:class "value") (entry-value entry)))
      (else #f)))))

(define (copy-text! text)
  (js/method (js/method (js/ref (window) "navigator" "clipboard") "writeText" text)
             "catch"
             (lambda (error)
               (js/method (js/ref (window) "console") "error" "roost devtools: copy failed" error))))

;; The entries of an association list other than key's.
(define (filter-out key alist)
  (let loop ((alist alist) (kept '()))
    (cond
     ((null? alist) (reverse kept))
     ((equal? (caar alist) key) (loop (cdr alist) kept))
     (else (loop (cdr alist) (cons (car alist) kept))))))

;; Keeps the panel inside the viewport while it is dragged.
(define (clamp-position x y)
  (cons (max 0 (min x (- (js/ref (window) "innerWidth") 80)))
        (max 0 (min y (- (js/ref (window) "innerHeight") 32)))))

;; modules: names of the modules to evaluate in, as text; preview: renders a node (or
;; #f) below the history and reports render errors to its second argument; saved: the
;; stored settings, or #f; module-forms: a module name's top-level forms, or #f;
;; root: the shadow root holding the panel.
(define (devtools attributes)
  (let-props attributes (modules preview saved module-forms root)
    (let-values (((open? set-open!) (use-state (lambda () (setting saved "open" #f))))
                 ((module set-module!)
                  (use-state (lambda ()
                               (let ((name (setting saved "module" main-module)))
                                 (if (member name modules) name main-module)))))
                 ((entries set-entries!)
                  (use-state (lambda () (map js->entry (js/to-scheme (setting saved "entries" (js/array)))))))
                 ((size set-size!)
                  (use-state (lambda () (cons (setting saved "width" 520) (setting saved "height" 420)))))
                 ((position set-position!)
                  (use-state (lambda ()
                               (clamp-position (setting saved "x" (- (js/ref (window) "innerWidth") 536))
                                               (setting saved "y" (- (js/ref (window) "innerHeight") 480))))))
                 ((draft set-draft!) (use-state ""))
                 ((cursor set-cursor!) (use-state #f))
                 ;; Names defined from the panel, per module: ((module name ...) ...).
                 ((defined set-defined!) (use-state '()))
                 ((selected set-selected!) (use-state #f))
                 ((preview-error set-preview-error!) (use-state #f)))
      (let ((drag (use-ref #f))
            (panel (use-ref #f))
            (log (use-ref #f)))

        (define (run! source)
          (unless (string=? "" (js/method source "trim"))
            (let* ((result (evaluate source module))
                   (entry (make-entry module source (result-output result) (result-value result)
                                      (result-error result) (result-node result))))
              (set-entries! (keep-last history-limit (append entries (list entry))))
              (unless (result-error result)
                (set-defined! (lambda (defined)
                                (let ((names (cdr (or (assoc module defined) (list module)))))
                                  (cons (cons module (append (source-defined-names source) names))
                                        (filter-out module defined))))))
              (set-draft! "")
              (set-cursor! #f)
              (when (result-node result)
                (set-preview-error! #f)
                (set-selected! entry)))))

        ;; Ctrl+Up and Ctrl+Down walk through the history.
        (define (browse! step)
          (let* ((count (length entries))
                 (next (cond
                        ((= count 0) #f)
                        ((not cursor) (and (< step 0) (- count 1)))
                        (else (let ((i (+ cursor step))) (and (< i count) (max 0 i)))))))
            (set-cursor! next)
            (set-draft! (if next (entry-source (list-ref entries next)) ""))))

        ;; Completion offers what the module sees, and what the panel defined in it.
        (define (names)
          (visible-names (module-forms (module-datum module))
                         (cdr (or (assoc module defined) (list module)))))

        (define (start-drag event)
          (unless (member (js/ref event "target" "tagName") '("SELECT" "OPTION" "BUTTON"))
            (js/method (js/ref event "currentTarget") "setPointerCapture" (js/ref event "pointerId"))
            (js/set! drag "current" (cons (- (js/ref event "clientX") (car position))
                                          (- (js/ref event "clientY") (cdr position))))))

        (define (move-drag event)
          (let ((offset (js/ref drag "current")))
            (when offset
              (set-position! (clamp-position (- (js/ref event "clientX") (car offset))
                                             (- (js/ref event "clientY") (cdr offset)))))))

        ;; The panel resizes with CSS; its size is read when the pointer is released.
        (define (save-size event)
          (let ((element (js/ref panel "current")))
            (when element
              (let ((width (js/ref element "offsetWidth")) (height (js/ref element "offsetHeight")))
                (unless (and (= width (car size)) (= height (cdr size)))
                  (set-size! (cons width height)))))))

        (use-effect (lambda ()
                      (save-settings! "open" open? "module" module
                                      "x" (car position) "y" (cdr position)
                                      "width" (car size) "height" (cdr size)
                                      "entries" (apply js/array (map entry->js entries))))
                    (list open? module entries position size))

        ;; Ctrl+` shows or hides the panel anywhere on the page.
        (use-effect (lambda ()
                      (let ((document (js/ref (window) "document"))
                            (on-key (lambda (event)
                                      (when (and (js/ref event "ctrlKey") (string=? "`" (js/ref event "key")))
                                        (js/method event "preventDefault")
                                        (set-open! not)))))
                        (js/method document "addEventListener" "keydown" on-key)
                        (lambda () (js/method document "removeEventListener" "keydown" on-key))))
                    '())

        (use-effect (lambda () (preview (and selected (entry-node selected)) set-preview-error!))
                    (list selected))

        (use-effect (lambda ()
                      (let ((element (js/ref log "current")))
                        (when element (js/set! element "scrollTop" (js/ref element "scrollHeight")))))
                    (list entries open?))

        (h/div
         (props #:class "theme")
         (and open?
              (h/section
               (props #:class "panel" #:ref panel #:on-pointer-up save-size
                      #:style (props #:left (car position) #:top (cdr position)
                                     #:width (car size) #:height (cdr size)))
               (h/div
                (props #:class "bar" #:on-pointer-down start-drag #:on-pointer-move move-drag
                       #:on-pointer-up (lambda (event) (js/set! drag "current" #f)))
                (h/span (props #:class "title") "λ roost repl")
                (h/span (props #:class "spacer"))
                (h/select (props #:value module #:title "Module to evaluate in"
                                 #:on-change (lambda (event) (set-module! (event-value event))))
                          (map (lambda (name) (h/option (props #:key name #:value name) (module-label name)))
                               modules))
                (h/button (props #:title "Clear the history"
                                 #:on-click (lambda (event) (set-entries! '()) (set-selected! #f)))
                          "clear")
                (h/button (props #:title "Close (Ctrl+`)" #:on-click (lambda (event) (set-open! #f)))
                          "×"))
               (h/div
                (props #:class "log" #:ref log)
                (if (null? entries)
                    (h/div (props #:class "empty")
                           "Evaluate Scheme in the running page. Pick a module above; "
                           "a Hiccup result renders below with the page's own styles.")
                    (let loop ((rest entries) (i 0) (views '()))
                      (if (null? rest)
                          (reverse views)
                          (loop (cdr rest) (+ i 1)
                                (cons (component entry-view
                                                 (props #:key i #:entry (car rest)
                                                        #:selected? (eq? (car rest) selected)
                                                        #:on-pick (lambda (source) (set-draft! source) (set-cursor! #f))
                                                        #:on-select (lambda (entry) (set-preview-error! #f) (set-selected! entry))))
                                      views))))))
               (and selected
                    (h/div
                     (props #:class "preview")
                     (h/div (props #:class "label")
                            (h/span "preview · " (module-label (entry-module selected)))
                            (h/button (props #:title "Close the preview"
                                             #:on-click (lambda (event) (set-selected! #f)))
                                      "×"))
                     (h/div (props #:class "stage")
                            (h/slot (props #:name "preview"))
                            (and preview-error (h/pre (props #:class "error") preview-error)))))
               (component editor (props #:value draft #:on-change set-draft! #:on-run run!
                                        #:on-history browse! #:names names #:root root))
               (h/div (props #:class "hint")
                      "Ctrl/⌘+Enter run · Ctrl/⌘+↑↓ history · in " (module-label module))))
         (h/button (props #:class "toggle" #:title "Roost REPL (Ctrl+`)"
                          #:on-click (lambda (event) (set-open! not)))
                   "λ"))))))
