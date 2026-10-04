;; Where the playground's code comes from and goes: the draft kept in the browser, links
;; that carry code in their hash, the starter examples, and the layout.
(define-module (lab draft)
  #:pure
  #:export (load-draft save-draft! shared-text clear-shared! share-url fetch-starter
            load-layout save-layout!)
  #:use-module (scheme base)
  #:use-module ((roost js) #:prefix js/))

(define draft-key "roost-playground:draft")
(define layout-key "roost-playground:layout")
(define hash-prefix "#code=")

(define (storage) (js/ref js/global "localStorage"))
(define (location) (js/ref js/global "location"))
(define (lz) (js/module "lz-string"))

;; localStorage throws when the browser blocks it; the playground then works without it.
(define (stored key)
  (guard (e ((js/error? e)
             (js/method (js/ref js/global "console") "error" "playground: cannot read storage" (js/error-value e))
             #f))
    (js/method (storage) "getItem" key)))

(define (store! key value)
  (guard (e ((js/error? e)
             (js/method (js/ref js/global "console") "error" "playground: cannot write storage" (js/error-value e))))
    (js/method (storage) "setItem" key value)))

(define (load-draft) (stored draft-key))
(define (save-draft! text) (store! draft-key text))

;; The code a shared link carries, or #f.
(define (shared-text)
  (let ((hash (js/ref (location) "hash")))
    (and (string-prefix? hash-prefix hash)
         (js/method (lz) "decompressFromEncodedURIComponent"
                    (substring hash (string-length hash-prefix) (string-length hash))))))

;; Drops the code from the address, so a reload starts from the draft.
(define (clear-shared!)
  (js/method (js/ref js/global "history") "replaceState" #f ""
             (string-append (js/ref (location) "pathname") (js/ref (location) "search"))))

(define (share-url text)
  (string-append (js/ref (location) "origin") (js/ref (location) "pathname")
                 hash-prefix (js/method (lz) "compressToEncodedURIComponent" text)))

(define (string-prefix? prefix text)
  (and (>= (string-length text) (string-length prefix))
       (string=? prefix (substring text 0 (string-length prefix)))))

;; Fetches starters/<name>.scm and hands its text to k.
(define (fetch-starter name k)
  (let ((response (js/method js/global "fetch" (string-append "starters/" name ".scm"))))
    (js/method (js/method response "then" (lambda (response) (js/method response "text")))
               "then" k)))

;; The split ratios: (columns . rows), each between 0 and 1.
(define default-layout (cons 0.5 0.62))

(define (load-layout)
  (let* ((saved (stored layout-key))
         (comma (and saved (string-index saved #\,)))
         (columns (and comma (string->number (substring saved 0 comma))))
         (rows (and comma (string->number (substring saved (+ comma 1) (string-length saved))))))
    (if (and columns rows) (cons columns rows) default-layout)))

(define (string-index text char)
  (let loop ((i 0))
    (cond
     ((= i (string-length text)) #f)
     ((char=? (string-ref text i) char) i)
     (else (loop (+ i 1))))))

(define (save-layout! layout)
  (store! layout-key (string-append (number->string (car layout)) "," (number->string (cdr layout)))))
