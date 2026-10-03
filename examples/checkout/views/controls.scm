;; Small controls shared by several views.
(define-module (views controls)
  #:pure
  #:export (event-value event-checked text-field stepper)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost js) #:prefix js/))

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
               "+"))))
