# Roost

Scheme-first React bindings powered by Guile Hoot.

Roost is a library in the design phase. Its goal is to let you write complete React applications in Scheme and compile them to WebAssembly with Hoot. The library itself is written in Scheme on top of a small, stable JavaScript kernel, and existing JavaScript libraries remain usable from Scheme.

The design uses Hiccup to express UI and native React Hooks to manage state and effects, while preserving Scheme expressions, lexical scope, and module imports.

There is no installable Roost library yet, and the API is still being designed. See the [design principles](docs/design-principles.md) for the agreed direction.
