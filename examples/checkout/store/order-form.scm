;; The checkout form's data: values as an association list of (field . string), and
;; validation as a list of (field . message).
(define-module (store order-form)
  #:pure
  #:export (initial-form form-ref form-set validate)
  #:use-module (scheme base)
  #:use-module (store text))

(define initial-form
  '((email . "") (phone . "") (name . "") (street . "") (city . "") (postal . "")
    (country . "United States")
    (billing-name . "") (billing-street . "") (billing-city . "") (billing-postal . "")
    (card . "") (expiry . "") (cvc . "")))

(define (form-ref form key) (cdr (assq key form)))

(define (form-set form key value)
  (map (lambda (entry) (if (eq? (car entry) key) (cons key value) entry)) form))

(define (error-if invalid? key message)
  (if invalid? (list (cons key message)) '()))

(define (blank? form key) (string=? "" (trim (form-ref form key))))

(define (required form key label)
  (error-if (blank? form key) key (string-append label " is required")))

(define (validate-email form)
  (let ((email (trim (form-ref form 'email))))
    (cond
     ((string=? email "") (error-if #t 'email "Email is required"))
     (else (error-if (not (and (string-contains-ci email "@") (string-contains-ci email ".")))
                     'email "Enter a valid email")))))

;; Postal codes differ by country; only their length is checked.
(define (validate-postal form key)
  (error-if (not (<= 3 (string-length (trim (form-ref form key))) 10)) key "Enter a valid postal code"))

(define (validate-expiry form)
  (let ((expiry (digits-only (form-ref form 'expiry))))
    (error-if (not (and (= 4 (string-length expiry))
                        (<= 1 (string->number (substring expiry 0 2)) 12)))
              'expiry "Use MM/YY")))

(define (validate form billing-same?)
  (append
   (validate-email form)
   (required form 'name "Full name")
   (required form 'street "Street")
   (required form 'city "City")
   (validate-postal form 'postal)
   (if billing-same?
       '()
       (append (required form 'billing-name "Billing name")
               (required form 'billing-street "Billing street")
               (required form 'billing-city "Billing city")
               (validate-postal form 'billing-postal)))
   (error-if (not (= 16 (string-length (digits-only (form-ref form 'card))))) 'card "Card number must have 16 digits")
   (validate-expiry form)
   (error-if (not (<= 3 (string-length (digits-only (form-ref form 'cvc))) 4)) 'cvc "CVC has 3 or 4 digits")))
