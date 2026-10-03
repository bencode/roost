;; Evaluation for the REPL panel: forms are read from text and evaluated in a module
;; of the running program, collecting what they print and what they return.
(define-module (roost devtools evaluate)
  #:pure
  #:export (evaluate result-output result-value result-node result-error hiccup-node? exception-text)
  #:use-module (scheme base)
  #:use-module (scheme write)
  #:use-module ((hoot modules) #:select (the-root-module resolve-module))
  #:use-module ((hoot eval) #:select (eval))
  #:use-module ((hoot read) #:select (read))
  #:use-module ((hoot error-handling) #:select (format-exception))
  #:use-module ((roost js) #:prefix js/))

;; One evaluation: printed output, and either the written values, a Hiccup node to
;; render, or the text of an error. Fields that do not apply are #f.
(define-record-type <result>
  (make-result output value node error)
  result?
  (output result-output)
  (value result-value)
  (node result-node)
  (error result-error))

;; Hiccup nodes are vectors whose first element is a tag or a component.
(define (hiccup-node? v)
  (and (vector? v)
       (> (vector-length v) 0)
       (let ((type (vector-ref v 0)))
         (or (string? type) (procedure? type) (js/value? type)))))

(define (read-all port)
  (let loop ((forms '()))
    (let ((form (read port)))
      (if (eof-object? form)
          (reverse forms)
          (loop (cons form forms))))))

;; Unspecified values, such as a definition's, are left out.
(define unspecified (if #f #f))

(define (written values)
  (let ((port (open-output-string)))
    (let loop ((rest (let keep ((rest values))
                       (cond
                        ((null? rest) '())
                        ((eq? (car rest) unspecified) (keep (cdr rest)))
                        (else (cons (car rest) (keep (cdr rest)))))))
               (first? #t))
      (unless (null? rest)
        (unless first? (newline port))
        (write (car rest) port)
        (loop (cdr rest) #f)))
    (get-output-string port)))

(define (exception-text e)
  (let ((port (open-output-string)))
    (format-exception e port)
    (get-output-string port)))

;; module-name is the module's name as text, such as "(store cart)". The values are
;; those of the last form.
(define (evaluate source module-name)
  (let ((output (open-output-string)))
    (guard (e (#t (make-result (get-output-string output) #f #f (exception-text e))))
      (let* ((module (or (resolve-module (the-root-module) (read (open-input-string module-name)))
                         (error "module is not loaded" module-name)))
             (values (parameterize ((current-output-port output))
                       (let loop ((forms (read-all (open-input-string source))) (last '()))
                         (if (null? forms)
                             last
                             (loop (cdr forms)
                                   (call-with-values (lambda () (eval (car forms) module)) list)))))))
        (if (and (= 1 (length values)) (hiccup-node? (car values)))
            (make-result (get-output-string output) #f (car values) #f)
            (make-result (get-output-string output) (written values) #f #f))))))
