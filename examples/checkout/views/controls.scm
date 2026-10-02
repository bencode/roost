;; Small controls shared by several views.
(define-library (views controls)
  (export event-value event-checked text-field stepper)
  (import (scheme base)
          (prefix (roost dom) h/)
          (only (roost props) props let-props)
          (prefix (roost js) js/))
  (begin
    (define (event-value event) (js/ref event "target" "value"))
    (define (event-checked event) (js/ref event "target" "checked"))

    ;; A labelled input. The error message, when there is one, shows under it.
    (define (text-field attributes)
      (let-props attributes (label name value on-change on-blur error (type "text") (placeholder ""))
        (h/label
         (props #:class (if error "field invalid" "field"))
         (h/span label)
         (h/input (props #:name name #:type type #:value value #:placeholder placeholder
                         #:aria-invalid (if error "true" "false")
                         #:on-change (lambda (event) (on-change (event-value event)))
                         #:on-blur (lambda (event) (on-blur))))
         (and error (h/small error)))))

    ;; − quantity +
    (define (stepper attributes)
      (let-props attributes (quantity on-change)
        (h/div
         (props #:class "stepper")
         (h/button (props #:type "button" #:aria-label "Decrease"
                          #:on-click (lambda (event) (on-change (- quantity 1))))
                   "−")
         (h/span quantity)
         (h/button (props #:type "button" #:aria-label "Increase"
                          #:on-click (lambda (event) (on-change (+ quantity 1))))
                   "+"))))))
