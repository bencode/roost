;; The products viewed most recently, most recent first.
(define-module (views recently-viewed)
  #:pure
  #:export (recently-viewed)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module (store products))

;; ids: product ids; on-view receives the product to open.
(define (recently-viewed attributes)
  (let-props attributes (ids on-view)
    (and (pair? ids)
         (h/section
          (props #:class "recent")
          (h/h2 "Recently viewed")
          (h/ul
           (map (lambda (id)
                  (let ((product (product-by-id id)))
                    (h/li (props #:key id)
                          (h/button (props #:type "button" #:on-click (lambda (event) (on-view product)))
                                    (product-name product)))))
                ids))))))
