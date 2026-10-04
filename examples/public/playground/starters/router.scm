;; React Router, used directly: its components and hooks are JavaScript values.
(define-module (playground)
  #:pure
  #:use-module (scheme base)
  #:use-module ((roost dom) #:prefix h/)
  #:use-module ((roost props) #:select (props))
  #:use-module ((roost hiccup) #:select (component))
  #:use-module ((roost react) #:select (render-root))
  #:use-module ((roost js) #:prefix js/))

(define router-dom (js/module "react-router-dom"))
(define (router name) (js/ref router-dom name))

(define pages '(("/" . "Home") ("/about" . "About") ("/users/42" . "User 42")))

(define (nav attributes)
  (h/nav (map (lambda (page)
                (h/span (props #:key (car page))
                        (component (router "Link") (props #:to (car page)) (cdr page))
                        " "))
              pages)))

(define (user attributes)
  (let ((id (js/ref ((router "useParams")) "id")))
    (h/p "User " (h/strong id))))

(define (app attributes)
  (h/section
   (h/h2 "Router")
   (component nav (props))
   (component (router "Routes") (props)
              (component (router "Route") (props #:path "/" #:element (h/p "Home page")))
              (component (router "Route") (props #:path "/about" #:element (h/p "About this playground")))
              (component (router "Route") (props #:path "/users/:id" #:element (component user (props)))))))

(render-root (component (router "HashRouter") (props) (component app (props))) "root")
