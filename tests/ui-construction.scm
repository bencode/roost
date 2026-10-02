;; Run: guile --no-auto-compile -L modules tests/ui-construction.scm
(use-modules (srfi srfi-64)
             ((roost dom) #:prefix h/)
             ((roost dom) #:select (section p))
             ((roost props) #:select (props props? props-entries props-ref let-props))
             ((roost hiccup) #:select (make-node component)))

(test-begin "ui-construction")

(test-group "props"
  (let ((attributes (props #:name "Ada" #:email #f)))
    (test-assert "props is a distinct type" (and (props? attributes) (not (list? attributes))))
    (test-equal "keeps keys in order" '(#:name #:email) (map car (props-entries attributes)))
    (test-equal "returns the value" "Ada" (props-ref attributes #:name))
    (test-eq "an existing #f is not replaced by the default" #f (props-ref attributes #:email "x"))
    (test-equal "default only for a missing key" "none" (props-ref attributes #:phone "none"))
    (test-error "missing key without default" #t (props-ref attributes #:phone)))
  (let ((handler (lambda (event) event)))
    (test-eq "keeps value references" handler (props-ref (props #:on-click handler) #:on-click)))
  (let ((evaluated 0))
    (let-props (begin (set! evaluated (+ evaluated 1)) (props #:name "Ada" #:email #f))
        (name email (phone "none"))
      (test-equal "let-props binds properties by name" '("Ada" #f "none") (list name email phone))
      (test-equal "let-props evaluates the props expression once" 1 evaluated)))
  (test-error "let-props without default for a missing key" #t
              (let-props (props) (name) name))
  (test-error "odd argument count" #t (props #:name))
  (test-error "non-keyword key" #t (props 'name "Ada"))
  (test-error "duplicate key" #t (props #:name "Ada" #:name "Bob")))

(test-group "nodes"
  (let ((node (h/section (props #:class "card") (h/h2 "Title"))))
    (test-equal "tag first" "section" (vector-ref node 0))
    (test-assert "props second" (props? (vector-ref node 1)))
    (test-equal "child node" "h2" (vector-ref (vector-ref node 2) 0)))
  (test-equal "node without props" '("p" "Hello") (vector->list (h/p "Hello")))
  (let ((names '("a" "b")))
    (test-equal "a mapped list stays one collection child"
                2 (vector-length (h/ul (map h/li names))))
    (test-assert "the collection keeps its list boundary"
                 (list? (vector-ref (h/ul (map h/li names)) 1)))
    (test-equal "apply spreads children explicitly"
                3 (vector-length (apply h/ul (map h/li names)))))
  (test-equal "conditional children are kept as given"
              '("div" #f 0 ()) (vector->list (h/div #f 0 '())))
  (test-error "props after a child" #t (h/div "text" (props #:class "x")))
  (test-error "second props" #t (h/div (props) (props)))
  (test-error "empty tag" #t (make-node "")))

(test-group "component"
  (let* ((called #f)
         (user-card (lambda (attributes) (set! called #t) (h/p "card")))
         (node (component user-card (props #:name "Ada") (h/p "child"))))
    (test-assert "render is not called" (not called))
    (test-eq "keeps the render procedure" user-card (vector-ref node 0))
    (test-equal "keeps trailing children" "p" (vector-ref (vector-ref node 2) 0)))
  (test-error "a tag string is rejected" #t (component "div"))
  (let ((js-component (vector 'external)))
    (test-eq "non-procedure types are left to the adapter"
             js-component (vector-ref (component js-component) 0))))

(test-group "imports"
  (test-eq "prefixed and selected names are the same procedure" h/section section)
  (test-equal "both build the same node" (vector->list (h/p "x")) (vector->list (p "x")))
  (test-equal "the full HTML element set, including map"
              '("input" "map") (list (vector-ref (h/input) 0) (vector-ref (h/map) 0)))
  (let ((h/h2 (lambda (title) (string-append "local:" title))))
    (test-equal "local bindings shadow imports" "local:Roost" (h/h2 "Roost"))))

(define failures (test-runner-fail-count (test-runner-current)))
(test-end "ui-construction")
(exit (if (zero? failures) 0 1))
