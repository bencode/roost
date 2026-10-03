;; Browsing the catalog: products similar to one, the recently viewed list, and the
;; neighbors of a product in the list the shopper is looking at.
(define-module (store browsing)
  #:pure
  #:export (similar-products remember-viewed neighbor)
  #:use-module (scheme base)
  #:use-module ((hoot lists) #:select (filter sort))
  #:use-module (store products))

(define (take items n)
  (if (or (= n 0) (null? items))
      '()
      (cons (car items) (take (cdr items) (- n 1)))))

;; Up to n other products of the same category, closest in price first.
(define (similar-products product n)
  (let* ((same (filter (lambda (p)
                         (and (string=? (product-category p) (product-category product))
                              (not (= (product-id p) (product-id product)))))
                       (vector->list products)))
         (distance (lambda (p) (abs (- (product-price p) (product-price product))))))
    (take (sort same (lambda (a b) (< (distance a) (distance b)))) n)))

;; Product ids, most recent first, each once, at most limit of them.
(define (remember-viewed viewed id limit)
  (take (cons id (filter (lambda (other) (not (= other id))) viewed)) limit))

;; The product before (step -1) or after (step 1) product in items, or #f at an end.
(define (neighbor items product step)
  (let loop ((rest items) (previous #f))
    (cond
     ((null? rest) #f)
     ((= (product-id (car rest)) (product-id product))
      (if (< step 0) previous (and (pair? (cdr rest)) (cadr rest))))
     (else (loop (cdr rest) (car rest))))))
