// Development and build tooling. It only automates what can be done by hand:
// `guild compile-wasm`, registering the npm packages used by js/module, and serving
// Hoot's runtime files. Nothing here is needed at run time.
import { execFile } from 'node:child_process'
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'
import { createRelay, replBase } from './repl-relay.js'
import { importedLibraries, moduleHeader, moduleStructure, programAsLibrary } from './scheme-source.js'

const run = promisify(execFile)
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const loaderPath = path.join(repoRoot, 'js', 'roost-loader.js')
const runtimeFiles = ['reflect.wasm', 'wtf8.wasm']
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

const entryCode = ({ wasmFile, reflectWasmDir, modules }) =>
  [
    `import { Scheme } from 'hoot:reflect'`,
    `import { boot } from ${JSON.stringify(loaderPath)}`,
    `import wasm from ${JSON.stringify(`${wasmFile}?url`)}`,
    ...modules.map((name, i) => `import * as m${i} from ${JSON.stringify(name)}`),
    `boot({`,
    `  Scheme,`,
    `  wasm,`,
    `  reflectWasmDir: ${JSON.stringify(reflectWasmDir)},`,
    `  modules: { ${modules.map((name, i) => `${JSON.stringify(name)}: m${i}`).join(', ')} },`,
    `})`,
  ].join('\n')

// Live development: the page runs a development shell (Roost compiled with Hoot's
// run-time module system) that loads the application's modules from source, starts a
// REPL, and evaluates saved modules again when the server sends roost:reload.
const roostLibraries = ['(roost js)', '(roost props)', '(roost hiccup)', '(roost dom)', '(roost hooks)', '(roost react)']
const mainModule = '(roost-dev main)'
const mainPath = 'roost-dev/main'

const shellProgram = ({ base, libraries }) =>
  [
    '(import (scheme base)',
    '        (roost dev)',
    ...libraries.map((library, i) => `        (prefix ${library} %shell-${i}:)`),
    '        )',
    `(dev-program ${JSON.stringify(base)} '${mainModule})`,
  ].join('\n')

const replEntryCode = ({ wasmFile, reflectWasmDir, modules, key }) =>
  [
    `import { Scheme, repr } from 'hoot:reflect'`,
    `import { boot } from ${JSON.stringify(loaderPath)}`,
    `import wasm from ${JSON.stringify(`${wasmFile}?url`)}`,
    ...modules.map((name, i) => `import * as m${i} from ${JSON.stringify(name)}`),
    `const show = error => (error instanceof Error ? error : repr(error))`,
    `const [start, reload] = await boot({`,
    `  Scheme,`,
    `  wasm,`,
    `  reflectWasmDir: ${JSON.stringify(reflectWasmDir)},`,
    `  modules: { ${modules.map((name, i) => `${JSON.stringify(name)}: m${i}`).join(', ')} },`,
    `})`,
    `start.call_async().catch(error => console.error('roost dev:', show(error)))`,
    `import.meta.hot?.on('roost:reload', ({ key, source }) => {`,
    `  if (key !== ${JSON.stringify(key)}) return`,
    `  try {`,
    `    reload.call(source)`,
    `  } catch (error) {`,
    `    console.error('roost reload:', show(error))`,
    `  }`,
    `})`,
  ].join('\n')

export default function roost({ loadPaths = [path.join(repoRoot, 'modules')], repl = false } = {}) {
  let config
  let hoot
  // Live development state per page entry key: { entry, dir, known, structures }.
  // known: library names the page can import (compiled into its shell or its own modules).
  const pages = new Map()
  let relay = null
  const live = () => repl && config.command === 'serve'

  const pageSource = async (key, modulePath) => {
    const page = pages.get(key)
    if (!page || modulePath.split('/').includes('..')) return null
    if (modulePath === mainPath) return programAsLibrary(await readFile(page.entry, 'utf8'), mainModule)
    try {
      return await readFile(path.join(page.dir, `${modulePath}.scm`), 'utf8')
    } catch (error) {
      if (error.code === 'ENOENT') return null
      throw error
    }
  }

  // The shell holds Roost and every other library the application imports; the
  // application's own modules stay out of it, so the page can load them from source.
  async function loadDevShell(entry) {
    const dir = path.dirname(entry)
    const key = path.relative(config.root, entry)
    const appFiles = await schemeFiles(dir)
    const sources = await Promise.all(appFiles.map(file => readFile(file, 'utf8')))
    const appModules = new Set(sources.map(source => moduleHeader(source)?.name).filter(Boolean))
    const libraries = [
      ...new Set([...roostLibraries, ...sources.flatMap(importedLibraries)]),
    ].filter(library => !appModules.has(library) && library !== '(scheme base)')
    pages.set(key, {
      entry,
      dir,
      known: new Set(['(scheme base)', ...libraries, ...appModules]),
      structures: new Map(appFiles.map((file, i) => [file, moduleStructure(sources[i])])),
    })

    const outDir = path.join(config.cacheDir, 'roost')
    const name = key.replaceAll(path.sep, '_')
    const shellFile = path.join(outDir, `${name}.shell.scm`)
    const wasmFile = path.join(outDir, `${name}.shell.wasm`)
    await mkdir(outDir, { recursive: true })
    await writeFile(shellFile, shellProgram({ base: replBase(key), libraries }))
    await compileScheme({ entry: shellFile, output: wasmFile, loadPaths, optimize: 1, features: ['runtime-modules'] })

    const files = [...appFiles, ...(await Promise.all(loadPaths.map(schemeFiles))).flat()]
    files.forEach(file => this.addWatchFile(file))
    return replEntryCode({ wasmFile, reflectWasmDir: hootUrl.slice(0, -1), modules: await scanModules(files), key })
  }

  return {
    name: 'roost',
    enforce: 'pre',

    async configResolved(resolved) {
      config = resolved
      hoot = await hootPaths()
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
      if (live()) {
        relay = createRelay({ httpServer: server.httpServer, sourceFor: pageSource })
        server.middlewares.use(relay.middleware)
      }
      server.watcher.on('change', async file => {
        if (!file.endsWith('.scm')) return
        const page = live() && [...pages.entries()].find(([, page]) => file.startsWith(page.dir + path.sep))
        if (!page) return recompile()
        // Application code is loaded from source by the page, so nothing is compiled.
        const [key, { entry, known, structures }] = page
        const source = await readFile(file, 'utf8')
        let structure
        let imports
        try {
          structure = moduleStructure(source)
          imports = importedLibraries(source)
        } catch (error) {
          // Usually a save in the middle of an edit; the next save is read again.
          config.logger.warn(`roost: cannot read ${path.relative(config.root, file)}: ${error.message}`)
          return
        }
        // A library the shell lacks must be compiled into it.
        if (!imports.every(library => known.has(library))) return recompile()
        if (file === entry || !moduleHeader(source) || structure !== structures.get(file)) {
          structures.set(file, structure)
          server.ws.send({ type: 'full-reload' })
        } else {
          server.ws.send({ type: 'custom', event: 'roost:reload', data: { key, source } })
        }
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
      if (live()) return loadDevShell.call(this, entry)
      const serving = config.command === 'serve'
      const outDir = path.join(config.cacheDir, 'roost')
      const wasmFile = path.join(outDir, `${path.relative(config.root, entry).replaceAll(path.sep, '_')}.wasm`)
      // The entry's directory holds the application's own libraries.
      await compileScheme({ entry, output: wasmFile, loadPaths: [path.dirname(entry), ...loadPaths], optimize: serving ? 1 : undefined })

      const files = [...(await schemeFiles(path.dirname(entry))), ...(await Promise.all(loadPaths.map(schemeFiles))).flat()]
      files.forEach(file => this.addWatchFile(file))
      const modules = await scanModules(files)
      const reflectWasmDir = serving ? hootUrl.slice(0, -1) : `${config.base}hoot`.replace(/\/$/, '')
      return entryCode({ wasmFile, reflectWasmDir, modules })
    },

    // Vite calls buildEnd when the development server closes or restarts.
    buildEnd() {
      relay?.close()
      relay = null
    },

    // Saved application modules are handled by the watcher above, not by Vite's HMR.
    handleHotUpdate({ file }) {
      if (live() && file.endsWith('.scm')) return []
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
