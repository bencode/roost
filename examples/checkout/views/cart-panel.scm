;; The cart: line items, shipping method, coupon, and the order totals.
(define-library (views cart-panel)
  (export cart-panel)
  (import (scheme base)
          (prefix (roost dom) h/)
          (only (roost props) props let-props)
          (only (roost hiccup) component)
          (only (roost hooks) use-state)
          (store products)
          (store cart)
          (store text)
          (views controls))
  (begin
    (define (cart-line attributes)
      (let-props attributes (product quantity on-change)
        (h/li
         (h/span (props #:class "line-name") (product-name product))
         (component stepper (props #:quantity quantity
                                   #:on-change (lambda (n) (on-change product n))))
         (h/span (props #:class "line-total") (money (* quantity (product-price product))))
         (h/button (props #:type "button" #:class "remove" #:aria-label "Remove"
                          #:on-click (lambda (event) (on-change product 0)))
                   "×"))))

    (define (coupon-box attributes)
      (let-props attributes (status on-apply)
        (let-values (((code set-code!) (use-state "")))
          (let ((checking? (eq? status 'checking)))
            (h/div
             (h/div
              (props #:class "coupon")
              (h/input (props #:placeholder "Coupon code (try SAVE10)" #:aria-label "Coupon code" #:value code
                              #:on-change (lambda (event) (set-code! (event-value event)))))
              (h/button (props #:type "button" #:disabled (or checking? (string=? "" (trim code)))
                               #:on-click (lambda (event) (on-apply (trim code))))
                        (if checking? "Checking…" "Apply")))
             (case status
               ((valid) (h/p (props #:class "ok") "SAVE10 applied: 10% off"))
               ((invalid) (h/p (props #:class "error") "That code is not valid"))
               (else #f)))))))

    (define (cart-panel attributes)
      (let-props attributes (cart on-change shipping on-shipping discount coupon-status on-coupon)
        (let ((totals (cart-totals cart shipping discount)))
          (h/aside
           (props #:class "cart")
           (h/h2 "Cart (" (cart-count cart) ")")
           (if (null? cart)
               (h/p (props #:class "empty") "Your cart is empty.")
               (h/ul
                (map (lambda (entry)
                       (component cart-line (props #:key (car entry) #:product (product-by-id (car entry))
                                                   #:quantity (cdr entry) #:on-change on-change)))
                     cart)))
           (h/fieldset
            (h/legend "Shipping")
            (map (lambda (method)
                   (h/label (props #:key (shipping-id method) #:class "radio")
                            (h/input (props #:type "radio" #:name "shipping" #:value (shipping-id method)
                                            #:checked (string=? shipping (shipping-id method))
                                            #:on-change (lambda (event) (on-shipping (shipping-id method)))))
                            (shipping-label method) " — " (money (shipping-cost method))))
                 shipping-methods))
           (component coupon-box (props #:status coupon-status #:on-apply on-coupon))
           (h/dl
            (h/dt "Subtotal") (h/dd (money (totals-subtotal totals)))
            (h/dt "Discount") (h/dd "−" (money (totals-discount totals)))
            (h/dt "Shipping") (h/dd (money (totals-shipping totals)))
            (h/dt "Tax (8%)") (h/dd (money (totals-tax totals)))
            (h/dt (props #:class "total") "Total") (h/dd (props #:class "total") (money (totals-total totals))))))))))
