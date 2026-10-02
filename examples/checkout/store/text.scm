;; Text helpers the page needs. R7RS small has no substring search or trimming.
(define-library (store text)
  (export money string-contains-ci digits-only group-card-number trim)
  (import (scheme base)
          (scheme char)
          (only (hoot lists) filter)
          (prefix (roost js) js/))
  (begin
    (define (money cents)
      (let ((dollars (quotient cents 100)) (rest (remainder cents 100)))
        (string-append "$" (number->string dollars) "." (if (< rest 10) "0" "") (number->string rest))))

    (define (string-contains-ci text part)
      (let ((n (string-length text)) (m (string-length part)))
        (define (match-at? i)
          (let loop ((j 0))
            (or (= j m)
                (and (char-ci=? (string-ref text (+ i j)) (string-ref part j))
                     (loop (+ j 1))))))
        (let loop ((i 0))
          (and (<= (+ i m) n)
               (or (match-at? i) (loop (+ i 1)))))))

    (define (digits-only s)
      (list->string (filter char-numeric? (string->list s))))

    ;; "1234567890" -> "1234 5678 90"
    (define (group-card-number digits)
      (let loop ((chars (string->list digits)) (i 0) (acc '()))
        (cond
         ((null? chars) (list->string (reverse acc)))
         ((and (> i 0) (= 0 (modulo i 4))) (loop (cdr chars) (+ i 1) (cons (car chars) (cons #\space acc))))
         (else (loop (cdr chars) (+ i 1) (cons (car chars) acc))))))

    (define (trim s) (js/method s "trim"))))
