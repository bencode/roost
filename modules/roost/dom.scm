(define-library (roost dom)
  (export div section h2 p ul li aside button output)
  (import (scheme base)
          (roost hiccup))
  (begin
    (define-syntax define-dom-tags
      (syntax-rules ()
        ((_ (name tag) ...)
         (begin
           (define (name . contents)
             (apply make-node tag contents))
           ...))))

    (define-dom-tags
      (div "div")
      (section "section")
      (h2 "h2")
      (p "p")
      (ul "ul")
      (li "li")
      (aside "aside")
      (button "button")
      (output "output"))))
