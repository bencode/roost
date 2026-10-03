;; The REPL panel of live development, mounted beside the application. It uses no
;; framework: any page can have it.
;;
;; <roost-devtools> holds the panel in a shadow root, so the panel's styles and the
;; page's styles stay apart. The preview of rendered values is a light DOM child placed
;; through a slot, so the page's styles do apply to it, as on the page itself.
(define-module (roost devtools)
  #:pure
  #:export (mount-devtools!)
  #:use-module (scheme base)
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools session) #:select (make-session))
  #:use-module ((roost devtools panel) #:select (mount-panel!))
  #:use-module ((roost devtools commands) #:select (repl-commands))
  #:use-module ((roost devtools remote) #:select (connect-terminals!))
  #:use-module ((roost devtools sources) #:select (source-forms-of))
  #:use-module ((roost devtools style) #:select (stylesheet)))

(define (document) (js/ref js/global "document"))
(define (element tag) (js/method (document) "createElement" tag))

;; The slot sits inside the panel, so text in the preview would inherit the panel's
;; monospace font; start it from the page's own text style instead.
(define (inherit-page-text! preview)
  (let ((computed (js/method js/global "getComputedStyle" (js/ref (document) "body")))
        (style (js/ref preview "style")))
    (for-each (lambda (property) (js/set! style property (js/ref computed property)))
              '("fontFamily" "fontSize" "lineHeight" "color"))))

;; module: the module the REPL starts in. sources: returns the application modules'
;; sources (<module-source>). loader: loads a module while evaluating.
;; previewable?: values to render rather than print; render: (render value element
;; report-error) renders one into element, or #f. terminal-url: the WebSocket the
;; development server relays terminal REPLs through.
(define (mount-devtools! module sources loader previewable? render terminal-url)
  (let* ((host (element "roost-devtools"))
         (shadow (js/method host "attachShadow" (js/object "mode" "open")))
         (style (element "style"))
         (preview (element "div")))
    (js/set! style "textContent" stylesheet)
    (js/method preview "setAttribute" "slot" "preview")
    (inherit-page-text! preview)
    (js/method shadow "append" style)
    (js/method host "append" preview)
    (js/method (js/ref (document) "body") "append" host)
    (let ((commands (repl-commands sources)))
      (mount-panel! shadow preview (make-session module previewable? commands loader) render
                    (lambda (name) (source-forms-of (sources) name)))
      (connect-terminals! terminal-url
                          (lambda () (make-session module (lambda (value) #f) commands loader))))))
