# Contributing

## Setup

See [Setup](docs/setup.md), then:

```sh
pnpm install
pnpm dev      # examples at http://localhost:5173
pnpm build    # examples into dist/
pnpm test     # Guile and Vitest suites
```

| Script | Runs |
| --- | --- |
| `pnpm test:scheme` | Scheme tests under Guile, with host stand-ins from `tests/host/` |
| `pnpm test:js` | Vitest: the React adapter, the Scheme reader, the REPL relay |

## Repository layout

| Path | Contents |
| --- | --- |
| `modules/roost/` | The Scheme library: `props`, `hiccup`, `dom`, `react`, `hooks`, `js`; `dev` and `devtools/` for live development |
| `js/` | The JavaScript kernel, the React builder, the loader |
| `tooling/` | The Vite plugin; live development (`live-dev.js`), its REPL relay, the `pnpm repl` client |
| `examples/` | Example applications |
| `tests/` | Guile and Vitest tests |
| `docs/` | Guides and [design principles](docs/design-principles.md) |

## Conventions

- Code, comments, docs, commits: **English**.
- Read the [design principles](docs/design-principles.md) before changing the library.

## License

Contributions are licensed under [Apache-2.0](LICENSE).
