;; Application modules evaluated from source, in a program compiled with Hoot's run-time
;; module system: reading a module's forms, keeping its source for the REPL commands,
;; and evaluating its definitions again in the running module.
(define-module (roost devtools modules)
  #:pure
  #:export (read-forms sources record-source! module-structure evaluate! reload!)
  #:use-module (scheme base)
  #:use-module ((hoot lists) #:select (filter))
  #:use-module ((hoot modules) #:select (the-root-module resolve-module module-local-variable))
  #:use-module ((hoot eval) #:select (eval))
  #:use-module ((hoot read) #:select (read read-syntax))
  #:use-module ((hoot ports) #:select (port-line port-column))
  #:use-module ((hoot syntax-objects) #:select (syntax->datum syntax-sourcev))
  #:use-module ((roost react) #:select (transfer-component! refresh-roots!))
  #:use-module ((roost devtools sources) #:select (make-module-source module-source-name))
  #:use-module ((roost devtools completion) #:select (defined-names)))

;; Offsets in text where each line starts.
(define (line-starts text)
  (let loop ((i 0) (starts '(0)))
    (cond
     ((= i (string-length text)) (list->vector (reverse starts)))
     ((char=? (string-ref text i) #\newline) (loop (+ i 1) (cons (+ i 1) starts)))
     (else (loop (+ i 1) starts)))))

;; The top-level forms of text, as syntax, with each one's (start . end) offsets in it.
;; A form without a source position starts where the previous one ended.
(define (read-forms text)
  (let ((port (open-input-string text))
        (starts (line-starts text)))
    (define (offset line column) (+ (vector-ref starts line) column))
    (let loop ((forms '()) (spans '()) (previous-end 0))
      (let ((form (read-syntax port)))
        (if (eof-object? form)
            (values (reverse forms) (reverse spans))
            (let ((source (syntax-sourcev form))
                  (end (offset (port-line port) (port-column port))))
              (loop (cons form forms)
                    (cons (cons (if (vector? source)
                                    (offset (vector-ref source 1) (vector-ref source 2))
                                    previous-end)
                                end)
                          spans)
                    end)))))))

;; Each application module's source as it last loaded or reloaded, newest first.
(define loaded-sources '())

(define (sources) loaded-sources)

;; Reads a module's source and records it; returns its forms, as syntax, and their spans.
(define (record-source! name text)
  (call-with-values (lambda () (read-forms text))
    (lambda (forms spans)
      (set! loaded-sources
            (cons (make-module-source name (map syntax->datum forms) text spans)
                  (filter (lambda (source) (not (equal? (module-source-name source) name)))
                          loaded-sources)))
      (values forms spans))))

(define (record-type-form? datum)
  (and (pair? datum) (eq? (car datum) 'define-record-type)))

;; What evaluating a module again cannot change: its header and its record types.
(define (module-structure forms)
  (let ((data (map syntax->datum forms)))
    (if (null? data)
        '()
        (cons (car data) (filter record-type-form? (cdr data))))))

(define (binding module name)
  (let ((variable (module-local-variable module name)))
    (and variable (variable))))

;; A record type that exists already is kept: values in the running application are
;; instances of it.
(define (existing-record-type? module datum)
  (and (record-type-form? datum)
       (pair? (cdr datum))
       (symbol? (cadr datum))
       (module-local-variable module (cadr datum))))

;; Evaluates forms in module, in order, then renders every root again. Components keep
;; their React types, so mounted ones keep their state and show the new definitions.
;; Stops at the first form that raises: returns (index . exception), or #f.
(define (evaluate! module forms)
  (let loop ((forms forms) (index 0))
    (if (null? forms)
        (begin (refresh-roots!) #f)
        (let* ((datum (syntax->datum (car forms)))
               (skip? (existing-record-type? module datum))
               (names (if skip? '() (defined-names (list datum))))
               (old (map (lambda (name) (binding module name)) names))
               (failure (and (not skip?)
                             (guard (e (#t e))
                               (eval (car forms) module)
                               #f))))
          (for-each (lambda (name old)
                      (let ((new (binding module name)))
                        (when (and (procedure? old) (procedure? new))
                          (transfer-component! old new))))
                    names old)
          (if failure
              (begin (refresh-roots!) (cons index failure))
              (loop (cdr forms) (+ index 1)))))))

;; Evaluates a saved module's definitions in the running module; raises what a form
;; raises. The development server reloads the page when a record type changes.
(define (reload! source)
  (let ((modname (cadr (read (open-input-string source)))))   ; (define-module NAME ...)
    (call-with-values (lambda () (record-source! modname source))
      (lambda (forms spans)
        (let ((failure (evaluate! (resolve-module (the-root-module) modname) (cdr forms))))
          (when failure (raise (cdr failure))))))))
