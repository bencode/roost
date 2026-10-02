;; TodoMVC (todomvc.com) written with Roost.
(import (scheme base)
        (only (hoot lists) filter)
        (prefix (roost dom) h/)
        (only (roost props) props let-props)
        (only (roost hiccup) component)
        (only (roost react) render-root)
        (only (roost hooks) use-state use-effect use-ref)
        (prefix (roost js) js/))

;; Stylesheet: imported only for its side effect.
(js/module "todomvc-app-css/index.css")

(define React (js/module "react"))
(define router-dom (js/module "react-router-dom"))
(define Link (js/ref router-dom "Link"))

(define-record-type <todo>
  (make-todo id title completed?)
  todo?
  (id todo-id)
  (title todo-title)
  (completed? todo-completed?))

(define (with-title todo title)
  (make-todo (todo-id todo) title (todo-completed? todo)))

(define (with-completed todo completed?)
  (make-todo (todo-id todo) (todo-title todo) completed?))

(define (active todos)
  (filter (lambda (todo) (not (todo-completed? todo))) todos))

(define (next-id todos)
  (+ 1 (apply max 0 (map todo-id todos))))

;; Filters by route: "/", "/active", "/completed".
(define (visible todos route)
  (cond
   ((string=? route "/active") (active todos))
   ((string=? route "/completed") (filter todo-completed? todos))
   (else todos)))

;; Persistence in localStorage as JSON.
(define storage-key "todos-roost")
(define storage (js/ref js/global "localStorage"))
(define JSON (js/ref js/global "JSON"))

(define (load-todos)
  (let ((saved (js/method storage "getItem" storage-key)))
    (if saved
        (map (lambda (o) (make-todo (js/ref o "id") (js/ref o "title") (js/ref o "completed")))
             (js/to-scheme (js/method JSON "parse" saved)))
        '())))

(define (save-todos todos)
  (js/method storage "setItem" storage-key
             (js/method JSON "stringify"
                        (js/from-scheme
                         (map (lambda (t)
                                (props #:id (todo-id t) #:title (todo-title t) #:completed (todo-completed? t)))
                              todos)))))

;; No string-trim in R7RS small; use JavaScript's.
(define (trim s) (js/method s "trim"))

(define (event-value event) (js/ref event "target" "value"))
(define (event-key event) (js/ref event "key"))

(define (todo-item attributes)
  (let-props attributes (todo editing? on-toggle on-destroy on-edit on-save on-cancel)
    (let-values (((text set-text!) (use-state (todo-title todo)))
                 ((edit-field) (use-ref #f)))
      (define (submit!) (on-save todo (trim text)))
      ;; Focus the edit field when editing starts.
      (use-effect (lambda ()
                    (when editing?
                      (js/method (js/ref edit-field "current") "focus")))
                  (list editing?))
      (h/li
       (props #:class (string-append (if (todo-completed? todo) "completed " "")
                                     (if editing? "editing" "")))
       (h/div
        (props #:class "view")
        (h/input (props #:class "toggle"
                        #:type "checkbox"
                        #:checked (todo-completed? todo)
                        #:on-change (lambda (event) (on-toggle todo))))
        (h/label (props #:on-double-click (lambda (event)
                                            (set-text! (todo-title todo))
                                            (on-edit todo)))
                 (todo-title todo))
        (h/button (props #:class "destroy" #:on-click (lambda (event) (on-destroy todo)))))
       (and editing?
            (h/input (props #:class "edit"
                            #:ref edit-field
                            #:value text
                            #:on-change (lambda (event) (set-text! (event-value event)))
                            #:on-blur (lambda (event) (submit!))
                            #:on-key-down (lambda (event)
                                            (let ((key (event-key event)))
                                              (cond
                                               ((string=? key "Enter") (submit!))
                                               ((string=? key "Escape") (on-cancel))))))))))))

(define (app attributes)
  (let-values (((todos set-todos!) (use-state load-todos))
               ((text set-text!) (use-state ""))
               ((editing set-editing!) (use-state #f)))
    (define (update-todo! todo f)
      (set-todos! (lambda (todos)
                    (map (lambda (t) (if (= (todo-id t) (todo-id todo)) (f t) t)) todos))))
    (define (add!)
      (let ((title (trim text)))
        (unless (string=? title "")
          (set-todos! (lambda (todos) (append todos (list (make-todo (next-id todos) title #f)))))
          (set-text! ""))))
    (define (toggle! todo)
      (update-todo! todo (lambda (t) (with-completed t (not (todo-completed? t))))))
    (define (remove! todo)
      (set-todos! (lambda (todos) (filter (lambda (t) (not (= (todo-id t) (todo-id todo)))) todos))))
    ;; Saving an empty title deletes the todo.
    (define (save! todo title)
      (if (string=? title "")
          (remove! todo)
          (update-todo! todo (lambda (t) (with-title t title))))
      (set-editing! #f))
    (define (toggle-all! completed?)
      (set-todos! (lambda (todos) (map (lambda (t) (with-completed t completed?)) todos))))
    (define (clear-completed!)
      (set-todos! active))
    (use-effect (lambda () (save-todos todos)) (list todos))
    (let* ((route (js/ref ((js/ref router-dom "useLocation")) "pathname"))
           (left (length (active todos)))
           (done (- (length todos) left)))
      (define (filter-link to name)
        (h/li (component Link (props #:to to #:class (if (string=? route to) "selected" "")) name)))
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
                                        (when (string=? (event-key event) "Enter") (add!))))))
       (and (pair? todos)
            (h/section
             (props #:class "main")
             (h/input (props #:id "toggle-all"
                             #:class "toggle-all"
                             #:type "checkbox"
                             #:checked (= left 0)
                             #:on-change (lambda (event) (toggle-all! (> left 0)))))
             (h/label (props #:for "toggle-all") "Mark all as complete")
             (h/ul
              (props #:class "todo-list")
              (map (lambda (todo)
                     (component todo-item (props #:key (todo-id todo)
                                                 #:todo todo
                                                 #:editing? (and editing (= editing (todo-id todo)))
                                                 #:on-toggle toggle!
                                                 #:on-destroy remove!
                                                 #:on-edit (lambda (todo) (set-editing! (todo-id todo)))
                                                 #:on-save save!
                                                 #:on-cancel (lambda () (set-editing! #f)))))
                   (visible todos route)))))
       (and (pair? todos)
            (h/footer
             (props #:class "footer")
             (h/span (props #:class "todo-count")
                     (h/strong (number->string left))
                     (if (= left 1) " item left" " items left"))
             (h/ul (props #:class "filters")
                   (filter-link "/" "All")
                   (filter-link "/active" "Active")
                   (filter-link "/completed" "Completed"))
             (and (> done 0)
                  (h/button (props #:class "clear-completed" #:on-click (lambda (event) (clear-completed!)))
                            "Clear completed"))))))))

(render-root
 (component (js/ref React "StrictMode") (props)
            (component (js/ref router-dom "HashRouter") (props)
                       (component app (props))))
 "root")
