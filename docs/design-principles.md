# Roost design principles

Status: working prototype. This document records the agreed design; the library implements it and the [examples](../examples) exercise it. Details may still change, and Roost is not packaged for installation yet.

## Scheme applications and the React runtime

Roost aims to let you write complete web applications in Scheme, compiled to Wasm with Guile Hoot. Components, Hooks, event handlers, and business logic are all Scheme. Mature JavaScript libraries such as React Router, TanStack Query, or Ramda remain ordinary dependencies, called from Scheme.

The library itself is written in Scheme as well. Its JavaScript side is a small, generic kernel that supplies only what Hoot does not provide: reading modules and properties, calling functions and constructors, turning Scheme procedures into JavaScript functions, and converting primitive values. The kernel knows nothing about React. Once it is complete, it should stay stable: adding a Hook, using a browser API, or integrating a JavaScript library should require only Scheme code, not new bridge functions.

Roost does not hide React. Scheme names map one-to-one to React APIs (`use-state` is `useState`), and React's semantics, rules, and documentation apply unchanged.

UI is expressed as Hiccup. The construction syntax follows Scheme's expressions, lexical bindings, and function composition, using macros where needed. Quasiquote and unquote are not the default way to write UI.

Props use a distinct type, constructed with `(props #:class "card")`. Types distinguish props from nodes and collections of children.

Component nodes are constructed explicitly with `(component render ...)`, which stores a reference to the render procedure without calling it. Ordinary Scheme function calls keep their usual behavior. The library creates React elements from these nodes, leaving React to decide when to execute each component. Each component is an ordinary Scheme procedure that receives one props value; no component-definition macro is required. [React component calls](https://react.dev/reference/rules/react-calls-components-and-hooks).

## Component identity

React identifies a component by its type, compared with `Object.is`. Roost maps each render procedure to exactly one React type, keyed by the procedure's identity (`eq?`):

- The same procedure always produces the same React type, so re-rendering a parent preserves the child's state.
- Different procedures produce different types.
- A procedure created anew during render, such as a fresh `lambda`, is a new type, just as defining a component inside another component is in React.

The mapping is kept by the library, not attached to the procedure, so a plain `define` is all a component needs.

## Component props

Components receive one value of the distinct props type. Ordinary helper procedures keep their own argument lists.

```scheme
(define (user-card attributes)
  (let-props attributes (name (email #f))
    (h/section
      (props #:class "user-card")
      (h/h2 name)
      (and email (h/p email)))))

(component user-card (props #:name "Ada"))
```

`props`, `props-ref`, and `let-props` come from `(roost props)`; `component` comes from `(roost hiccup)`.

`let-props` binds each name to the property with the same keyword, optionally with a default. It is shorthand for `props-ref`:

- `(props-ref attributes key)` returns the property's value, or raises an error if the key is missing.
- `(props-ref attributes key default)` returns the default only when the key is missing.
- Existing values, including `#f`, are returned unchanged. Object and procedure references are preserved.
- `#:key` is passed to React as the element key and is not visible to the component, as in React.

## DOM properties

`(roost dom)` provides every HTML element except `html`, `head`, and `body`.

Property names on DOM nodes follow Reagent's conventions:

| Roost | React |
| --- | --- |
| `#:class` | `className` |
| `#:for` | `htmlFor` |
| `#:on-click`, `#:tab-index` | `onClick`, `tabIndex` (kebab-case to camelCase) |
| `#:aria-label`, `#:data-id` | `aria-label`, `data-id` (unchanged) |

`#:style` takes a nested props value. Its names are converted from kebab-case to camelCase, and custom properties starting with `--` are kept unchanged:

```scheme
(h/div (props #:style (props #:margin-top 8 #:--accent "blue")))
;; style: { marginTop: 8, "--accent": "blue" }
```

JavaScript components, such as React Router's `Link`, receive props under the same names, including `#:style`, following React's convention that components accept `className`, `htmlFor`, `aria-*`, and `data-*`. Components written in Scheme read their props by keyword and see no name conversion.

## Children

Trailing children become the component's `#:children` property. A container component reads that property with `props-ref` and forwards the value unchanged:

```scheme
(define (card attributes)
  (h/section
    (props #:class "card")
    (props-ref attributes #:children #f)))

(component card
  (props)
  (h/h2 "Title")
  (h/p "Body"))
```

- With no trailing children, an explicit `#:children` property is preserved. If it was absent, it remains absent.
- One trailing child preserves that value, including a procedure used as a render prop.
- Multiple trailing children form an ordered collection, preserving nested collection boundaries.
- Trailing children override an explicit `#:children` property.

Treat children as opaque content when forwarding them, rather than assuming they are always a list. This follows React's approach to [children](https://react.dev/reference/react/Children).

A dynamic collection such as `(map item-view items)` remains a single collection child. It is not automatically spread into separate arguments or recursively flattened. It becomes a JavaScript array, so React checks keys as it would for a dynamic list. [createElement](https://react.dev/reference/react/createElement).

Static children keep their static nature when a component forwards them. Multiple trailing children are forwarded through a Fragment rather than an array, so React does not ask for keys on them.

## Native React Hooks

React owns state, update scheduling, rendering, effects, and cleanup. Roost does not introduce ratoms, reactions, automatic dependency tracking, or a separate update queue.

React Hooks are ordinary functions that React associates with the current component by call order. Roost's Hooks are likewise ordinary Scheme procedures that call the React function of the same name during render. Each is a thin layer that only converts values at the boundary:

```scheme
(let-values (((count set-count!) (use-state 0)))
  (use-effect
    (lambda ()
      (subscribe!)
      (lambda () (unsubscribe!)))   ; a returned procedure is the cleanup
    (list set-count!))
  ...)

(set-count! (lambda (n) (+ n 1)))   ; a procedure is an updater, as in React
```

`(roost hooks)` provides `use-state`, `use-effect`, and `use-ref`. `use-ref` returns the React ref object: pass it as `#:ref` to a DOM node, or read and write its `current` with `js/ref` and `js/set!`. Other React Hooks, and Hooks from JavaScript libraries, can be called directly through `(roost js)`; Roost adds named Hooks when applications need them, and adding one does not require new mechanisms.

The bridge follows React's Rules of Hooks, preserves state update semantics, and retains React's per-item `Object.is` comparison for dependencies. Functions that React keeps stable, such as state setters, are also stable in Scheme: the same JavaScript function always maps to the same Scheme procedure. [Rules of Hooks](https://react.dev/reference/rules/rules-of-hooks), [useEffect](https://react.dev/reference/react/useEffect).

## JavaScript interop

The `(roost js)` module gives Scheme code access to JavaScript. Documentation imports it with the prefix `js/`:

```scheme
(import (prefix (roost js) js/))

(define R (js/module "ramda"))

((js/ref R "map") (lambda (x) (* x 10)) (js/from-scheme '(1 2 3)))
(js/ref event "target" "value")
(js/method (js/ref js/global "Promise") "resolve" 41)
(js/new (js/ref js/global "URL") "https://example.org")
(or (js/ref query "data") "loading")
```

Values cross the boundary in two ways:

- **Shallow conversion** applies to every call. Numbers, strings, and booleans convert to their counterparts. JavaScript `null` and `undefined` become `#f`. JavaScript functions become Scheme procedures that can be called directly, and Scheme procedures become JavaScript functions. Other Scheme values, such as lists and records, pass through unchanged and come back as the same object, so a JavaScript library can store Scheme data. Other JavaScript objects stay opaque on the Scheme side.
- **Deep conversion** is explicit. `js/from-scheme` turns Scheme data into plain JavaScript data: lists become arrays, and props become objects with camelCase keys. `js/to-scheme` converts in the opposite direction. Use it where a library inspects data, such as a query key or a route configuration.

JavaScript components, such as React Router's `Link`, can be used directly as node types. Errors thrown by JavaScript become Scheme conditions, so `guard` and `dynamic-wind` behave as usual.

A Scheme procedure called from JavaScript receives the call's arguments without trailing `undefined` values, since JavaScript often passes more arguments than a callback uses. Some libraries, such as Ramda's `curry`, read a function's `length`; declare it with `(js/function procedure length)`, which also passes at most that many arguments.

Stylesheets from npm packages are imported for their side effect with `(js/module "todomvc-app-css/index.css")`; the Vite plugin bundles them. Without the plugin, link the stylesheet from the page instead.

## Module imports and names

Roost's modules are R7RS libraries, imported with `import` as Hoot programs do. The DOM module exports ordinary tag names. Documentation imports it with the prefix `h/`; applications can instead import short names with `only`. Tags are not injected into application scope automatically, and Roost does not add its own import syntax. [R7RS libraries](https://small.r7rs.org/attachment/r7rs.pdf).

```scheme
(import (scheme base)
        (prefix (roost dom) h/)
        (only (roost props) props))

(h/section
  (props #:class "card")
  (h/h2 title)
  (h/p "Hello"))
```

A calling module may instead select short names:

```scheme
(import (only (roost dom) section h2 p))

(section (h2 title) (p "Hello"))
```

Callers choose the prefix. `h/section` is an imported Scheme identifier.
