(define-library (roost hooks)
  (export use-state use-effect use-ref)
  (import (scheme base)
          (scheme case-lambda)
          (scheme lazy)
          (prefix (roost js) js/))
  (begin
    ;; Thin layers over the React functions of the same name; React's semantics apply.
    ;; Lazy: Hoot evaluates library bodies at expansion time, where JavaScript is absent.
    (define react (delay (js/module "react")))

    ;; The React function of that name, looked up once on first use.
    (define (react-hook name)
      (let ((hook (delay (js/ref (force react) name))))
        (lambda args (apply (force hook) args))))

    (define react-use-state (react-hook "useState"))
    (define react-use-effect (react-hook "useEffect"))
    (define react-use-ref (react-hook "useRef"))

    ;; A procedure as init is a lazy initializer, and the setter treats a procedure as
    ;; an updater, exactly as in React.
    (define (use-state init)
      (let ((state (react-use-state init)))
        (values (js/ref state 0) (js/ref state 1))))

    ;; Only a returned procedure is a cleanup; React requires undefined otherwise, and
    ;; every Scheme procedure returns some value.
    (define (effect thunk)
      (lambda ()
        (call-with-values thunk
          (lambda results
            (if (and (pair? results) (null? (cdr results)) (procedure? (car results)))
                (car results)
                (if #f #f))))))

    (define use-effect
      (case-lambda
        ((thunk) (react-use-effect (effect thunk)))
        ((thunk deps) (react-use-effect (effect thunk) (apply js/array deps)))))

    ;; The ref object itself: read and write its current with js/ref and js/set!, or
    ;; pass it as #:ref to a DOM node.
    (define (use-ref initial)
      (react-use-ref initial))))
