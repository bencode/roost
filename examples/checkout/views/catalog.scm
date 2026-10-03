;; The product catalog: search, category filter, sort order, and a grid of product cards.
;; The filters are local state; the cart comes from the page.
(define-module (views catalog)
  #:pure
  #:export (catalog)
  #:use-module (scheme base)
  #:use-module ((hoot lists) #:select (filter sort))
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost hooks) #:select (use-state))
  #:use-module (store products)
  #:use-module (store cart)
  #:use-module (store text)
  #:use-module (views controls))

(define (product-card attributes)
  (let-props attributes (product quantity on-change)
    (h/article
     (props #:class (if (> quantity 0) "product in-cart" "product"))
     (h/div (props #:class "thumb") (string (string-ref (product-category product) 0)))
     (h/h3 (product-name product))
     (h/p (props #:class "category") (product-category product))
     (h/p (props #:class "price") (money (product-price product)))
     (if (> quantity 0)
         (component stepper (props #:quantity quantity
                                   #:on-change (lambda (n) (on-change product n))))
         (h/button (props #:type "button" #:class "add"
                          #:on-click (lambda (event) (on-change product 1)))
                   "Add to cart")))))

(define (by-name a b) (string<? (product-name a) (product-name b)))
(define (by-price a b) (< (product-price a) (product-price b)))

(define (visible-products query category order)
  (sort (filter (lambda (p)
                  (and (or (string=? category "All") (string=? category (product-category p)))
                       (string-contains-ci (product-name p) query)))
                (vector->list products))
        (if (string=? order "price") by-price by-name)))

(define (catalog attributes)
  (let-props attributes (cart on-change)
    (let-values (((query set-query!) (use-state ""))
                 ((category set-category!) (use-state "All"))
                 ((order set-order!) (use-state "name")))
      (let ((shown (visible-products query category order)))
        (h/section
         (props #:class "catalog")
         (h/div
          (props #:class "toolbar")
          (h/input (props #:type "search" #:placeholder "Search products" #:aria-label "Search products"
                          #:value query
                          #:on-change (lambda (event) (set-query! (event-value event)))))
          (h/select (props #:aria-label "Category" #:value category
                           #:on-change (lambda (event) (set-category! (event-value event))))
                    (map (lambda (c) (h/option (props #:key c #:value c) c))
                         (cons "All" categories)))
          (h/select (props #:aria-label "Sort" #:value order
                           #:on-change (lambda (event) (set-order! (event-value event))))
                    (h/option (props #:value "name") "Sort by name")
                    (h/option (props #:value "price") "Sort by price"))
          (h/span (props #:class "count") (length shown) " products"))
         (if (null? shown)
             (h/p (props #:class "empty") "No products match your search.")
             (h/div
              (props #:class "grid")
              (map (lambda (p)
                     (component product-card
                                (props #:key (product-id p) #:product p
                                       #:quantity (cart-quantity cart (product-id p))
                                       #:on-change on-change)))
                   shown))))))))
