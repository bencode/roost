# Roost design principles

Status: design phase. This document records agreed directions; the library and example APIs have not been implemented yet.

## Scheme applications and the React runtime

Roost aims to let you write application components, event handlers, and business logic in Scheme, compiled to Wasm with Guile Hoot. The library's JavaScript bridge connects to React, so application authors do not need to write a JavaScript wrapper for each component.

UI is expressed as Hiccup. The construction syntax follows Scheme's expressions, lexical bindings, and function composition, using macros where needed. Quasiquote and unquote are not the default way to write UI. The internal node representation and component argument model remain undecided.

Props use a distinct type, constructed with `(props #:class "card")`. Types distinguish props from nodes and collections of children. The mapping from property names to React props remains undecided.

Component nodes are constructed explicitly with `(component render ...)`, which stores a reference to the render procedure without calling it. Ordinary Scheme function calls keep their usual behavior. The bridge creates React elements from these nodes, leaving React to decide when to execute each component. The component argument model remains undecided. [React component calls](https://react.dev/reference/rules/react-calls-components-and-hooks).

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
