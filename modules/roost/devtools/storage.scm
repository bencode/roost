;; The panel's settings and history in localStorage, as one JSON object.
(define-module (roost devtools storage)
  #:pure
  #:export (load-settings setting save-settings!)
  #:use-module (scheme base)
  #:use-module ((roost js) #:prefix js/))

(define key "roost-devtools")

(define (storage) (js/ref js/global "localStorage"))
(define (json) (js/ref js/global "JSON"))

;; The stored object, or #f when there is none. Stored text that is not JSON is
;; reported and ignored: it only costs the panel its saved layout and history.
(define (load-settings)
  (let ((text (js/method (storage) "getItem" key)))
    (and text
         (guard (e ((js/error? e)
                    (js/method (js/ref js/global "console") "warn"
                               "roost devtools: ignoring unreadable settings" (js/error-value e))
                    #f))
           (js/method (json) "parse" text)))))

;; A stored field, or default when settings or the field is missing.
(define (setting settings name default)
  (if (and settings (not (string=? "undefined" (js/typeof settings name))))
      (js/ref settings name)
      default))

;; keys-and-values as for js/object; values are JavaScript values.
(define (save-settings! . keys-and-values)
  (js/method (storage) "setItem" key (js/method (json) "stringify" (apply js/object keys-and-values))))
