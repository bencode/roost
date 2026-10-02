;; React Router and TanStack Query used directly from Scheme; no bridge code.
(import (scheme base)
        (prefix (roost dom) h/)
        (only (roost props) props props-ref)
        (only (roost hiccup) component)
        (only (roost react) render-root)
        (prefix (roost js) js/))

(define router-dom (js/module "react-router-dom"))
(define query (js/module "@tanstack/react-query"))
(define Link (js/ref router-dom "Link"))

;; A pretend API: resolves after a short delay.
(define (fetch-user id)
  (js/new (js/ref js/global "Promise")
          (lambda (resolve reject)
            ((js/ref js/global "setTimeout")
             (lambda () (resolve (js/from-scheme (props #:id id #:name (string-append "User " id)))))
             300))))

(define (user-page attributes)
  (let* ((id (js/ref ((js/ref router-dom "useParams")) "id"))
         (result ((js/ref query "useQuery")
                  (js/from-scheme (props #:query-key (list "user" id)
                                         #:query-fn (lambda (context) (fetch-user id)))))))
    (h/section
     (h/h2 (string-append "User " id))
     (if (js/ref result "isPending")
         (h/p "Loading...")
         (h/p (string-append "Loaded: " (js/ref result "data" "name"))))
     (component Link (props #:to "/") "Back"))))

(define (home attributes)
  (let ((navigate ((js/ref router-dom "useNavigate"))))
    (h/section
     (h/h2 "Users")
     (h/ul
      (map (lambda (id)
             (h/li (props #:key id) (component Link (props #:to (string-append "/users/" id)) (string-append "User " id))))
           '("1" "2" "3")))
     (h/button (props #:on-click (lambda (event) (navigate "/users/42"))) "Open user 42"))))

(define router
  ((js/ref router-dom "createHashRouter")
   (js/from-scheme
    (list (props #:path "/" #:element (component home (props)))
          (props #:path "/users/:id" #:element (component user-page (props)))))))

(render-root
 (component (js/ref query "QueryClientProvider")
            (props #:client (js/new (js/ref query "QueryClient")))
            (component (js/ref router-dom "RouterProvider") (props #:router router)))
 "root")
