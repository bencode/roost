# Using Roost

How to write components, state, effects, and calls into JavaScript with Roost, and how to develop in a running page, drawn from the examples in this repository. [Design principles](design-principles.md) explains how Roost works and why; this guide is about using it. The snippets are taken from the examples, most of them from the [checkout page](../examples/checkout/main.scm).

## Components

A component is a procedure of its props. `let-props` binds them by name, with defaults in parentheses:

```scheme
(define (text-field attributes)
  (let-props attributes (label name value on-change on-blur error (type "text") (placeholder ""))
    (h/label
     (props #:class (if error "field invalid" "field"))
     (h/span label)
     (h/input (props #:name name #:type type #:value value #:placeholder placeholder
                     #:aria-invalid (if error "true" "false")
                     #:on-change (lambda (event) (on-change (event-value event)))
                     #:on-blur (lambda (event) (on-blur))))
     (and error (h/small error)))))
```

([`views/controls.scm`](../examples/checkout/views/controls.scm))

- Pass components data and callbacks; a component tells its parent what happened (`on-change`, `on-view`) and the parent decides what changes.
- Render a list with `map`, and give each item a `#:key`.
- Leave out an optional part with `and` (`(and error (h/small error))`), and choose between two with `if`.
- A helper used by one component can be an internal `define`, such as the `field` helper of [`views/checkout-form.scm`](../examples/checkout/views/checkout-form.scm), which builds each text field of the form with `component` and `apply props`.

## State

Keep state in the smallest component that uses it, and move it up only when another part needs it. The catalog keeps its search and filters to itself; the product being viewed in the quick view lives in the page, because the "recently viewed" list at the bottom of the page opens it too:

```scheme
;; Opens the quick view on a product, or closes it with #f.
(define (view! product)
  (set-viewing! (and product (product-id product)))
  (when product
    (set-recent! (lambda (recent) (remember-viewed recent (product-id product) 5)))))
```

([`main.scm`](../examples/checkout/main.scm))

When the new state depends on the old, pass the setter a procedure of the old state, as `set-recent!` does above and the cart does here:

```scheme
(define (change-quantity! product quantity)
  (set-cart! (lambda (cart) (cart-set cart (product-id product) quantity))))
```

The state is then always the newest, even when several updates happen before React renders again.

## Events and effects

An event handler is a `lambda`. An effect that sets something up returns a procedure that takes it down, and lists what it depends on:

```scheme
(use-effect (lambda ()
              (let ((document (js/ref js/global "document"))
                    (on-key (lambda (event)
                              (let ((key (js/ref event "key")))
                                (cond
                                 ((string=? key "Escape") (on-close))
                                 ((string=? key "ArrowLeft") (on-step -1))
                                 ((string=? key "ArrowRight") (on-step 1)))))))
                (js/method document "addEventListener" "keydown" on-key)
                (lambda () (js/method document "removeEventListener" "keydown" on-key))))
            (list on-close on-step))
```

([`views/quick-view.scm`](../examples/checkout/views/quick-view.scm))

Removing the listener works because a Scheme procedure is always the same JavaScript function. For DOM nodes, take a ref with `use-ref`, pass it as `#:ref`, and use `(js/ref ref "current")` in an effect, as TodoMVC does to focus the field being edited.

## JavaScript libraries

`js/module` returns an npm package, and Roost's Vite plugin imports it for you:

```scheme
(define router-dom (js/module "react-router-dom"))
(define query (js/module "@tanstack/react-query"))
(define Link (js/ref router-dom "Link"))
```

([`router-query/main.scm`](../examples/router-query/main.scm))

- Read with `js/ref`, call methods with `js/method`, construct with `js/new`. Call a global function as a method of `js/global`: `(js/method js/global "setTimeout" thunk 400)`.
- Pass Scheme procedures wherever a library wants a callback.
- Call hooks from libraries as functions, inside components: `((js/ref router-dom "useParams"))`.
- Use JavaScript components with `component`, like Scheme ones: `(component Link (props #:to "/") "Back")`.
- Import a stylesheet for its effect alone: `(js/module "todomvc-app-css/index.css")`.
- At the edge of the application, convert data in one step: `js/from-scheme` before `JSON.stringify`, `js/to-scheme` after `JSON.parse`, as TodoMVC does with localStorage.
- Create a library that manages its own DOM (an editor, a map, a chart) in an effect on a ref, and destroy it in the effect's cleanup.

## Developing in a running page

With `ROOST_REPL=1 pnpm dev` (see [Live development](../README.md#live-development)), the page keeps running while you change it. A good order of work:

1. Look at the data in a REPL: `,m (store products)`, then `(product-by-id 0)`.
2. Write a new function in the REPL, in its module (`,m (store browsing)`), and call it on real data until it is right; then copy it into the file.
3. Find what exists with `,apropos cart` and read it with `,source cart-set`.
4. Try a component on its own: in the panel, a Hiccup result renders with the page's styles, so `(component similar-list (props …))` shows the list before it is part of any page.
5. Save the file. Its definitions are evaluated again in the running page, and components keep their state. Changing a module's header, a record type, or the entry reloads the page.

## Checklist

- Components take props with `let-props` and report events through callbacks.
- Lists are rendered with `map`, each item with a `#:key`.
- State lives in the smallest component that needs it; setters that depend on the old state take a procedure.
- Effects list their dependencies and clean up what they set up.
- JavaScript libraries, their hooks and components are used directly; conversion happens at the application's edge.
- New code is tried in a REPL on real data before it goes into a file.
