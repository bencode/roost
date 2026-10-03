(define-module (roost hiccup)
  #:pure
  #:export (make-node component)
  #:use-module (scheme base)
  #:use-module (roost props))

;; Node = #(type [props] child ...). Props may only appear first in contents;
;; children are kept as given so list boundaries survive.
(define (check-contents contents)
  (let ((rest (if (and (pair? contents) (props? (car contents)))
                  (cdr contents)
                  contents)))
    (for-each (lambda (child)
                (when (props? child)
                  (error "make-node: props must be the first content" child)))
              rest)))

(define (make-node type . contents)
  (when (and (string? type) (= 0 (string-length type)))
    (error "make-node: empty tag name"))
  (check-contents contents)
  (apply vector type contents))

;; The render value is stored, never called. Whether it is a Scheme procedure or a
;; JavaScript component is checked by the React adapter, keeping this layer FFI-free.
(define (component render . contents)
  (when (string? render)
    (error "component: use a DOM constructor for tag" render))
  (apply make-node render contents))
