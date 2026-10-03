// Development and build tooling. It only automates what can be done by hand:
// `guild compile-wasm`, registering the npm packages used by js/module, and serving
// Hoot's runtime files. Nothing here is needed at run time.
import { execFile } from 'node:child_process'
import { mkdir, readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'
import { createLiveDev } from './live-dev.js'

const run = promisify(execFile)
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const loaderPath = path.join(repoRoot, 'js', 'roost-loader.js')
const runtimeFiles = ['reflect.wasm', 'wtf8.wasm']
const developmentOnly = /[\\/]roost[\\/](dev\.scm$|devtools)/
const hootUrl = '/@hoot/'
const reflectId = '\0hoot:reflect'

// Ask the installed Hoot where its runtime lives, so it always matches the compiler.
export const hootPaths = async () => {
  const { stdout } = await run('guile', [
    '-c',
    '(use-modules (hoot config)) (display %reflect-js-dir) (newline) (display %reflect-wasm-dir)',
  ])
  const [reflectJsDir, reflectWasmDir] = stdout.trim().split('\n')
  return { reflectJs: path.join(reflectJsDir, 'reflect.js'), reflectWasmDir }
}

export const compileScheme = async ({ entry, output, loadPaths = [], optimize, features = [] }) => {
  await mkdir(path.dirname(output), { recursive: true })
  const args = [
    'compile-wasm',
    ...loadPaths.flatMap(dir => ['-L', dir]),
    ...(optimize === undefined ? [] : [`-O${optimize}`]),
    ...features.map(feature => `-f${feature}`),
    '-o',
    output,
    entry,
  ]
  try {
    await run('guild', args, { maxBuffer: 16 * 1024 * 1024 })
  } catch (error) {
    throw new Error(`guild compile-wasm failed for ${entry}\n${error.stderr || error.message}`)
  }
}

const schemeFiles = async dir => {
  const entries = await readdir(dir, { withFileTypes: true, recursive: true })
  return entries
    .filter(entry => entry.isFile() && entry.name.endsWith('.scm'))
    .map(entry => path.join(entry.parentPath, entry.name))
}

// Package names given literally to js/module (under any import prefix).
const modulePattern = /\(\s*[^\s()"]*module\s+"([^"]+)"/g

export const scanModules = async files => {
  const sources = await Promise.all(files.map(file => readFile(file, 'utf8')))
  return [...new Set(sources.flatMap(source => [...source.matchAll(modulePattern)].map(match => match[1])))]
    .filter(name => name !== 'global')
    .sort()
}

// then: JavaScript source of a function given boot's results, if any.
const entryCode = ({ wasmFile, reflectWasmDir, modules, then }) =>
  [
    `import { Scheme, repr } from 'hoot:reflect'`,
    `import { boot } from ${JSON.stringify(loaderPath)}`,
    `import wasm from ${JSON.stringify(`${wasmFile}?url`)}`,
    ...modules.map((name, i) => `import * as m${i} from ${JSON.stringify(name)}`),
    `boot({`,
    `  Scheme,`,
    `  wasm,`,
    `  reflectWasmDir: ${JSON.stringify(reflectWasmDir)},`,
    `  modules: { ${modules.map((name, i) => `${JSON.stringify(name)}: m${i}`).join(', ')} },`,
    then ? `}).then(${then})` : `})`,
  ].join('\n')

export default function roost({ loadPaths = [path.join(repoRoot, 'modules')], repl = false } = {}) {
  let config
  let hoot
  // Live development (ROOST_REPL=1), only while serving.
  let live = null

  return {
    name: 'roost',
    enforce: 'pre',

    async configResolved(resolved) {
      config = resolved
      hoot = await hootPaths()
      if (repl && config.command === 'serve') {
        live = createLiveDev({
          config,
          loadPaths,
          reflectWasmDir: hootUrl.slice(0, -1),
          build: { compileScheme, schemeFiles, scanModules, entryCode },
        })
      }
    },

    // reflect.js is a classic script that only exports through a CommonJS `exports`
    // object; re-export its top-level declarations as an ES module.
    resolveId(id) {
      if (id === 'hoot:reflect') return reflectId
    },

    // An entry script `<script type="module" src="./main.scm">` becomes an import, so
    // Vite treats the .scm file as a module in development as well.
    transformIndexHtml(html) {
      return html.replace(
        /<script\s+type="module"\s+src="([^"]+\.scm)"\s*><\/script>/g,
        (_, src) => `<script type="module">import ${JSON.stringify(src)}</script>`,
      )
    },

    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const name = req.url?.startsWith(hootUrl) && req.url.slice(hootUrl.length)
        if (!runtimeFiles.includes(name)) return next()
        res.setHeader('Content-Type', 'application/wasm')
        res.end(await readFile(path.join(hoot.reflectWasmDir, name)))
      })
      server.watcher.add(loadPaths)
      const recompile = () => {
        for (const module of server.moduleGraph.idToModuleMap.values()) {
          if (module.file?.endsWith('.scm')) server.moduleGraph.invalidateModule(module)
        }
        server.ws.send({ type: 'full-reload' })
      }
      live?.attach(server)
      server.watcher.on('change', async file => {
        if (!file.endsWith('.scm')) return
        if (!(await live?.change(file, server, recompile))) recompile()
      })
    },

    async load(id) {
      if (id === reflectId) {
        // Modules are strict: declare the loop variable reflect.js leaves undeclared,
        // which otherwise throws while Hoot prints a backtrace.
        const source = (await readFile(hoot.reflectJs, 'utf8')).replace('for (attr in map)', 'for (const attr in map)')
        return `${source}\nexport { Scheme, SchemeQuitError, repr }\n`
      }
      const entry = id.split('?')[0]
      if (!entry.endsWith('.scm')) return
      if (live) return live.load(entry, file => this.addWatchFile(file))
      const serving = config.command === 'serve'
      const outDir = path.join(config.cacheDir, 'roost')
      const wasmFile = path.join(outDir, `${path.relative(config.root, entry).replaceAll(path.sep, '_')}.wasm`)
      // The entry's directory holds the application's own libraries.
      await compileScheme({ entry, output: wasmFile, loadPaths: [path.dirname(entry), ...loadPaths], optimize: serving ? 1 : undefined })

      const files = [...(await schemeFiles(path.dirname(entry))), ...(await Promise.all(loadPaths.map(schemeFiles))).flat()]
      files.forEach(file => this.addWatchFile(file))
      // Roost's live development modules only run in the development shell; the npm
      // packages they use (CodeMirror) stay out of applications.
      const modules = await scanModules(files.filter(file => !developmentOnly.test(file)))
      const reflectWasmDir = serving ? hootUrl.slice(0, -1) : `${config.base}hoot`.replace(/\/$/, '')
      return entryCode({ wasmFile, reflectWasmDir, modules })
    },

    // Vite calls buildEnd when the development server closes or restarts.
    buildEnd() {
      live?.close()
    },

    // Saved application modules are handled by the watcher above, not by Vite's HMR.
    handleHotUpdate({ file }) {
      if (live && file.endsWith('.scm')) return []
    },

    async generateBundle() {
      for (const name of runtimeFiles) {
        this.emitFile({
          type: 'asset',
          fileName: `hoot/${name}`,
          source: await readFile(path.join(hoot.reflectWasmDir, name)),
        })
      }
    },
  }
}
