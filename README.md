# Roost

Scheme-first React bindings powered by Guile Hoot.

Roost lets you write React applications in Scheme and compile them to WebAssembly with [Hoot](https://spritely.institute/hoot/). Components, Hooks, event handlers, and business logic are Scheme; React and existing JavaScript libraries are used directly from Scheme. The library itself is written in Scheme on top of a small, stable JavaScript kernel.

Roost is a working prototype. The examples run, but the library is not packaged for installation yet and its API may still change.

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

## Requirements

- [Guile](https://www.gnu.org/software/guile/) 3.0.11 and [Hoot](https://spritely.institute/hoot/) 0.9.0, with `guild` on `PATH` and Hoot's modules on `GUILE_LOAD_PATH`. [Live development](#live-development) needs Hoot built from its `main` branch, whose interpreter supports record types
- Node.js 24 and pnpm 10

## Getting started

```sh
pnpm install
pnpm dev      # serve the examples at http://localhost:5173
pnpm build    # build the examples into dist/
pnpm test     # Guile and Vitest test suites
```

The first visit to an example compiles its Scheme to WebAssembly, which takes a few seconds. Saving a `.scm` file recompiles it and reloads the page.

## Examples

| Example | Shows |
| --- | --- |
| [`examples/counter`](examples/counter/main.scm) | `use-state`, `use-effect`, DOM events |
| [`examples/router-query`](examples/router-query/main.scm) | React Router and TanStack Query used from Scheme |
| [`examples/todomvc`](examples/todomvc/main.scm) | The complete [TodoMVC](https://todomvc.com) application: editing, filtering with routes, persistence |
| [`examples/checkout`](examples/checkout/main.scm) | A store page split into libraries (`store/` for data and logic, `views/` for components): a 200-product catalog, cart, coupon, validated checkout form, simulated server calls |

Each example is an `index.html` and a `main.scm`. The page loads the Scheme entry directly:

```html
<div id="root"></div>
<script type="module" src="./main.scm"></script>
```

## How the Vite plugin helps

[`tooling/vite-plugin-roost.js`](tooling/vite-plugin-roost.js) compiles `.scm` entries with `guild compile-wasm` (the entry's directory is on the load path, so an application's own libraries live next to it), finds the npm packages named in `(js/module "…")` calls and imports them, and serves Hoot's runtime files. It only automates steps you can do by hand.

## Live development

Scheme is at its best when the program keeps running while you change it. Start the examples in live mode and open a page:

```sh
ROOST_REPL=1 pnpm dev
```

The page runs a development shell: Roost compiled once with Hoot's run-time module system and interpreter (the first visit takes about 20 seconds). The application's own modules are not compiled; the page loads them from source. Saving a file then works like this:

| Saved file | What happens |
| --- | --- |
| A module of the application | Its definitions are evaluated again in the running page and every root renders again. Nothing is compiled and the page does not reload. Components keep their state, even when their own definition changed |
| The module's header (`define-module`) or a `define-record-type` in it, or the entry `main.scm` | The page reloads and loads the modules from source again |
| A Roost library | The shell is compiled again and the page reloads |

A REPL connects to the page that opened last:

```sh
pnpm repl                                   # interactive session; ,module (store cart) switches modules
pnpm repl ',module (store cart)' '(cart-count (list (cons 1 2)))'   # each argument is a line; prints, then exits
```

With arguments, `pnpm repl` exits with status 1 when an evaluation raises an error, so scripts and coding agents can use it. Editors that speak Hoot's REPL protocol over TCP, such as Emacs with Geiser, can connect to port 37146.

Limits:

- A change to the number or order of a component's hooks makes React report an error; reload the page.
- The interpreter cannot `set!` a module's top-level variable; keep mutable state in a container such as a vector or a box.
- Hoot's interpreter accepts only two arguments for `<`, `<=`, `=`, `>=` and `>`; compiled code accepts more.
- Modules that use `define-foreign` or inline Wasm must be compiled, so they cannot be loaded from source.
- Interpreted code runs about three times slower than compiled code. Live mode is for development only; `pnpm build` is unaffected.

## Using Roost without the plugin

Compile the application and copy Hoot's runtime files next to it:

```sh
guild compile-wasm -L <roost>/modules -L . --bundle -o public/app.wasm main.scm
```

`-L .` lets `main.scm` import the application's own libraries, such as `(store cart)` from `store/cart.scm`.

Load Hoot's `reflect.js` as a classic script, then start the application with the loader, registering every package the Scheme code passes to `js/module`:

```html
<div id="root"></div>
<script src="/reflect.js"></script>
<script type="module" src="/main.js"></script>
```

```js
import * as React from 'react'
import * as ReactDOMClient from 'react-dom/client'
import { boot } from '<roost>/js/roost-loader.js'

boot({
  Scheme, // defined by reflect.js
  wasm: '/app.wasm',
  reflectWasmDir: '',
  modules: { react: React, 'react-dom/client': ReactDOMClient },
})
```

## Repository layout

| Path | Contents |
| --- | --- |
| `modules/roost/` | The Scheme library: `props`, `hiccup`, `dom`, `react`, `hooks`, `js`, and `dev` for live development |
| `js/` | The JavaScript kernel, the React builder, and the loader |
| `tooling/` | The Vite plugin; live development (`live-dev.js`), its REPL relay, and the `pnpm repl` client |
| `examples/` | Example applications |
| `tests/` | Guile and Vitest tests |

See the [design principles](docs/design-principles.md) for how Roost works and why.
