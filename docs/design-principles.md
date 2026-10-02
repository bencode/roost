# Roost design principles

Status: design phase. This document records agreed directions; the library and example APIs have not been implemented yet.

## Scheme applications and the React runtime

Roost aims to let you write application components, event handlers, and business logic in Scheme, compiled to Wasm with Guile Hoot. The library's JavaScript bridge connects to React, so application authors do not need to write a JavaScript wrapper for each component.

UI is expressed as Hiccup. The construction syntax follows Scheme's expressions, lexical bindings, and function composition, using macros where needed. Quasiquote and unquote are not the default way to write UI. The internal node representation remains undecided.

Props use a distinct type, constructed with `(props #:class "card")`. Types distinguish props from nodes and collections of children. The mapping from property names to React props remains undecided.

Component nodes are constructed explicitly with `(component render ...)`, which stores a reference to the render procedure without calling it. Ordinary Scheme function calls keep their usual behavior. The bridge creates React elements from these nodes, leaving React to decide when to execute each component. Each component is an ordinary Scheme procedure that receives one props value; no component-definition macro is required. [React component calls](https://react.dev/reference/rules/react-calls-components-and-hooks).

## Component props

Components receive one value of the distinct props type. Ordinary helper procedures keep their own argument lists.

```scheme
(define (user-card attributes)
  (let ((name  (props-ref attributes #:name))
        (email (props-ref attributes #:email #f)))
    (h/section
      (props #:class "user-card")
      (h/h2 name)
      (and email (h/p email)))))

(component user-card (props #:name "Ada"))
```

The example illustrates agreed API semantics, not an implemented library. Import `props-ref` from `(roost props)` and `component` from `(roost hiccup)` when using these proposed modules.

- `(props-ref attributes key)` returns the property's value, or raises an error if the key is missing.
- `(props-ref attributes key default)` returns the default only when the key is missing.
- Existing values, including `#f`, are returned unchanged. Object and procedure references are preserved.

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
- One trailing child preserves that value.
- Multiple trailing children form an ordered collection, preserving nested collection boundaries.
- Trailing children override an explicit `#:children` property.

Treat children as opaque content when forwarding them, rather than assuming they are always a list. This follows React's approach to [children](https://react.dev/reference/react/Children).

A dynamic collection such as `(map item-view items)` remains a single collection child. It is not automatically spread into separate arguments or recursively flattened, preserving the boundary needed for React's dynamic-list key checks. [createElement](https://react.dev/reference/react/createElement).

The Wasm boundary representation and conversion to React nodes are still being designed. In particular, the adapter must preserve the distinction between static trailing children and dynamic collections when forwarding them through components.

## Native React Hooks

React owns state, update scheduling, rendering, effects, and cleanup. Roost does not introduce ratoms, reactions, automatic dependency tracking, or a separate update queue.

The bridge must follow React's Rules of Hooks, preserve state update semantics, and retain React's per-item `Object.is` comparison for dependencies. Rewrapping the same Scheme value must not cause spurious dependency changes. [Rules of Hooks](https://react.dev/reference/rules/rules-of-hooks), [useEffect](https://react.dev/reference/react/useEffect).

## Module imports and names

The DOM module exports ordinary tag names. Documentation uses `#:prefix h/` by default; applications can explicitly import short names with `#:select`. Tags are not injected into application scope automatically, and Roost does not add its own import syntax. [Guile module imports](https://www.gnu.org/software/guile/manual/html_node/Using-Guile-Modules.html).

The following examples illustrate the proposed import style. The modules and tag constructors have not been implemented yet.

```scheme
(use-modules ((roost dom) #:prefix h/)
             ((roost props) #:select (props)))

(h/section
  (props #:class "card")
  (h/h2 title)
  (h/p "Hello"))
```

A calling module may instead select short names:

```scheme
(use-modules ((roost dom) #:select (section h2 p)))

(section (h2 title) (p "Hello"))
```

Callers choose the prefix. `h/section` is an imported Scheme identifier; the concrete node construction API is still being designed.
