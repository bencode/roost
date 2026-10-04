;; A component with state. Change the step, run again (Mod-Enter): the count stays.
(define-module (playground)
  #:pure
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost react) #:select (render-root))
  #:use-module ((roost hooks) #:select (use-state)))

(define step 1)

(define (counter attributes)
  (let-props attributes ((start 0))
    (let-values (((count set-count!) (use-state start)))
      (h/section
       (h/h2 "Counter")
       (h/output count)
       (h/button (props #:on-click (lambda (event) (set-count! (lambda (n) (- n step)))))
                 "-" step)
       (h/button (props #:on-click (lambda (event) (set-count! (lambda (n) (+ n step)))))
                 "+" step)))))

(render-root (component counter (props #:start 0)) "root")
