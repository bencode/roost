# Setup

## Requirements

| Tool | Version | Used for |
| --- | --- | --- |
| **Node.js** | 24 | Vite, tests |
| **pnpm** | 10 | packages |
| **Guile** | 3.0.11 | runs the Hoot compiler |
| **Hoot** | 0.9.0 | compiles Scheme to WebAssembly |

- `guild` must be on `PATH`, and Hoot's modules on `GUILE_LOAD_PATH`.
- **Live development** needs Hoot built from its `main` branch: its interpreter supports record types, which 0.9.0's does not.

## Install Guile and Hoot

Hoot installs Guile with it:

| System | Command |
| --- | --- |
| **macOS** | `brew tap aconchillo/guile && brew install guile-hoot` |
| **Debian** (testing, unstable) | `apt install guile-hoot` |
| **Guix** | `guix shell guile guile-hoot` |

- Homebrew: run `brew unlink guile` first if Guile is already installed.
- Other systems, or Hoot's `main` branch: [build from source](https://codeberg.org/spritely/hoot#building-from-source).

Check it works:

```sh
guild compile-wasm --help
```

## What the Vite plugin does

[`tooling/vite-plugin-roost.js`](../tooling/vite-plugin-roost.js) only automates steps you can do by hand:

- **Compiles** `.scm` entries with `guild compile-wasm`. The entry's directory is on the load path, so an application's own modules live next to it.
- **Imports** the npm packages named in `(js/module "…")` calls.
- **Serves** Hoot's runtime files, and copies them into builds with Hoot's license.
- **Strips debug information** from built applications, about a fifth of the wasm. Compiled procedures then print as `#<procedure>`, without their names. Development keeps it.
- **Live development**: see [Live development](live-development.md).

## Without the plugin

**1. Compile** the application, and copy Hoot's runtime files next to it:

```sh
guild compile-wasm -L <roost>/modules -L . --bundle -o public/app.wasm main.scm
```

`-L .` lets `main.scm` import the application's own modules, such as `(store cart)` from `store/cart.scm`.

**2. Load** Hoot's `reflect.js` as a classic script, then start the application with the loader:

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

Register every package the Scheme code passes to `js/module` in `modules`.

**3. Optionally, strip** the debug information, as the plugin does for builds:

```sh
hoot strip public/app.wasm
```

It writes the debug information to `public/app.debug.wasm`; do not deploy that file.

**4. License**: the build includes Hoot's runtime (Apache-2.0). Ship Hoot's license with it.
