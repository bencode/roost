;; Meta-commands Roost adds to Hoot's REPL, for looking into the running program:
;; ,names ,apropos ,source ,trace ,untrace, and a ,bt that leaves out frames unrelated
;; to the error.
(define-module (roost devtools commands)
  #:pure
  #:export (repl-commands)
  #:use-module (scheme base)
  #:use-module (scheme write)
  #:use-module ((hoot lists) #:select (filter sort))
  #:use-module ((hoot modules) #:select (module-name module-exported-names))
  #:use-module ((hoot repl) #:select (make-meta-command repl-environment repl-environment-module
                                      repl-environment-data repl-debug? repl-debug-exception
                                      repl-debug-stack))
  #:use-module ((hoot error-handling) #:select (format-exception print-backtrace))
  #:use-module ((hoot exceptions) #:select (exception-with-origin? exception-origin
                                            exception-with-source? exception-source-file
                                            exception-source-line exception-source-column))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools completion) #:select (visible-names defined-names))
  #:use-module ((roost devtools trace) #:select (trace! untrace! take-trace!))
  #:use-module (roost devtools sources))

;;; Text helpers

;; Commands take the rest of their line as one argument, trimmed.
(define (rest-of-line repl port)
  (let ((line (read-line port)))
    (list (if (eof-object? line) "" (js/method line "trim")))))

(define (contains? text part) (js/method text "includes" part))

(define (starts-with? text prefix) (js/method text "startsWith" prefix))

(define (lines text) (js/to-scheme (js/method text "split" "\n")))

;; The names on a command line, as symbols.
(define (names-in text)
  (map string->symbol (filter (lambda (word) (not (string=? word "")))
                              (js/to-scheme (js/method text "split" (js/new (js/ref js/global "RegExp") "\\s+"))))))

(define (join-lines lines) (js/method (apply js/array lines) "join" "\n"))

(define (written datum)
  (let ((port (open-output-string)))
    (write datum port)
    (get-output-string port)))

;; Prints strings in columns across 80 characters.
(define (print-columns strings)
  (let* ((width (+ 2 (apply max 0 (map string-length strings))))
         (per-line (max 1 (quotient 80 width))))
    (let loop ((strings strings) (column 0))
      (cond
       ((null? strings) (unless (= column 0) (newline)))
       ((= column per-line) (newline) (loop strings 0))
       (else
        (let ((s (car strings)))
          (display s)
          (when (and (pair? (cdr strings)) (< (+ column 1) per-line))
            (display (make-string (- width (string-length s)) #\space)))
          (loop (cdr strings) (+ column 1))))))))

;;; Definitions in the application's sources

(define (current-module repl) (repl-environment-module (repl-environment repl)))

;; The start of the line holding offset i.
(define (line-start text i)
  (if (and (> i 0) (not (char=? (string-ref text (- i 1)) #\newline)))
      (line-start text (- i 1))
      i))

;; Moves start up over the comment lines directly above it.
(define (comments-above text start)
  (if (= start 0)
      start
      (let* ((previous (line-start text (- start 1)))
             (line (js/method (substring text previous (- start 1)) "trim")))
        (if (starts-with? line ";") (comments-above text previous) start))))

;; The text of the form defining name in entry, with its comments, or #f.
(define (definition-text entry name)
  (let loop ((forms (module-source-forms entry)) (spans (module-source-spans entry)))
    (cond
     ((null? forms) #f)
     ((memq name (defined-names (list (car forms))))
      (let ((text (module-source-text entry)) (span (car spans)))
        (substring text (comments-above text (line-start text (car span))) (cdr span))))
     (else (loop (cdr forms) (cdr spans))))))

;;; Commands

(define (names-command sources defined)
  (make-meta-command
   #:name 'names #:group 'roost #:usage "[PREFIX]"
   #:summary "List the names the current module sees, or those starting with PREFIX."
   #:reader rest-of-line
   #:proc (lambda (repl prefix)
            (let* ((module (current-module repl))
                   (entry (source-of (sources) (module-name module)))
                   (names (if entry
                              (visible-names (module-source-forms entry) (defined))
                              (map symbol->string (module-exported-names module)))))
              (print-columns (filter (lambda (name) (starts-with? name prefix)) names))))))

(define (apropos-command sources)
  (make-meta-command
   #:name 'apropos #:aliases '(a) #:group 'roost #:usage "TEXT"
   #:summary "Find the application's definitions whose names contain TEXT."
   #:reader rest-of-line
   #:proc (lambda (repl text)
            (let ((matches
                   (sort (apply append
                                (map (lambda (entry)
                                       (map (lambda (name) (cons (symbol->string name) (module-source-name entry)))
                                            (defined-names (cdr (module-source-forms entry)))))
                                     (sources)))
                         (lambda (a b) (string<? (car a) (car b))))))
              (let ((found (filter (lambda (match) (contains? (car match) text)) matches)))
                (if (null? found)
                    (begin (display "No definition's name contains ") (write text) (newline))
                    (let ((width (+ 2 (apply max (map (lambda (m) (string-length (car m))) found)))))
                      (for-each (lambda (match)
                                  (display (car match))
                                  (display (make-string (- width (string-length (car match))) #\space))
                                  (write (cdr match))
                                  (newline))
                                found))))))))

(define (source-command sources)
  (make-meta-command
   #:name 'source #:group 'roost #:usage "NAME"
   #:summary "Show the source of NAME's definition: the current module's, or another's."
   #:reader rest-of-line
   #:proc (lambda (repl text)
            (let* ((name (string->symbol text))
                   (entries (sources))
                   (here (source-of entries (module-name (current-module repl))))
                   (ordered (if here (cons here (filter (lambda (e) (not (eq? e here))) entries)) entries)))
              (let loop ((entries ordered))
                (cond
                 ((null? entries)
                  (display "No definition of ") (display text)
                  (display " in the application's modules.") (newline))
                 ((definition-text (car entries) name)
                  => (lambda (definition)
                       (display ";; ") (display (written (module-source-name (car entries)))) (newline)
                       (display definition) (newline)))
                 (else (loop (cdr entries)))))))))

;; Frames of interpreted code have no name; they say nothing about where an error is.
(define (named-frames text)
  (let loop ((lines (filter (lambda (line) (not (contains? line "(\"_\" "))) (lines text)))
             (kept '()))
    (cond
     ((null? lines) (join-lines (reverse kept)))
     ;; A file heading whose frames were all left out goes too.
     ((and (starts-with? (car lines) "In ")
           (or (null? (cdr lines)) (not (starts-with? (cadr lines) " "))))
      (loop (cdr lines) kept))
     (else (loop (cdr lines) (cons (car lines) kept))))))

(define (backtrace-command entry-height)
  (make-meta-command
   #:name 'backtrace #:aliases '(bt) #:group 'debug #:usage "[all]"
   #:summary "Print a backtrace of the error; `all' keeps every frame."
   #:reader rest-of-line
   #:proc (lambda (repl which)
            (let ((debug (repl-environment-data (repl-environment repl))))
              (unless (repl-debug? debug) (error "Not in a debugger."))
              (let* ((exn (repl-debug-exception debug))
                     (stack (repl-debug-stack debug))
                     (all? (string=? which "all"))
                     ;; Frames below where the evaluation began belong to whatever ran
                     ;; the REPL: the terminal connection, the REPL itself.
                     (frames (if all? stack (vector-copy stack (min (entry-height) (vector-length stack)))))
                     (port (open-output-string)))
                (format-exception exn (current-output-port))
                (newline)
                (newline)
                (call-with-values (lambda ()
                                    (if (exception-with-source? exn)
                                        (values (exception-source-file exn)
                                                (exception-source-line exn)
                                                (exception-source-column exn))
                                        (values #f #f #f)))
                  (lambda (file line column)
                    (print-backtrace frames (and (exception-with-origin? exn) (exception-origin exn))
                                     file line column port)))
                (display (if all? (get-output-string port) (named-frames (get-output-string port))))
                (newline))))))

;; sources: returns the application modules' sources (<module-source>). The result, given a session's
;; entry-height and defined-names thunks, is the list of commands for it.
(define (trace-command sources)
  (make-meta-command
   #:name 'trace #:group 'roost #:usage "[NAME ...]"
   #:summary "Trace calls of NAMEs; without names, show and clear the calls traced so far."
   #:reader rest-of-line
   #:proc (lambda (repl text)
            (let ((names (names-in text)))
              (display (if (null? names)
                           (take-trace!)
                           (join-lines (map (lambda (name) (trace! sources (current-module repl) name))
                                            names))))
              (newline)))))

(define (untrace-command)
  (make-meta-command
   #:name 'untrace #:group 'roost #:usage "[NAME ...]"
   #:summary "Stop tracing NAMEs, or everything."
   #:reader rest-of-line
   #:proc (lambda (repl text)
            (display (untrace! (current-module repl) (names-in text)))
            (newline))))

(define (repl-commands sources)
  (lambda (entry-height defined)
    (list (names-command sources defined)
          (apropos-command sources)
          (source-command sources)
          (trace-command sources)
          (untrace-command)
          (backtrace-command entry-height))))
