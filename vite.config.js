import { existsSync, readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import roost from './tooling/vite-plugin-roost.js'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'examples')

// Every examples/<name>/index.html is a page, plus the example list. examples/public
// holds static files, served and copied as they are.
const pages = Object.fromEntries([
  ['index', path.join(root, 'index.html')],
  ...readdirSync(root, { withFileTypes: true })
    .filter(entry => entry.isDirectory() && existsSync(path.join(root, entry.name, 'index.html')))
    .map(entry => [entry.name, path.join(root, entry.name, 'index.html')]),
])

export default defineConfig({
  root,
  // ROOST_REPL=1 pnpm dev: live development with a REPL (see README).
  plugins: [
    roost({
      repl: process.env.ROOST_REPL === '1',
      // The playground evaluates Scheme in the page.
      runtimeModules: ['playground/main.scm'],
    }),
  ],
  build: {
    outDir: path.join(root, '..', 'dist'),
    emptyOutDir: true,
    rollupOptions: { input: pages },
  },
  test: {
    root: path.join(root, '..'),
    include: ['tests/**/*.test.js'],
  },
})
