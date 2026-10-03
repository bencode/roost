;; Scenarios for tests/react-adapter.test.js. Observations go to globalThis.roostLog.
(import (scheme base)
        (prefix (roost dom) h/)
        (only (roost props) props props-ref)
        (only (roost hiccup) component)
        (only (roost react) render-root refresh-roots! transfer-component!)
        (only (roost hooks) use-state use-effect)
        (prefix (roost js) js/))

(define (log! . items)
  (js/method (js/ref js/global "roostLog") "push" (apply js/array items)))

;; JavaScript exceptions from calls and from property writes become js-error conditions.
(define (js-error-name thunk)
  (guard (e ((js/error? e) (js/ref (js/error-value e) "name")))
    (thunk)
    "no error"))

(log! "json-parse" (js-error-name (lambda () ((js/ref js/global "JSON" "parse") "{bad"))))
(log! "frozen-set"
      (js-error-name
       (lambda () (js/set! (js/method (js/ref js/global "Object") "freeze" (js/object "a" 1)) "a" 2))))

;; Weak tables keep values as they are; js/typeof reports JavaScript types.
(define table (js/make-weak-table))
(define key (list 'key))
(define value (vector 1 2))
(js/weak-table-set! table key value)
(js/weak-table-set! table value 42)
(log! "weak-table"
      (eq? value (js/weak-table-ref table key #f))
      (js/weak-table-ref table value #f)
      (js/weak-table-ref table (list 'other) "missing"))
(log! "typeof"
      (js/typeof js/global "roostUndefined")
      (js/typeof (js/method (js/ref js/global "JSON") "parse" "{\"a\":null}") "a")
      (js/typeof 1) (js/typeof "s") (js/typeof (lambda () 1)) (js/typeof js/global) (js/typeof (list 1)))

;; Identity: re-rendering the parent keeps the same child component mounted.
(define (child attributes)
  ;; An effect may return no values; (values) is valid Scheme.
  (use-effect (lambda ()
                (log! "child-mounted")
                (js/set! js/global "roostChildEffect" #t)
                (values))
              '())
  (h/p (props-ref attributes #:label)))

(define (identity-parent attributes)
  (let-values (((n set-n!) (use-state 0)))
    (h/div
     (h/button (props #:id "identity-rerender" #:on-click (lambda (event) (set-n! (+ n 1)))) "rerender")
     (component child (props #:label (string-append "render " (number->string n)))))))

;; Children: static children forwarded by a component, and dynamic lists with/without keys.
(define (card attributes)
  (h/section (props #:class "card") (props-ref attributes #:children #f)))

(define (children-demo attributes)
  (h/div
   (component card (props) (h/h2 "Title") (h/p "Body"))
   (h/ul (props #:id "keyed") (map (lambda (x) (h/li (props #:key x) x)) '("a" "b")))))

(define (unkeyed-demo attributes)
  (h/ul (map h/li '("x" "y"))))

;; DOM properties and events.
(define (dom-demo attributes)
  (let-values (((clicks set-clicks!) (use-state 0)))
    (h/button
     (props #:id "dom-button"
            #:class "primary"
            #:aria-label "Increment"
            #:data-count clicks
            #:style (props #:margin-top 8 #:--accent "blue")
            #:on-click (lambda (event) (set-clicks! (lambda (c) (+ c 1)))))
     (number->string clicks))))

;; Hooks: setter identity, updater, lazy initializer, effect deps and cleanup.
(define last-setter #f)
(define (counter attributes)
  (let-values (((items set-items!) (use-state '()))
               ((label set-label!) (use-state (lambda () "items"))))
    (when last-setter (log! "setter-stable" (eq? last-setter set-items!)))
    (set! last-setter set-items!)
    (use-effect (lambda ()
                  (log! "effect" (length items))
                  (lambda () (log! "cleanup")))
                (list set-items! label))
    (h/div
     (h/button (props #:id "counter-add" #:on-click (lambda (event) (set-items! (lambda (l) (cons (vector 'item) l))))) "add")
     (h/button (props #:id "counter-same" #:on-click (lambda (event) (set-label! "items"))) "same")
     (h/output (props #:id "counter-output") (string-append label ": " (number->string (length items)))))))

;; Unsupported child, rendered only after a click.
(define (bad-demo attributes)
  (let-values (((bad? set-bad!) (use-state #f)))
    (h/div
     (h/button (props #:id "bad-trigger" #:on-click (lambda (event) (set-bad! #t))) "break")
     (if bad? (h/p 'not-a-child) (h/p "ok")))))

;; A procedure passed to a JavaScript component keeps one function across renders.
(define Probe (js/ref (js/module "test-components") "Probe"))
(define (stable-callback value) value)
(define (js-identity-parent attributes)
  (let-values (((n set-n!) (use-state 0)))
    (h/div
     (h/button (props #:id "js-rerender" #:on-click (lambda (event) (set-n! (+ n 1)))) "rerender")
     (component Probe (props #:callback stable-callback #:count n)))))

;; Literal strings are cached by identity; a mutable string must show its current content.
(define mutable-title (string-copy "before"))
(define (mutable-text attributes)
  (let-values (((n set-n!) (use-state 0)))
    (h/div
     (h/button (props #:id "mutate"
                      #:on-click (lambda (event)
                                   (string-set! mutable-title 0 #\B)
                                   (set-n! (+ n 1))))
               "mutate")
     (h/p (props #:id "mutable-title" #:class "literal") mutable-title))))

;; Live reloading: rendering into the same element reuses its root, and a transferred
;; component keeps its React type, so its state survives the new definition.
(define (live-v1 attributes)
  (let-values (((n set-n!) (use-state 0)))
    (h/p (props #:id "live-text") "v1 " n
         (h/button (props #:id "live-inc" #:on-click (lambda (event) (set-n! (+ n 1)))) "+"))))

(define (live-v2 attributes)
  (let-values (((n set-n!) (use-state 0)))
    (h/p (props #:id "live-text") "v2 " n
         (h/button (props #:id "live-inc" #:on-click (lambda (event) (set-n! (+ n 1)))) "+"))))

(define (live-controls attributes)
  (h/div
   (h/button (props #:id "live-rerender"
                    #:on-click (lambda (event) (render-root (component live-v1 (props)) "live")))
             "render again")
   (h/button (props #:id "live-transfer"
                    #:on-click (lambda (event) (transfer-component! live-v1 live-v2) (refresh-roots!)))
             "transfer")))

;; A JavaScript component receives DOM-style prop names.
(define Box (js/ref (js/module "test-components") "Box"))

(render-root (component Box (props #:id "box" #:class "selected" #:aria-label "Box" #:data-kind "demo"
                                   #:style (props #:margin-top 8 #:--accent "blue")))
             "js-component")
(render-root (component js-identity-parent (props)) "js-identity")
(render-root (component mutable-text (props)) "mutable")
(render-root (component live-v1 (props)) "live")
(render-root (component live-controls (props)) "live-controls")
(render-root (component identity-parent (props)) "identity")
(render-root (component children-demo (props)) "children")
(render-root (component unkeyed-demo (props)) "unkeyed")
(render-root (component dom-demo (props)) "dom")
(render-root (component counter (props)) "counter")
(render-root (component bad-demo (props)) "bad")
