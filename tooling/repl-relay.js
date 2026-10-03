// Relays terminal REPL clients (`pnpm repl`, telnet, Emacs) to the page. Pages cannot
// listen for connections, so the page connects out over a WebSocket at <base>/repl and
// clients connect here over TCP; the page runs a REPL session for each client.
// Messages to the page: {type: "open" | "input" | "close", id, text}; from the page:
// {type: "output", id, text}.
import net from 'node:net'
import { WebSocketServer } from 'ws'
import { readForms } from './scheme-source.js'

// One base per page entry; the key is encoded so it holds no slashes.
export const replBase = key => `/@roost-repl/${encodeURIComponent(key)}`
const basePattern = /^\/@roost-repl\/([^/]+)\/repl/

// Splits what a client types into inputs the REPL can evaluate at once: a meta-command
// is its line; anything else waits for its lines to hold complete forms.
export const inputSplitter = () => {
  let pending = ''
  return chunk => {
    pending += chunk
    const inputs = []
    for (;;) {
      const end = pending.lastIndexOf('\n') + 1
      const lines = pending.slice(0, end)
      if (!lines.trim()) {
        pending = pending.slice(end)
        return inputs
      }
      if (lines.trimStart().startsWith(',')) {
        const line = lines.indexOf('\n') + 1
        inputs.push(lines.slice(0, line))
        pending = pending.slice(line)
        continue
      }
      try {
        readForms(lines)
      } catch (error) {
        // Wait for the rest of the form; any other error is the REPL's to report.
        if (error.message.includes('incomplete')) return inputs
      }
      inputs.push(lines)
      pending = pending.slice(end)
    }
  }
}

// sourceFor(key, path) returns a module's source text, or null when there is none.
export const createRelay = ({ httpServer, sourceFor, port = 37146, log = console.log }) => {
  const sockets = new WebSocketServer({ noServer: true })
  // Open pages, oldest first; a new REPL client talks to the newest. Each client stays
  // with the page it started on.
  const pages = []
  const clients = new Map()
  let nextId = 0
  const send = (page, message) => page.send(JSON.stringify(message))

  httpServer.on('upgrade', (request, socket, head) => {
    if (!new URL(request.url, 'http://host').pathname.match(/^\/@roost-repl\/[^/]+\/repl$/)) return
    sockets.handleUpgrade(request, socket, head, page => {
      pages.push(page)
      page.on('message', data => {
        const message = JSON.parse(data.toString())
        if (message.type === 'output') clients.get(message.id)?.socket.write(message.text)
        else log(`roost repl: unexpected message ${data}`)
      })
      page.on('close', () => {
        pages.splice(pages.indexOf(page), 1)
        clients.forEach(client => client.page === page && client.socket.end())
      })
    })
  })

  const server = net.createServer(socket => {
    const page = pages.at(-1)
    if (!page) {
      socket.end('No page is connected. Open a page served with ROOST_REPL=1.\n')
      return
    }
    const id = nextId++
    const split = inputSplitter()
    clients.set(id, { socket, page })
    send(page, { type: 'open', id })
    socket.setEncoding('utf8')
    socket.on('data', text => split(text).forEach(input => send(page, { type: 'input', id, text: input })))
    socket.on('close', () => {
      clients.delete(id)
      if (pages.includes(page)) send(page, { type: 'close', id })
    })
  })
  server.on('error', error => log(`roost repl: cannot listen on ${port}: ${error.message}`))
  server.listen(port, '127.0.0.1')

  const close = () => {
    clients.forEach(client => client.socket.destroy())
    pages.forEach(page => page.close())
    sockets.close()
    server.close()
  }

  // GET <base>/repl/load/a/b serves the source of module (a b).
  const middleware = async (request, response, next) => {
    const url = new URL(request.url, 'http://host')
    const base = url.pathname.match(basePattern)
    const load = url.pathname.match(/^\/@roost-repl\/[^/]+\/repl\/load\/(.+)$/)
    if (!base || !load) return next()
    const source = await sourceFor(decodeURIComponent(base[1]), decodeURIComponent(load[1]))
    if (source === null) {
      response.statusCode = 404
      response.end()
      return
    }
    response.setHeader('Content-Type', 'text/plain; charset=utf-8')
    response.end(source)
  }

  return { middleware, close }
}
