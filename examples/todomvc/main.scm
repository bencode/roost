;; TodoMVC, iteration 1: add, toggle, delete, items-left count.
(import (scheme base)
        (only (hoot lists) filter)
        (prefix (roost dom) h/)
        (only (roost props) props props-ref)
        (only (roost hiccup) component)
        (only (roost react) render-root)
        (only (roost hooks) use-state)
        (prefix (roost js) js/))

;; Stylesheet: imported only for its side effect.
(js/module "todomvc-app-css/index.css")

(define-record-type <todo>
  (make-todo id title completed?)
  todo?
  (id todo-id)
  (title todo-title)
  (completed? todo-completed?))

(define (toggle todo)
  (make-todo (todo-id todo) (todo-title todo) (not (todo-completed? todo))))

(define (remaining todos)
  (length (filter (lambda (todo) (not (todo-completed? todo))) todos)))

;; No string-trim in R7RS small; use JavaScript's.
(define (trim s) (js/method s "trim"))

(define (event-value event) (js/ref event "target" "value"))

(define (todo-item attributes)
  (let ((todo (props-ref attributes #:todo))
        (on-toggle (props-ref attributes #:on-toggle))
        (on-destroy (props-ref attributes #:on-destroy)))
    (h/li
     (props #:class (if (todo-completed? todo) "completed" ""))
     (h/div
      (props #:class "view")
      (h/input (props #:class "toggle"
                      #:type "checkbox"
                      #:checked (todo-completed? todo)
                      #:on-change (lambda (event) (on-toggle todo))))
      (h/label (todo-title todo))
      (h/button (props #:class "destroy" #:on-click (lambda (event) (on-destroy todo))))))))

(define (app attributes)
  (let-values (((todos set-todos!) (use-state '()))
               ((text set-text!) (use-state ""))
               ((next-id set-next-id!) (use-state 1)))
    (define (add!)
      (let ((title (trim text)))
        (unless (string=? title "")
          (set-todos! (lambda (todos) (append todos (list (make-todo next-id title #f)))))
          (set-next-id! (+ next-id 1))
          (set-text! ""))))
    (define (toggle! todo)
      (set-todos! (lambda (todos)
                    (map (lambda (t) (if (= (todo-id t) (todo-id todo)) (toggle t) t)) todos))))
    (define (remove! todo)
      (set-todos! (lambda (todos)
                    (filter (lambda (t) (not (= (todo-id t) (todo-id todo)))) todos))))
    (let ((left (remaining todos)))
      (h/section
       (props #:class "todoapp")
       (h/header
        (props #:class "header")
        (h/h1 "todos")
        (h/input (props #:class "new-todo"
                        #:placeholder "What needs to be done?"
                        #:auto-focus #t
                        #:value text
                        #:on-change (lambda (event) (set-text! (event-value event)))
                        #:on-key-down (lambda (event)
                                        (when (string=? (js/ref event "key") "Enter") (add!))))))
       (h/section
        (props #:class "main")
        (h/ul
         (props #:class "todo-list")
         (map (lambda (todo)
                (component todo-item (props #:key (todo-id todo)
                                            #:todo todo
                                            #:on-toggle toggle!
                                            #:on-destroy remove!)))
              todos)))
       (h/footer
        (props #:class "footer")
        (h/span (props #:class "todo-count")
                (h/strong (number->string left))
                (if (= left 1) " item left" " items left")))))))

(render-root (component app (props)) "root")
