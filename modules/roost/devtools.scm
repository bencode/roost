;; The REPL panel of live development, mounted beside the application.
;;
;; <roost-devtools> holds the panel in a shadow root, so the panel's styles and the
;; page's styles stay apart. The preview of Hiccup results is a light DOM child placed
;; through a slot, so the page's styles do apply to it, as on the page itself.
(define-module (roost devtools)
  #:pure
  #:export (mount-devtools!)
  #:use-module (scheme base)
  #:use-module ((roost props) #:select (props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools panel) #:select (devtools))
  #:use-module ((roost devtools storage) #:select (load-settings))
  #:use-module ((roost devtools evaluate) #:select (exception-text))
  #:use-module ((roost devtools style) #:select (stylesheet)))

(define (document) (js/ref js/global "document"))
(define (element tag) (js/method (document) "createElement" tag))
(define (create-root . args) (apply js/method (js/module "react-dom/client") "createRoot" args))

;; The slot sits inside the panel, so text in the preview would inherit the panel's
;; monospace font; start it from the page's own text style instead.
(define (inherit-page-text! preview)
  (let ((computed (js/method js/global "getComputedStyle" (js/ref (document) "body")))
        (style (js/ref preview "style")))
    (for-each (lambda (property) (js/set! style property (js/ref computed property)))
              '("fontFamily" "fontSize" "lineHeight" "color"))))

;; Converting a node walks its whole tree at once, so a malformed node fails here
;; rather than while React renders; components fail later, in onUncaughtError.
(define (render-preview root node on-error)
  (guard (e (#t (js/method root "render" #f) (on-error (exception-text e))))
    (js/method root "render" (js/from-scheme node))))

;; modules: the names, as text, of the modules the panel can evaluate in.
(define (mount-devtools! modules)
  (let* ((host (element "roost-devtools"))
         (shadow (js/method host "attachShadow" (js/object "mode" "open")))
         (style (element "style"))
         (container (element "div"))
         (preview (element "div"))
         ;; The panel sets the reporter for the preview's render errors.
         (report-error (vector (lambda (message) #f)))
         (preview-root (create-root preview
                                    (js/object "onUncaughtError"
                                               (js/function (lambda (error info)
                                                              ((vector-ref report-error 0)
                                                               (js/ref error "message")))
                                                            2)))))
    (js/set! style "textContent" stylesheet)
    (js/method preview "setAttribute" "slot" "preview")
    (inherit-page-text! preview)
    (js/method shadow "append" style container)
    (js/method host "append" preview)
    (js/method (js/ref (document) "body") "append" host)
    (js/method (create-root container) "render"
               (js/from-scheme
                (component devtools
                           (props #:modules modules
                                  #:saved (load-settings)
                                  #:preview (lambda (node on-error)
                                              (vector-set! report-error 0 on-error)
                                              (render-preview preview-root node on-error))))))))
