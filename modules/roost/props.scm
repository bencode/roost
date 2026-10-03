(define-module (roost props)
  #:pure
  #:export (props props? props-entries props-ref let-props)
  #:use-module (scheme base)
  #:use-module (scheme case-lambda)
  #:use-module ((guile) #:select (keyword? symbol->keyword syntax-case syntax with-syntax
                                  identifier? datum->syntax syntax->datum)))

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
       (if entry (cdr entry) default)))))

;; (let-props attributes (name (name default) ...) body ...) binds each name to the
;; property of the same keyword, exactly as props-ref with or without a default.
(define-syntax let-props
  (lambda (stx)
    (define (keyword-of id)
      (datum->syntax id (symbol->keyword (syntax->datum id))))
    (syntax-case stx ()
      ((_ attributes (spec ...) body0 body ...)
       (with-syntax
           (((binding ...)
             (map (lambda (spec)
                    (syntax-case spec ()
                      ((name default)
                       (identifier? #'name)
                       (with-syntax ((key (keyword-of #'name)))
                         #'(name (props-ref source key default))))
                      (name
                       (identifier? #'name)
                       (with-syntax ((key (keyword-of #'name)))
                         #'(name (props-ref source key))))))
                  #'(spec ...))))
         #'(let ((source attributes))
             (let (binding ...) body0 body ...)))))))
