;; Terminal REPLs. A page cannot listen for connections, so it connects out to the
;; development server, which relays terminal clients (`pnpm repl`, nc) to it. Each
;; client gets its own session. Messages are JSON:
;;   from the server: {type: "open" | "input" | "close", id, text}
;;   to the server:   {type: "output", id, text}   (output, then the next prompt)
(define-module (roost devtools remote)
  #:pure
  #:export (connect-terminals!)
  #:use-module (scheme base)
  #:use-module ((hoot lists) #:select (filter))
  #:use-module ((roost js) #:prefix js/)
  #:use-module ((roost devtools session) #:select (session-run! session-prompt)))

(define welcome
  "Roost REPL, in the running page. ,help lists the commands; ,m (module) enters a module.\n")

(define (json) (js/ref js/global "JSON"))

;; new-session: makes a session for a client that connects.
(define (connect-terminals! url new-session)
  (let ((socket (js/new (js/ref js/global "WebSocket") url))
        (sessions '()))
    (define (send! id text)
      (js/method socket "send"
                 (js/method (json) "stringify" (js/object "type" "output" "id" id "text" text))))
    (define (session-of id)
      (let ((entry (assoc id sessions)))
        (and entry (cdr entry))))
    (define (replace-session! id)
      (let ((session (new-session)))
        (set! sessions (cons (cons id session)
                             (filter (lambda (entry) (not (equal? (car entry) id))) sessions)))
        session))
    ;; Hoot's REPL does not catch everything: an exception raised again inside an
    ;; exception handler quits the program's evaluation with a JavaScript throw, which no
    ;; Scheme handler sees, and the Scheme code that called it cannot go on. So each
    ;; evaluation starts afresh from JavaScript, in a promise's callback; a throw rejects
    ;; the promise, and the client hears of it rather than waiting. The session, left in
    ;; an unknown state, is replaced.
    (define (run! id session text)
      (js/method
       (js/method (js/method (js/ref js/global "Promise") "resolve")
                  "then"
                  ;; Called with undefined, which a callback without a length does not
                  ;; receive.
                  (lambda ()
                    (string-append (vector-ref (session-run! session text) 0)
                                   (session-prompt session))))
       "then"
       (lambda (output) (send! id output))
       (lambda (error)
         (js/method (js/ref js/global "console") "error" "roost repl:" error)
         (send! id (string-append "Scheme error:\n  roost: the evaluation escaped Hoot's error handling;"
                                  " the session was reset\n"
                                  (session-prompt (replace-session! id)))))))
    (js/set! socket "onmessage"
             (js/function
              (lambda (event)
                (let* ((message (js/method (json) "parse" (js/ref event "data")))
                       (type (js/ref message "type"))
                       (id (js/ref message "id")))
                  (cond
                   ((string=? type "open")
                    (let ((session (new-session)))
                      (set! sessions (cons (cons id session) sessions))
                      (send! id (string-append welcome (session-prompt session)))))
                   ((and (string=? type "input") (session-of id))
                    => (lambda (session) (run! id session (js/ref message "text"))))
                   ((string=? type "close")
                    (set! sessions (filter (lambda (entry) (not (equal? (car entry) id))) sessions))))))
              1))
    socket))
