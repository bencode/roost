;; The cart as an association list of (product-id . quantity), in the order items were added.
(define-module (store cart)
  #:pure
  #:export (cart-quantity cart-set cart-count cart-totals totals-subtotal totals-discount
            totals-shipping totals-tax totals-total)
  #:use-module (scheme base)
  #:use-module ((hoot lists) #:select (filter fold))
  #:use-module (store products))

(define (cart-quantity cart id)
  (let ((entry (assv id cart))) (if entry (cdr entry) 0)))

;; A quantity of zero removes the product.
(define (cart-set cart id quantity)
  (cond
   ((<= quantity 0) (filter (lambda (entry) (not (= (car entry) id))) cart))
   ((assv id cart) (map (lambda (entry) (if (= (car entry) id) (cons id quantity) entry)) cart))
   (else (append cart (list (cons id quantity))))))

(define (cart-subtotal cart)
  (fold (lambda (entry total) (+ total (* (cdr entry) (product-price (product-by-id (car entry))))))
        0 cart))

(define-record-type <totals>
  (make-totals subtotal discount shipping tax total)
  totals?
  (subtotal totals-subtotal)
  (discount totals-discount)
  (shipping totals-shipping)
  (tax totals-tax)
  (total totals-total))

;; Amounts in cents. The discount is a percentage of the subtotal; tax is 8% of the
;; discounted subtotal; an empty cart ships for free.
(define (cart-totals cart shipping discount-percent)
  (let* ((subtotal (cart-subtotal cart))
         (discount (quotient (* subtotal discount-percent) 100))
         (shipping-amount (if (null? cart) 0 (shipping-cost (shipping-method shipping))))
         (tax (quotient (* (- subtotal discount) 8) 100)))
    (make-totals subtotal discount shipping-amount tax (+ (- subtotal discount) shipping-amount tax))))

(define (cart-count cart)
  (fold (lambda (entry n) (+ n (cdr entry))) 0 cart))
