;; Quick view: a drawer with a product's details, its similar products, and keyboard
;; browsing through the products the catalog shows.
(define-module (views quick-view)
  #:pure
  #:export (quick-view similar-list)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost hooks) #:select (use-effect))
  #:use-module ((roost js) #:prefix js/)
  #:use-module (store products)
  #:use-module ((store text) #:select (money))
  #:use-module ((store browsing) #:select (similar-products))
  #:use-module ((views controls) #:select (stepper)))

;; How another price compares with the one shown: "+$12.50", "−$3.00", or "same price".
(define (price-difference from to)
  (let ((difference (- to from)))
    (cond
     ((= difference 0) "same price")
     ((> difference 0) (string-append "+" (money difference)))
     (else (string-append "−" (money (- difference)))))))

(define (similar-list attributes)
  (let-props attributes (product on-pick)
    (h/section
     (props #:class "similar")
     (h/h3 "Similar in " (product-category product))
     (h/ul
      (map (lambda (similar)
             (h/li (props #:key (product-id similar))
                   (h/button (props #:type "button" #:on-click (lambda (event) (on-pick similar)))
                             (h/span (props #:class "name") (product-name similar))
                             (h/span (props #:class "price-tag")
                                     (money (product-price similar)) " · "
                                     (price-difference (product-price product) (product-price similar))))))
           (similar-products product 4))))))

;; on-step receives -1 or 1 to show the previous or next product.
(define (quick-view attributes)
  (let-props attributes (product quantity on-change on-close on-pick on-step)
    (use-effect (lambda ()
                  (let ((document (js/ref js/global "document"))
                        (on-key (lambda (event)
                                  (let ((key (js/ref event "key")))
                                    (cond
                                     ((string=? key "Escape") (on-close))
                                     ((string=? key "ArrowLeft") (on-step -1))
                                     ((string=? key "ArrowRight") (on-step 1)))))))
                    (js/method document "addEventListener" "keydown" on-key)
                    (lambda () (js/method document "removeEventListener" "keydown" on-key))))
                (list on-close on-step))
    (h/div
     (h/div (props #:class "backdrop" #:on-click (lambda (event) (on-close))))
     (h/aside
      (props #:class "quick-view" #:role "dialog" #:aria-label (product-name product))
      (h/header
       (h/div (props #:class "nav")
              (h/button (props #:type "button" #:aria-label "Previous" #:on-click (lambda (event) (on-step -1))) "←")
              (h/button (props #:type "button" #:aria-label "Next" #:on-click (lambda (event) (on-step 1))) "→"))
       (h/button (props #:type "button" #:aria-label "Close" #:on-click (lambda (event) (on-close))) "×"))
      (h/div
       (props #:class "body")
       (h/div (props #:class "hero")
              (h/span (string (string-ref (product-category product) 0)))
              (h/small (props #:class "hero-label") (product-category product)))
       (h/h2 (product-name product))
       (h/p (props #:class "meta") (product-category product) " · #" (product-id product))
       (h/p (props #:class "price") (money (product-price product)))
       (if (> quantity 0)
           (component stepper (props #:quantity quantity #:on-change (lambda (n) (on-change product n))))
           (h/button (props #:type "button" #:class "primary"
                            #:on-click (lambda (event) (on-change product 1)))
                     "Add to cart"))
       (component similar-list (props #:product product #:on-pick on-pick))
       (h/p (props #:class "keys") "← → browse · Esc close"))))))
