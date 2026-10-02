// @vitest-environment jsdom
// Uses the plugin-free path: compile with guild, then boot with the loader.
import { readFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import * as React from 'react'
import * as ReactDOMClient from 'react-dom/client'
import { beforeAll, describe, expect, it } from 'vitest'
import { boot } from '../js/roost-loader.js'
import { compileScheme, hootPaths } from '../tooling/vite-plugin-roost.js'

const here = path.dirname(fileURLToPath(import.meta.url))
const roots = ['identity', 'children', 'unkeyed', 'dom', 'counter', 'bad']
const errors = []

const log = () => globalThis.roostLog.map(entry => entry.join(' '))
const byId = id => document.getElementById(id)
const click = id =>
  React.act(() => byId(id).dispatchEvent(new window.MouseEvent('click', { bubbles: true })))
const keyWarnings = () => errors.filter(message => message.includes('unique "key"'))

// Hoot fetches its runtime wasm by path; serve local files for the test environment.
const serveLocalFiles = () => {
  const fetch = globalThis.fetch
  globalThis.fetch = async (url, init) =>
    typeof url === 'string' && path.isAbsolute(url)
      ? new Response(await readFile(url), { headers: { 'Content-Type': 'application/wasm' } })
      : fetch(url, init)
}

beforeAll(async () => {
  document.body.innerHTML = roots.map(id => `<div id="${id}"></div>`).join('')
  globalThis.IS_REACT_ACT_ENVIRONMENT = true
  globalThis.roostLog = []
  const consoleError = console.error
  console.error = (...args) => {
    errors.push(args.map(String).join(' '))
    consoleError.apply(console, args)
  }
  serveLocalFiles()

  const wasm = path.join(os.tmpdir(), 'roost-tests', 'react-adapter.wasm')
  await compileScheme({
    entry: path.join(here, 'fixtures', 'react-adapter.scm'),
    output: wasm,
    loadPaths: [path.join(here, '..', 'modules')],
    optimize: 1,
  })
  const hoot = await hootPaths()
  const { Scheme } = await import('hoot:reflect')
  const bytes = await readFile(wasm)
  await React.act(() =>
    boot({
      Scheme,
      wasm: bytes,
      reflectWasmDir: hoot.reflectWasmDir,
      modules: { react: React, 'react-dom/client': ReactDOMClient },
    }),
  )
}, 60_000)

describe('component identity', () => {
  it('keeps a child mounted when its parent re-renders', async () => {
    await click('identity-rerender')
    await click('identity-rerender')
    expect(byId('identity').textContent).toContain('render 2')
    expect(log().filter(entry => entry === 'child-mounted')).toHaveLength(1)
    expect(globalThis.roostChildEffect).toBe(true)
  })
})

describe('children', () => {
  it('forwards static children and only warns for unkeyed dynamic lists', () => {
    expect(byId('children').querySelector('section.card').innerHTML).toBe('<h2>Title</h2><p>Body</p>')
    expect(byId('keyed').textContent).toBe('ab')
    expect(byId('unkeyed').textContent).toBe('xy')
    expect(keyWarnings()).toHaveLength(1)
  })
})

describe('DOM properties', () => {
  it('maps names, style and events', async () => {
    const button = byId('dom-button')
    expect(button.className).toBe('primary')
    expect(button.getAttribute('aria-label')).toBe('Increment')
    expect(button.getAttribute('data-count')).toBe('0')
    expect(button.style.marginTop).toBe('8px')
    expect(button.style.getPropertyValue('--accent')).toBe('blue')
    await click('dom-button')
    expect(button.textContent).toBe('1')
    expect(button.getAttribute('data-count')).toBe('1')
  })
})

describe('hooks', () => {
  it('keeps setters stable, applies updaters and respects effect deps', async () => {
    expect(byId('counter-output').textContent).toBe('items: 0')
    await click('counter-add')
    await click('counter-add')
    await click('counter-same')
    expect(byId('counter-output').textContent).toBe('items: 2')
    const stable = log().filter(entry => entry.startsWith('setter-stable'))
    expect(stable.length).toBeGreaterThan(0)
    expect(stable.every(entry => entry === 'setter-stable true')).toBe(true)
    expect(log().filter(entry => entry.startsWith('effect'))).toEqual(['effect 0'])
    expect(log()).not.toContain('cleanup')
  })
})

describe('errors', () => {
  it('reports an unsupported child as a render error', async () => {
    // act rethrows the render error synchronously once the click has been processed.
    let thrown
    try {
      await click('bad-trigger')
    } catch (error) {
      thrown = error
    }
    expect(thrown?.message).toBe('node->react: unsupported child not-a-child')
  })
})
