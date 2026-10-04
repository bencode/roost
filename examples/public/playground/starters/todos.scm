;; A list of records, an input, and a filter. Try (todo-title (car items)) in the REPL.
(define-module (playground)
  #:pure
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost react) #:select (render-root))
  #:use-module ((roost hooks) #:select (use-state))
  #:use-module ((roost js) #:prefix js/))

(define-record-type <todo>
  (make-todo id title done?)
  todo?
  (id todo-id)
  (title todo-title)
  (done? todo-done?))

(define items
  (list (make-todo 1 "Write a component" #t)
        (make-todo 2 "Run it in the playground" #f)
        (make-todo 3 "Change it while it runs" #f)))

(define (toggle todo)
  (make-todo (todo-id todo) (todo-title todo) (not (todo-done? todo))))

(define (visible todos show)
  (cond
   ((eq? show 'open) (filter-todos (lambda (todo) (not (todo-done? todo))) todos))
   ((eq? show 'done) (filter-todos todo-done? todos))
   (else todos)))

(define (filter-todos keep? todos)
  (cond
   ((null? todos) '())
   ((keep? (car todos)) (cons (car todos) (filter-todos keep? (cdr todos))))
   (else (filter-todos keep? (cdr todos)))))

(define (todos attributes)
  (let-values (((todos set-todos!) (use-state items))
               ((text set-text!) (use-state ""))
               ((show set-show!) (use-state 'all)))
    (define (add!)
      (unless (string=? text "")
        (set-todos! (append todos (list (make-todo (+ 1 (length todos)) text #f))))
        (set-text! "")))
    (h/section
     (h/h2 "Todos")
     (h/input (props #:value text
                     #:placeholder "What next?"
                     #:on-change (lambda (event) (set-text! (js/ref event "target" "value")))
                     #:on-key-down (lambda (event)
                                     (when (string=? (js/ref event "key") "Enter") (add!)))))
     (h/ul
      (map (lambda (todo)
             (h/li (props #:key (todo-id todo))
                   (h/label
                    (h/input (props #:type "checkbox"
                                    #:checked (todo-done? todo)
                                    #:on-change (lambda (event)
                                                  (set-todos! (map (lambda (t) (if (eq? t todo) (toggle t) t))
                                                                   todos)))))
                    " " (todo-title todo))))
           (visible todos show)))
     (h/p (map (lambda (option)
                 (h/button (props #:key (symbol->string option)
                                  #:disabled (eq? option show)
                                  #:on-click (lambda (event) (set-show! option)))
                           (symbol->string option)))
               '(all open done))))))

(render-root (component todos (props)) "root")
