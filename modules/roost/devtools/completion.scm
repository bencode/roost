;; Completion for the REPL panel's editor: the names visible in a module.
;;
;; Hoot's run-time modules do not list their bindings, so the names come from the
;; module's source: what its header imports, expanded as the import specs say, and
;; what its body defines.
(define-module (roost devtools completion)
  #:pure
  #:export (visible-names defined-names source-defined-names completion-source)
  #:use-module (scheme base)
  #:use-module (scheme cxr)
  #:use-module (scheme lazy)
  #:use-module ((hoot lists) #:select (sort))
  #:use-module ((hoot modules) #:select (the-root-module resolve-module module-exported-names))
  #:use-module ((hoot read) #:select (read))
  #:use-module ((roost js) #:prefix js/))

(define (keep pred items)
  (let loop ((items items) (kept '()))
    (cond
     ((null? items) (reverse kept))
     ((pred (car items)) (loop (cdr items) (cons (car items) kept)))
     (else (loop (cdr items) kept)))))

(define (library-names name)
  (let ((module (and (list? name) (resolve-module (the-root-module) name))))
    (if module (module-exported-names module) '())))

(define (prefixed prefix names)
  (map (lambda (name) (string->symbol (string-append (symbol->string prefix) (symbol->string name))))
       names))

;; (only s id ...), (except s id ...), (prefix s p), (rename s (from to) ...), or a name.
(define (r7rs-names spec)
  (case (and (pair? spec) (car spec))
    ((only) (keep (lambda (name) (memq name (cddr spec))) (r7rs-names (cadr spec))))
    ((except) (keep (lambda (name) (not (memq name (cddr spec)))) (r7rs-names (cadr spec))))
    ((prefix) (prefixed (caddr spec) (r7rs-names (cadr spec))))
    ((rename) (map (lambda (name)
                     (let ((renamed (assq name (cddr spec))))
                       (if renamed (cadr renamed) name)))
                   (r7rs-names (cadr spec))))
    (else (library-names spec))))

;; (lib) or ((lib) #:select (id (from . to) ...) #:hide (id ...) #:prefix p).
(define (guile-names spec)
  (if (and (pair? spec) (pair? (car spec)))
      (let loop ((options (cdr spec)) (names (library-names (car spec))))
        (if (or (null? options) (null? (cdr options)))
            names
            (let ((value (cadr options)))
              (loop (cddr options)
                    (cond
                     ((eq? (car options) #:select)
                      (map (lambda (item) (if (pair? item) (cdr item) item)) value))
                     ((eq? (car options) #:hide)
                      (keep (lambda (name) (not (memq name value))) names))
                     ((eq? (car options) #:prefix) (prefixed value names))
                     (else names))))))
      (library-names spec)))

(define (imported-names header)
  (case (and (pair? header) (car header))
    ((define-module)
     (let loop ((args (cddr header)) (names '()))
       (cond
        ((or (null? args) (null? (cdr args))) names)
        ((eq? (car args) #:use-module) (loop (cddr args) (append (guile-names (cadr args)) names)))
        (else (loop (cdr args) names)))))
    ((define-library)
     (apply append (map (lambda (clause)
                          (if (and (pair? clause) (eq? (car clause) 'import))
                              (apply append (map r7rs-names (cdr clause)))
                              '()))
                        (cddr header))))
    (else '())))

;; The names top-level forms define.
(define (defined-names forms)
  (define (form-names form)
    (if (not (pair? form))
        '()
        (case (car form)
          ((define define-syntax define-syntax-rule)
           (let loop ((target (and (pair? (cdr form)) (cadr form))))
             (cond
              ((symbol? target) (list target))
              ((pair? target) (loop (car target)))
              (else '()))))
          ((define-record-type)
           (if (and (pair? (cdr form)) (pair? (cddr form)))
               (let ((constructor (caddr form))
                     (rest (cdddr form)))
                 (append (list (cadr form))
                         (if (pair? constructor) (list (car constructor)) '())
                         (if (pair? rest) (list (car rest)) '())
                         (apply append (map (lambda (field) (if (pair? field) (cdr field) '()))
                                            (if (pair? rest) (cdr rest) '())))))
               '()))
          (else '()))))
  (keep symbol? (apply append (map form-names forms))))

;; The names that source text defines, as strings. The text must read.
(define (source-defined-names source)
  (let ((port (open-input-string source)))
    (let loop ((forms '()))
      (let ((form (read port)))
        (if (eof-object? form)
            (map symbol->string (defined-names (reverse forms)))
            (loop (cons form forms)))))))

;; forms: the module's top-level forms (its header first), or #f when unknown.
;; extra: further names, as strings. Returns sorted, distinct strings.
(define (visible-names forms extra)
  (let* ((symbols (if forms
                      (append (imported-names (car forms)) (defined-names (cdr forms)))
                      '()))
         (all (append (map symbol->string symbols) extra)))
    (let loop ((names (sort all string<?)) (result '()))
      (cond
       ((null? names) (reverse result))
       ((and (pair? result) (string=? (car names) (car result))) (loop (cdr names) result))
       (else (loop (cdr names) (cons (car names) result)))))))

;; A CodeMirror completion source offering (names), a thunk so the names are current.
(define identifier (delay (js/new (js/ref js/global "RegExp") "[^\\s()\\[\\]{}\"';`,|]+")))

(define (completion-source names)
  (js/function
   (lambda (context)
     (let ((word (js/method context "matchBefore" (force identifier))))
       (and word
            (or (< (js/ref word "from") (js/ref word "to")) (js/ref context "explicit"))
            (js/object "from" (js/ref word "from")
                       "validFor" (force identifier)
                       "options" (apply js/array (map (lambda (name) (js/object "label" name)) (names)))))))
   1))
