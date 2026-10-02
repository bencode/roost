# Roost

Scheme-first React bindings powered by Guile Hoot.

Roost is a library in the design phase. Its goal is to let you write React applications in Scheme, compile them to WebAssembly with Hoot, and connect them to React through the library's JavaScript bridge.

The design uses Hiccup to express UI and native React Hooks to manage state and effects, while preserving Scheme expressions, lexical scope, and module imports.

There is no installable Roost library yet, and the API is still being designed. See the [design principles](docs/design-principles.md) for the agreed direction.
