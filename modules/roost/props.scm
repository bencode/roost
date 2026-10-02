(define-library (roost props)
  (export props props? props-entries props-ref)
  (import (scheme base)
          (scheme case-lambda)
          (only (guile) keyword?))
  (begin
    (define-record-type <props>
      (make-props entries)
      props?
      (entries props-entries))

    (define (keyword-values->entries args)
      (let loop ((rest args) (entries '()))
        (cond
         ((null? rest) (reverse entries))
         ((null? (cdr rest))
          (error "props: missing value for key" (car rest)))
         ((not (keyword? (car rest)))
          (error "props: key is not a keyword" (car rest)))
         ((assq (car rest) entries)
          (error "props: duplicate key" (car rest)))
         (else
          (loop (cddr rest) (cons (cons (car rest) (cadr rest)) entries))))))

    (define (props . keyword-values)
      (make-props (keyword-values->entries keyword-values)))

    (define props-ref
      (case-lambda
        ((attributes key)
         (let ((entry (assq key (props-entries attributes))))
           (if entry
               (cdr entry)
               (error "props-ref: missing key" key))))
        ((attributes key default)
         (let ((entry (assq key (props-entries attributes))))
           (if entry (cdr entry) default)))))))
