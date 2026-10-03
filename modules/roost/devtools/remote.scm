;; Terminal REPLs. A page cannot listen for connections, so it connects out to the
;; development server, which relays terminal clients (`pnpm repl`, nc) to it. Each
;; client gets its own session, like the panel's. Messages are JSON:
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
                    => (lambda (session)
                         (send! id (string-append
                                    (vector-ref (session-run! session (js/ref message "text")) 0)
                                    (session-prompt session)))))
                   ((string=? type "close")
                    (set! sessions (filter (lambda (entry) (not (equal? (car entry) id))) sessions))))))
              1))
    socket))
