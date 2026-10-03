;; The application modules' sources, as the development shell last loaded them. The
;; REPL completes names from them and shows definitions from them.
(define-module (roost devtools sources)
  #:pure
  #:export (make-module-source module-source-name module-source-forms module-source-text
            module-source-spans source-of source-forms-of)
  #:use-module (scheme base))

;; forms: the top-level forms, as data, the header first. spans: each form's
;; (start . end) offsets in text.
(define-record-type <module-source>
  (make-module-source name forms text spans)
  module-source?
  (name module-source-name)
  (forms module-source-forms)
  (text module-source-text)
  (spans module-source-spans))

;; The source of the module named name, such as (store cart), or #f.
(define (source-of sources name)
  (let loop ((sources sources))
    (cond
     ((null? sources) #f)
     ((equal? (module-source-name (car sources)) name) (car sources))
     (else (loop (cdr sources))))))

(define (source-forms-of sources name)
  (let ((source (source-of sources name)))
    (and source (module-source-forms source))))
