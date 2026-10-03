;; A store checkout page: a catalog of 200 products, a cart with live totals and an
;; asynchronous coupon check, and a validated checkout form with asynchronous submission.
;;
;; The application's own libraries sit next to this file:
;;   store/  data and pure logic (products, cart, form validation, text helpers)
;;   views/  React components, one library per part of the page
;; This file holds the state the parts share and the (simulated) server calls.
(import (scheme base)
        (scheme char)
        (prefix (roost dom) h/)
        (only (roost props) props let-props)
        (only (roost hiccup) component)
        (only (roost react) render-root)
        (only (roost hooks) use-state)
        (prefix (roost js) js/)
        (store products)
        (store cart)
        (store text)
        (store order-form)
        (only (store browsing) remember-viewed)
        (views catalog)
        (views recently-viewed)
        (views cart-panel)
        (views checkout-form))

;; Stand-ins for server requests: answer after a delay.
(define (after milliseconds thunk)
  (js/method js/global "setTimeout" thunk milliseconds))

(define (check-coupon code reply)
  (after 400 (lambda () (reply (string-ci=? code "SAVE10")))))

(define (place-order form total reply)
  (after 800 (lambda ()
               (if (string-ci=? (trim (form-ref form 'email)) "taken@example.com")
                   (reply #f "This email belongs to an existing account. Sign in to continue.")
                   (reply (+ 100000 (remainder total 900000)) #f)))))

(define (confirmation attributes)
  (let-props attributes (number email on-continue)
    (h/main
     (props #:class "done")
     (h/h1 "Thank you!")
     (h/p "Order " (h/strong "#" number) " is confirmed. A receipt is on its way to " email ".")
     (h/button (props #:type "button" #:on-click (lambda (event) (on-continue))) "Continue shopping"))))

(define (app attributes)
  (let-values (((cart set-cart!) (use-state '()))
               ((shipping set-shipping!) (use-state "standard"))
               ((coupon-status set-coupon-status!) (use-state 'none))
               ((submitting? set-submitting!) (use-state #f))
               ((failure set-failure!) (use-state #f))
               ((receipt set-receipt!) (use-state #f))
               ((viewing set-viewing!) (use-state #f))
               ((recent set-recent!) (use-state '())))
    (define discount (if (eq? coupon-status 'valid) 10 0))

    (define (change-quantity! product quantity)
      (set-cart! (lambda (cart) (cart-set cart (product-id product) quantity))))

    (define (apply-coupon! code)
      (set-coupon-status! 'checking)
      (check-coupon code (lambda (valid?) (set-coupon-status! (if valid? 'valid 'invalid)))))

    (define (submit! form)
      (set-submitting! #t)
      (set-failure! #f)
      (place-order form (totals-total (cart-totals cart shipping discount))
                   (lambda (number message)
                     (set-submitting! #f)
                     (if number
                         (set-receipt! (cons number (trim (form-ref form 'email))))
                         (set-failure! message)))))

    ;; Opens the quick view on a product, or closes it with #f.
    (define (view! product)
      (set-viewing! (and product (product-id product)))
      (when product
        (set-recent! (lambda (recent) (remember-viewed recent (product-id product) 5)))))

    (define (start-over!)
      (set-receipt! #f)
      (set-cart! '())
      (set-coupon-status! 'none))

    (if receipt
        (component confirmation (props #:number (car receipt) #:email (cdr receipt)
                                       #:on-continue start-over!))
        (h/main
         (h/header
          (h/h1 "Roost Store")
          (h/span (props #:class "badge") (cart-count cart) " in cart"))
         (and failure (h/p (props #:class "banner" #:role "alert") failure))
         (h/div
          (props #:class "layout")
          (component catalog (props #:cart cart #:on-change change-quantity!
                                    #:viewing viewing #:on-view view!))
          (h/div
           (props #:class "side")
           (component cart-panel (props #:cart cart #:on-change change-quantity!
                                        #:shipping shipping #:on-shipping set-shipping!
                                        #:discount discount
                                        #:coupon-status coupon-status #:on-coupon apply-coupon!))
           (component checkout-form (props #:can-order? (pair? cart) #:submitting? submitting?
                                           #:on-submit submit!))))
         (component recently-viewed (props #:ids recent #:on-view view!))))))

(render-root (component app (props)) "root")
