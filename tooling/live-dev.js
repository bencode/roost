// Live development (ROOST_REPL=1): the page runs a development shell, Roost compiled
// with Hoot's run-time module system, that loads the application's modules from source,
// starts a REPL, and evaluates a saved module again when the server sends roost:reload.
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { createRelay, replBase } from './repl-relay.js'
import { importedLibraries, moduleHeader, moduleStructure, programAsLibrary } from './scheme-source.js'

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

// Runs after boot: start the shell, and evaluate saved modules of this page.
const startShell = key =>
  [
    `([start, reload]) => {`,
    `  const show = error => (error instanceof Error ? error : repr(error))`,
    `  try {`,
    `    start.call()`,
    `  } catch (error) {`,
    `    console.error('roost dev:', show(error))`,
    `  }`,
    `  import.meta.hot?.on('roost:reload', ({ key, source }) => {`,
    `    if (key !== ${JSON.stringify(key)}) return`,
    `    try {`,
    `      reload.call(source)`,
    `    } catch (error) {`,
    `      console.error('roost reload:', show(error))`,
    `    }`,
    `  })`,
    `}`,
  ].join('\n')

// build: the plugin's { compileScheme, schemeFiles, scanModules, entryCode }.
export const createLiveDev = ({ config, loadPaths, reflectWasmDir, build }) => {
  // Per page entry key: { entry, dir, known, structures }. known holds the library names
  // the page can import: compiled into its shell, or its own modules.
  const pages = new Map()
  let relay = null

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
  const load = async (entry, watch) => {
    const dir = path.dirname(entry)
    const key = path.relative(config.root, entry)
    const appFiles = await build.schemeFiles(dir)
    const sources = await Promise.all(appFiles.map(file => readFile(file, 'utf8')))
    const appModules = new Set(sources.map(source => moduleHeader(source)?.name).filter(Boolean))
    const libraries = [...new Set([...roostLibraries, ...sources.flatMap(importedLibraries)])].filter(
      library => !appModules.has(library) && library !== '(scheme base)',
    )
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
    await build.compileScheme({ entry: shellFile, output: wasmFile, loadPaths, optimize: 1, features: ['runtime-modules'] })

    const files = [...appFiles, ...(await Promise.all(loadPaths.map(build.schemeFiles))).flat()]
    files.forEach(watch)
    return build.entryCode({ wasmFile, reflectWasmDir, modules: await build.scanModules(files), then: startShell(key) })
  }

  const attach = server => {
    relay = createRelay({ httpServer: server.httpServer, sourceFor: pageSource })
    server.middlewares.use(relay.middleware)
  }

  const pageOf = file => [...pages.entries()].find(([, page]) => file.startsWith(page.dir + path.sep))

  // A saved file of a page: nothing is compiled, since the page loads its modules from
  // source. Returns false for files that are not a page's.
  const change = async (file, server, recompile) => {
    const page = pageOf(file)
    if (!page) return false
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
      return true
    }
    // A library the shell lacks must be compiled into it.
    if (!imports.every(library => known.has(library))) recompile()
    else if (file === entry || !moduleHeader(source) || structure !== structures.get(file)) {
      structures.set(file, structure)
      server.ws.send({ type: 'full-reload' })
    } else {
      server.ws.send({ type: 'custom', event: 'roost:reload', data: { key, source } })
    }
    return true
  }

  const close = () => {
    relay?.close()
    relay = null
  }

  return { load, attach, change, close }
}
