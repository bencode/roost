;; A handle that resizes two panes by dragging. It reports the ratio of the pointer's
;; position within the handle's parent, between 0.15 and 0.85.
(define-module (views split)
  #:pure
  #:export (split-handle)
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props let-props))
  #:use-module ((roost hooks) #:select (use-ref))
  #:use-module ((roost js) #:prefix js/))

;; direction: columns (a vertical handle) or rows (a horizontal one). on-ratio receives
;; the new ratio while dragging; on-done when the pointer is released.
(define (split-handle attributes)
  (let-props attributes (direction on-ratio on-done)
    (let ((dragging (use-ref #f)))
      (define (ratio event)
        (let* ((parent (js/ref event "currentTarget" "parentElement"))
               (box (js/method parent "getBoundingClientRect"))
               (columns? (eq? direction 'columns))
               (offset (if columns?
                           (- (js/ref event "clientX") (js/ref box "left"))
                           (- (js/ref event "clientY") (js/ref box "top"))))
               (size (js/ref box (if columns? "width" "height"))))
          (max 0.15 (min 0.85 (inexact (/ offset size))))))
      (h/div (props #:class (string-append "split " (symbol->string direction))
                    #:on-pointer-down (lambda (event)
                                        (js/method (js/ref event "currentTarget") "setPointerCapture"
                                                   (js/ref event "pointerId"))
                                        (js/set! dragging "current" #t))
                    #:on-pointer-move (lambda (event)
                                        (when (js/ref dragging "current")
                                          (on-ratio (ratio event))))
                    #:on-pointer-up (lambda (event)
                                      (js/set! dragging "current" #f)
                                      (on-done)))))))
