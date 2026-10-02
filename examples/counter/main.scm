(import (scheme base)
        (prefix (roost dom) h/)
        (only (roost props) props let-props)
        (only (roost hiccup) component)
        (only (roost react) render-root)
        (only (roost hooks) use-state use-effect)
        (prefix (roost js) js/))

(define (counter attributes)
  (let-props attributes ((start 0))
    (let-values (((count set-count!) (use-state start)))
      (use-effect
       (lambda ()
         (js/set! (js/ref js/global "document") "title" (string-append "Count: " (number->string count))))
       (list count))
      (h/section
       (props #:class "counter")
       (h/h2 "Counter")
       (h/output count)
       (h/div
        (h/button (props #:on-click (lambda (event) (set-count! (lambda (n) (- n 1))))) "-1")
        (h/button (props #:on-click (lambda (event) (set-count! (lambda (n) (+ n 1))))) "+1"))))))

(render-root (component counter (props #:start 0)) "root")
