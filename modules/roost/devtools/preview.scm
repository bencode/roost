;; Previews: values a REPL renders rather than prints.
(define-module (roost devtools preview)
  #:pure
  #:export (hiccup-node? exception-text render-isolated render-into!)
  #:use-module (scheme base)
  #:use-module ((hoot error-handling) #:select (format-exception))
  #:use-module ((roost js) #:prefix js/))

;; Hiccup nodes are vectors whose first element is a tag or a component.
(define (hiccup-node? value)
  (and (vector? value)
       (> (vector-length value) 0)
       (let ((type (vector-ref value 0)))
         (or (string? type) (procedure? type) (js/value? type)))))

(define (exception-text e)
  (let ((port (open-output-string)))
    (format-exception e port)
    (get-output-string port)))

;; Renders value into element, in a React root of its own, so a failing preview leaves
;; the rest of the page alone; report receives error messages. Returns the root, for
;; the caller to render into again or unmount. Converting a node walks its whole tree
;; at once, so a malformed node fails at once; components fail while React renders.
(define (render-isolated value element report)
  (let ((root (js/method (js/module "react-dom/client") "createRoot" element
                         (js/object "onUncaughtError"
                                    (js/function (lambda (error info) (report (js/ref error "message")))
                                                 2)))))
    (render-into! root value report)
    root))

(define (render-into! root value report)
  (guard (e (#t (js/method root "render" #f) (report (exception-text e))))
    (js/method root "render" (js/from-scheme value))))
