;; An effect with a cleanup: a timer that stops when the component goes away.
;; Change the format and run again: the clock keeps ticking.
(define-module (playground)
  #:pure
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost react) #:select (render-root))
  #:use-module ((roost hooks) #:select (use-state use-effect))
  #:use-module ((roost js) #:prefix js/))

(define (now) (js/new (js/ref js/global "Date")))

(define (two-digits n)
  (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

(define (format-time date)
  (string-append (two-digits (js/method date "getHours")) ":"
                 (two-digits (js/method date "getMinutes")) ":"
                 (two-digits (js/method date "getSeconds"))))

(define (clock attributes)
  (let-values (((time set-time!) (use-state now)))
    (use-effect
     (lambda ()
       (let ((timer (js/method js/global "setInterval" (lambda () (set-time! (now))) 1000)))
         (lambda () (js/method js/global "clearInterval" timer))))
     '())
    (h/section
     (h/h2 "Clock")
     (h/p (props #:style (props #:font-size "48px" #:font-family "ui-monospace, monospace"))
          (format-time time)))))

(render-root (component clock (props)) "root")
