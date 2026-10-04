# Live development

Change the program **while it runs**. Save a file: the page updates, and **components keep their state**.

```sh
ROOST_REPL=1 pnpm dev
```

- Needs Hoot built from its `main` branch (see [Setup](setup.md)).
- The first visit takes about 20 seconds: Roost is compiled once into a **development shell** with Hoot's interpreter.
- The application's own modules are **not compiled**: the page loads them from source.

## Saving a file

| Saved file | What happens |
| --- | --- |
| A module of the application | Evaluated again in the page; roots render again. **No compile, no reload, state kept** |
| Its header (`define-module`), a `define-record-type`, or the entry `main.scm` | The page reloads |
| A Roost library | The shell is compiled again; the page reloads |

## The REPL panel

Open it with the **λ button** at the bottom right, or **Ctrl+\`**.

- **Any module**: `,m (store cart)` enters a module; call and redefine its private definitions.
- **Errors**: open a debug level. `,bt` shows the backtrace, `,q` leaves.
- **Hiccup results render** below the output, with the page's styles: build a component piece by piece.
- **Editor**: [CodeMirror](https://codemirror.net), driven from Scheme. Highlighting, bracket matching, completion of visible names.
- **Keys**: Mod+Enter runs; Mod+↑ / Mod+↓ walk the history.
- Floats over the page; keeps its place, size, and history across reloads.
- DOM only, no React. Builds leave it out.

## Commands

Hoot's own: `,m`, `,use`, `,d`, `,q`, `,help`. Roost adds:

| Command | Shows |
| --- | --- |
| `,names [PREFIX]` | Names the current module sees |
| `,apropos TEXT` | The application's definitions whose names contain TEXT, with their modules |
| `,source NAME` | The source of NAME's definition, with the comments above it |
| `,bt` / `,bt all` | The backtrace after an error, without the REPL's own frames; `all` keeps them |

## From the terminal

The same REPL, connected to the page that opened last:

```sh
pnpm repl                                                         # interactive
pnpm repl ',module (store cart)' '(cart-count (list (cons 1 2)))'   # one line per argument; prints, then exits
```

- With arguments, **exits with status 1** when an evaluation raises an error: usable from scripts and coding agents.
- Plain text on port **37146**: `nc localhost 37146` works too.

## Limits

- Changing **the number or order of a component's hooks**: React reports an error. Reload the page.
- **`set!` on a module's top-level variable** fails in the interpreter. Keep mutable state in a vector or a box.
- Hoot's interpreter takes **only two arguments** for `<`, `<=`, `=`, `>=`, `>`, `-`, `/`: `(- x)` and `(<= 1 x 9)` fail in live mode. Compiled code accepts them.
- Modules using `define-foreign` or inline Wasm must be compiled: they cannot load from source.
- Interpreted code runs about **3× slower**. Live mode is for development only; `pnpm build` is unaffected.
