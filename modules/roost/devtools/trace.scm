;; Tracing: a traced procedure records each call, with its arguments and what it
;; returned or raised, while the program runs. The records stay in the page until
;; taken, so a one-shot REPL can trace, let the page run, and come back for them.
;;
;; Only the application's modules can be traced: they are loaded from source, so their
;; variables can be given a new value, which every module importing them sees.
(define-module (roost devtools trace)
  #:pure
  #:export (trace! untrace! take-trace!)
  #:use-module (scheme base)
  #:use-module (scheme write)
  #:use-module ((hoot lists) #:select (filter))
  #:use-module ((hoot modules) #:select (module-variable module-name))
  #:use-module ((hoot exceptions) #:select (exception-with-origin? exception-origin
                                            exception-with-message? exception-message
                                            exception-with-irritants? exception-irritants))
  #:use-module ((roost react) #:select (transfer-component!))
  #:use-module ((roost devtools sources) #:select (source-of)))

(define record-limit 200)
(define value-width 120)

;; var: the traced variable; label: "cart-set (store cart)".
(define-record-type <traced>
  (make-traced var original wrapper label)
  traced?
  (var traced-var)
  (original traced-original)
  (wrapper traced-wrapper)
  (label traced-label))

;; result: what the call returned or raised, or #f while it runs.
(define-record-type <call>
  (make-call depth text result)
  call?
  (depth call-depth)
  (text call-text)
  (result call-result set-call-result!))

(define traced '())
(define calls '())            ; newest first, at most record-limit
(define depth 0)

;;; Text

(define (clip text)
  (if (> (string-length text) value-width)
      (string-append (substring text 0 (- value-width 1)) "…")
      text))

(define (written value)
  (let ((port (open-output-string)))
    (write value port)
    (clip (get-output-string port))))

(define (join texts separator)
  (if (null? texts)
      ""
      (apply string-append (car texts) (map (lambda (text) (string-append separator text)) (cdr texts)))))

;; "car: type check failed 1"
(define (summary e)
  (if (exception-with-message? e)
      (join (append (if (exception-with-origin? e) (list (string-append (written (exception-origin e)) ":")) '())
                    (list (exception-message e))
                    (map written (if (exception-with-irritants? e) (exception-irritants e) '())))
            " ")
      (written e)))

;;; Recording

(define (record! call)
  (set! calls (let ((kept (cons call calls)))
                (if (> (length kept) record-limit) (list-head kept record-limit) kept))))

(define (list-head items n)
  (if (or (= n 0) (null? items)) '() (cons (car items) (list-head (cdr items) (- n 1)))))

;; Records each call of original under name, then makes it.
(define (make-wrapper name original)
  (lambda args
    (let ((call (make-call depth (string-append "(" (join (cons (symbol->string name) (map written args)) " ") ")")
                           #f)))
      (record! call)
      (dynamic-wind
       (lambda () (set! depth (+ depth 1)))
       (lambda ()
         (call-with-values
             (lambda ()
               ;; guard, not with-exception-handler: Hoot's REPL loses its session when a
               ;; handler raises again. The exception goes on unchanged; a backtrace then
               ;; starts here.
               (guard (e (#t (set-call-result! call (string-append "raised: " (summary e)))
                             (raise e)))
                 (apply original args)))
           (lambda results
             (set-call-result! call (join (map written results) " "))
             (apply values results))))
       (lambda () (set! depth (- depth 1)))))))

;;; Tracing

;; The variable name refers to in module, with the module and name it is defined as:
;; (values var defining-module defined-name).
(define (lookup module name)
  (module-variable module name #:private? #t
                   #:found values
                   #:not-found (lambda () (error "trace: no such name here:" name))))

(define (find-traced var)
  (let loop ((entries traced))
    (cond
     ((null? entries) #f)
     ((eq? (traced-var (car entries)) var) (car entries))
     (else (loop (cdr entries))))))

;; Traces name as module sees it, from its next call on: callers read the variable when
;; they call, and React renders a component's type, which the wrapper takes over.
;; sources: the application modules' sources. Returns what it did, as text.
(define (trace! sources module name)
  (drop-redefined!)
  (call-with-values (lambda () (lookup module name))
    (lambda (var defining defined-name)
      (let ((label (string-append (symbol->string defined-name) " " (written (module-name defining))))
            (value (var)))
        (cond
         ((not (source-of (sources) (module-name defining)))
          (error (string-append "trace: " label " is compiled; only the application's modules can be traced")))
         ((not (procedure? value)) (error "trace: not a procedure:" name))
         ((find-traced var) (string-append "already tracing " label))
         (else
          (let ((wrapper (make-wrapper defined-name value)))
            (var wrapper)
            ;; A component keeps its React type, so mounted ones keep their state.
            (transfer-component! value wrapper)
            (set! traced (cons (make-traced var value wrapper label) traced))
            (string-append "tracing " label))))))))

(define (restore! entry)
  (when (eq? ((traced-var entry)) (traced-wrapper entry))
    ((traced-var entry) (traced-original entry))
    (transfer-component! (traced-wrapper entry) (traced-original entry))))

;; Stops tracing names as module sees them, or everything when names is empty.
(define (untrace! module names)
  (drop-redefined!)
  (let ((entries (if (null? names)
                     traced
                     (map (lambda (name)
                            (call-with-values (lambda () (lookup module name))
                              (lambda (var defining defined-name)
                                (or (find-traced var) (error "trace: not traced:" name)))))
                          names))))
    (for-each restore! entries)
    (set! traced (filter (lambda (entry) (not (memq entry entries))) traced))
    (if (null? entries)
        "nothing traced"
        (join (map (lambda (entry) (string-append "untraced " (traced-label entry))) entries) "\n"))))

;; Saving a traced module defines its procedures again, which ends their traces.
(define (drop-redefined!)
  (let ((ended (filter (lambda (entry) (not (eq? ((traced-var entry)) (traced-wrapper entry)))) traced)))
    (set! traced (filter (lambda (entry) (not (memq entry ended))) traced))
    ended))

;; The calls recorded since the last take, oldest first, and what is traced; clears the
;; records.
(define (take-trace!)
  (let ((ended (drop-redefined!))
        (taken (reverse calls)))
    (set! calls '())
    (join (append
           (if (null? taken)
               '("no calls")
               (map (lambda (call)
                      (string-append (make-string (* 2 (call-depth call)) #\space)
                                     (call-text call) " => " (or (call-result call) "…")))
                    taken))
           (map (lambda (entry) (string-append (traced-label entry) " (redefined: trace ended)")) ended)
           (list (if (null? traced)
                     "tracing: nothing"
                     (string-append "tracing: " (join (map traced-label (reverse traced)) ", ")))))
          "\n")))
