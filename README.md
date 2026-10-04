# Roost

**Write React apps in Scheme.**

Roost compiles Scheme to WebAssembly with [Hoot](https://spritely.institute/hoot/), and uses React as it is.

**[Playground](https://bencode.github.io/roost/playground/)** · [Live demos](https://bencode.github.io/roost/) · [Docs](#docs)

- **React as is**: components, Hooks, React 19, any npm library
- **Scheme all the way**: Hiccup markup, records, modules
- **Live development**: save a file, the page updates, **state is kept**; a REPL into the running page, from the terminal
- **Small**: the complete TodoMVC is about **330 KB gzipped**, React included

> **Status**: a working prototype. Not on npm yet; the API may change.

## A component

```scheme
(import (scheme base)
        (prefix (roost dom) h/)
        (only (roost props) props let-props)
        (only (roost hiccup) component)
        (only (roost react) render-root)
        (only (roost hooks) use-state))

(define (counter attributes)
  (let-props attributes ((start 0))
    (let-values (((count set-count!) (use-state start)))
      (h/section
       (h/output count)
       (h/button (props #:on-click (lambda (event) (set-count! (lambda (n) (+ n 1)))))
                 "+1")))))

(render-root (component counter (props #:start 0)) "root")
```

The page loads the Scheme file directly:

```html
<div id="root"></div>
<script type="module" src="./main.scm"></script>
```

## Quick start

You need **Node.js 24**, **pnpm 10**, and **Hoot** ([install](docs/setup.md#install-guile-and-hoot): one command on macOS, Debian, Guix).

```sh
pnpm install
pnpm dev                  # examples at http://localhost:5173
ROOST_REPL=1 pnpm dev     # the same, with live development
```

Live development needs Hoot's `main` branch for now ([why](docs/setup.md#requirements)).

## Examples

| Example | Shows | |
| --- | --- | --- |
| [Playground](examples/playground/main.scm) | Write a module, run it, try it in a REPL: in the browser, nothing to install | [Live](https://bencode.github.io/roost/playground/) |
| [Counter](examples/counter/main.scm) | State, effects, events | [Live](https://bencode.github.io/roost/counter/) |
| [TodoMVC](examples/todomvc/main.scm) | The complete [TodoMVC](https://todomvc.com): editing, routes, persistence | [Live](https://bencode.github.io/roost/todomvc/) |
| [Router + Query](examples/router-query/main.scm) | React Router and TanStack Query from Scheme | [Live](https://bencode.github.io/roost/router-query/) |
| [Checkout](examples/checkout/main.scm) | A store in modules: 200-product catalog, cart, coupon, checkout form, quick view | [Live](https://bencode.github.io/roost/checkout/) |

## Docs

- [Using Roost](docs/using-roost.md): components, state, effects, JavaScript libraries
- [Live development](docs/live-development.md): reload on save, the REPL, commands
- [Setup](docs/setup.md): requirements, installing Hoot, using Roost without Vite
- [Design principles](docs/design-principles.md): how Roost works, and why
- [Contributing](CONTRIBUTING.md)

## License

[Apache-2.0](LICENSE). Built applications include Hoot's runtime, also Apache-2.0; builds ship its license in `hoot/LICENSE`.
