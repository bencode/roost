;; Catalog data: 200 generated products, plus the reference lists the page offers.
(define-module (store products)
  #:pure
  #:export (make-product product? product-id product-name product-category product-price
            products product-by-id categories countries shipping-methods shipping-method
            shipping-id shipping-label shipping-cost)
  #:use-module (scheme base))

(define-record-type <product>
  (make-product id name category price)
  product?
  (id product-id)
  (name product-name)
  (category product-category)
  (price product-price))           ; in cents

(define categories
  '("Audio" "Cameras" "Computers" "Gaming" "Home" "Kitchen" "Outdoor" "Phones" "Sports" "Wearables"))

(define adjectives
  '("Compact" "Wireless" "Smart" "Classic" "Ultra" "Portable" "Premium" "Eco" "Pro" "Mini" "Rugged" "Slim"))

(define nouns
  '("Speaker" "Camera" "Laptop" "Controller" "Lamp" "Blender" "Tent" "Phone" "Racket" "Watch" "Headset" "Router"))

(define products
  (let loop ((i 0) (acc '()))
    (if (= i 200)
        (list->vector (reverse acc))
        (loop (+ i 1)
              (cons (make-product i
                                  (string-append (list-ref adjectives (modulo (* i 7) 12)) " "
                                                 (list-ref nouns (modulo (* i 5) 12)) " "
                                                 (number->string (+ 100 i)))
                                  (list-ref categories (modulo i 10))
                                  (+ 999 (* 125 (modulo (* i 37) 200))))
                    acc)))))

(define (product-by-id id) (vector-ref products id))

(define countries
  '("Australia" "Austria" "Belgium" "Brazil" "Canada" "China" "Denmark" "Finland" "France"
    "Germany" "India" "Ireland" "Italy" "Japan" "Mexico" "Netherlands" "New Zealand" "Norway"
    "Poland" "Portugal" "Singapore" "South Korea" "Spain" "Sweden" "Switzerland"
    "United Kingdom" "United States"))

;; (id label cost-in-cents)
(define shipping-methods
  '(("standard" "Standard (5–7 days)" 599)
    ("express" "Express (1–2 days)" 1999)
    ("pickup" "Store pickup" 0)))

(define (shipping-method id) (assoc id shipping-methods))
(define (shipping-id method) (car method))
(define (shipping-label method) (cadr method))
(define (shipping-cost method) (car (cddr method)))
