;; The REPL panel, built on the DOM directly so it works in any page: a toggle button
;; and a floating terminal for a REPL session, with a preview area for values the
;; page can render.
(define-module (roost devtools panel)
  #:pure
  #:export (mount-panel!)
  #:use-module (scheme base)
  #:use-module (scheme lazy)
  #:use-module ((roost js) #:prefix js/)
  #:use-module (roost devtools session)
  #:use-module ((roost devtools editor) #:select (make-editor editor-set-text! editor-focus!))
  #:use-module ((roost devtools completion) #:select (visible-names))
  #:use-module (roost devtools storage))

(define history-limit 100)

(define (document) (js/ref js/global "document"))
(define (window-size name) (js/ref js/global name))

;; An element with a class and children (nodes or strings).
(define (element tag class . children)
  (let ((node (js/method (document) "createElement" tag)))
    (when class (js/set! node "className" class))
    (for-each (lambda (child) (js/method node "append" child)) children)
    node))

(define (button class title label on-click)
  (let ((node (element "button" class label)))
    (js/set! node "type" "button")
    (js/set! node "title" title)
    (js/method node "addEventListener" "click" (lambda (event) (on-click)))
    node))

(define (take items n)
  (if (or (= n 0) (null? items)) '() (cons (car items) (take (cdr items) (- n 1)))))

;; Output with a line where the REPL reports an error shows as one. Lazy: Hoot
;; evaluates module bodies at expansion time, where JavaScript is absent.
(define error-line
  (delay (js/new (js/ref js/global "RegExp")
                 "^(Scheme error:|While (reading input|executing meta-command):)" "m")))

(define (output-view text)
  (element "pre" (if (js/method (force error-line) "test" text) "output error" "output") text))

;; Keeps the panel inside the viewport.
(define (clamp x y)
  (cons (max 0 (min x (- (window-size "innerWidth") 80)))
        (max 0 (min y (- (window-size "innerHeight") 32)))))

;; shadow: the shadow root to build in; preview: a light DOM element of the host,
;; shown through the preview slot; render: renders a previewable value into preview
;; and reports render errors to its third argument, or #f; module-forms: a module
;; name's top-level forms, or #f, for completion.
(define (mount-panel! shadow preview session render module-forms)
  (let* ((saved (load-settings))
         (open? (setting saved "open" #f))
         (width (setting saved "width" 560))
         (height (setting saved "height" 420))
         (position (clamp (setting saved "x" (- (window-size "innerWidth") (+ width 16)))
                          (setting saved "y" (- (window-size "innerHeight") (+ height 64)))))
         (history (js/to-scheme (setting saved "history" (js/array))))
         (cursor #f)
         (drag #f)
         (prompt (element "span" "prompt" (session-prompt session)))
         (log (element "div" "log"))
         (preview-error (element "pre" "error"))
         (preview-area (element "div" "preview"))
         (input (element "div" "editor"))
         (panel (element "section" "panel"))
         (bar (element "div" "bar"))
         (editor #f))

    (define (save!)
      (save-settings! "open" open? "x" (car position) "y" (cdr position)
                      "width" width "height" height "history" (apply js/array history)))

    (define (place!)
      (let ((style (js/ref panel "style")))
        (js/set! style "left" (string-append (number->string (car position)) "px"))
        (js/set! style "top" (string-append (number->string (cdr position)) "px"))
        (js/set! style "width" (string-append (number->string width) "px"))
        (js/set! style "height" (string-append (number->string height) "px"))))

    (define (show! open)
      (set! open? open)
      (js/set! panel "hidden" (not open))
      (save!)
      (when (and open editor) (editor-focus! editor)))

    (define (show-preview! value)
      (js/set! preview-area "hidden" #f)
      (js/set! preview-error "textContent" "")
      (render value preview (lambda (message) (js/set! preview-error "textContent" message))))

    (define (run! text)
      (unless (string=? "" (js/method text "trim"))
        (let* ((result (session-run! session text))
               (output (vector-ref result 0))
               (previews (vector-ref result 1)))
          (js/method log "append"
                     (element "div" "input" (element "span" "prompt" (js/ref prompt "textContent")) text))
          (unless (string=? "" output) (js/method log "append" (output-view output)))
          (js/set! prompt "textContent" (session-prompt session))
          (js/set! log "scrollTop" (js/ref log "scrollHeight"))
          (when (and render (pair? previews)) (show-preview! (car previews)))
          (set! history (take (cons text (if (and (pair? history) (string=? text (car history)))
                                             (cdr history)
                                             history))
                              history-limit))
          (set! cursor #f)
          (save!)
          (editor-set-text! editor ""))))

    ;; -1 goes back in the history, 1 forward; past the newest entry, the input empties.
    (define (browse! step)
      (let* ((count (length history))
             (next (cond
                    ((= count 0) #f)
                    ((not cursor) (and (< step 0) 0))
                    (else (let ((i (- cursor step))) (and (>= i 0) (min i (- count 1))))))))
        (set! cursor next)
        (editor-set-text! editor (if next (list-ref history next) ""))))

    (define (names)
      (visible-names (module-forms (session-module session)) (session-defined-names session)))

    (define (clear!)
      (js/set! log "textContent" "")
      (js/set! preview-area "hidden" #t)
      (when render (render #f preview (lambda (message) #f))))

    ;; Dragging the title bar moves the panel; the pointer is captured by the bar.
    (js/method bar "addEventListener" "pointerdown"
               (lambda (event)
                 (unless (string=? "BUTTON" (js/ref event "target" "tagName"))
                   (js/method bar "setPointerCapture" (js/ref event "pointerId"))
                   (set! drag (cons (- (js/ref event "clientX") (car position))
                                    (- (js/ref event "clientY") (cdr position)))))))
    (js/method bar "addEventListener" "pointermove"
               (lambda (event)
                 (when drag
                   (set! position (clamp (- (js/ref event "clientX") (car drag))
                                         (- (js/ref event "clientY") (cdr drag))))
                   (place!))))
    (js/method bar "addEventListener" "pointerup" (lambda (event) (set! drag #f) (save!)))
    ;; The panel resizes with CSS; its size is read when the pointer is released.
    (js/method panel "addEventListener" "pointerup"
               (lambda (event)
                 (set! width (js/ref panel "offsetWidth"))
                 (set! height (js/ref panel "offsetHeight"))
                 (save!)))
    ;; Ctrl+` shows or hides the panel anywhere on the page.
    (js/method (document) "addEventListener" "keydown"
               (lambda (event)
                 (when (and (js/ref event "ctrlKey") (string=? "`" (js/ref event "key")))
                   (js/method event "preventDefault")
                   (show! (not open?)))))

    (js/method bar "append"
               (element "span" "title" "λ")
               prompt
               (element "span" "spacer")
               (button #f "Clear the output" "clear" clear!)
               (button #f "Close (Ctrl+`)" "×" (lambda () (show! #f))))
    (js/method preview-area "append"
               (element "div" "label" "preview"
                        (button #f "Close the preview" "×"
                                (lambda () (js/set! preview-area "hidden" #t))))
               (let ((slot (element "slot" "stage")))
                 (js/set! slot "name" "preview")
                 slot)
               preview-error)
    (js/set! preview-area "hidden" #t)
    (js/method log "append"
               (element "div" "intro"
                        "A REPL in the running page. ,m (module) switches modules, ,help lists "
                        "commands. Mod-Enter runs; Mod-↑/↓ walks the history."))
    (js/method panel "append" bar log preview-area input)
    (js/method shadow "append"
               (element "div" "theme"
                        panel
                        (button "toggle" "Roost REPL (Ctrl+`)" "λ" (lambda () (show! (not open?))))))
    (set! editor (make-editor input shadow
                              (list (cons "Mod-Enter" run!)
                                    (cons "Mod-ArrowUp" (lambda (text) (browse! -1)))
                                    (cons "Mod-ArrowDown" (lambda (text) (browse! 1))))
                              names "(+ 1 2)   ,m (store cart)   Mod-Enter to run" #t))
    (place!)
    (js/set! panel "hidden" (not open?))))
