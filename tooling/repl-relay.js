// Relays REPL clients to the page. Pages cannot listen for connections, so the page's
// (hoot web-repl) connects out over a WebSocket at <base>/repl, and REPL clients
// (`pnpm repl`, telnet, Geiser) connect here over TCP. This is the protocol of Hoot's
// own `hoot server`: Scheme data (new id), (write id #vu8(...)) and (close id).
import net from 'node:net'
import { WebSocketServer } from 'ws'

// One base per page entry; the key is encoded so it holds no slashes.
export const replBase = key => `/@roost-repl/${encodeURIComponent(key)}`
const basePattern = /^\/@roost-repl\/([^/]+)\/repl/

// The page's port flushes in chunks, so a message may span several frames: split the
// stream into complete messages. Messages hold no strings, so counting parentheses works.
const messageSplitter = () => {
  let buffer = ''
  return text => {
    buffer += text
    const messages = []
    let depth = 0
    let start = 0
    for (let i = 0; i < buffer.length; i += 1) {
      if (buffer[i] === '(') depth += 1
      else if (buffer[i] === ')' && --depth === 0) {
        messages.push(buffer.slice(start, i + 1).trim())
        start = i + 1
      }
    }
    buffer = buffer.slice(start)
    return messages
  }
}

const parseMessage = text => {
  const write = text.match(/^\(write (\d+) #vu8\(([\d ]*)\)\)$/)
  if (write) return { type: 'write', id: Number(write[1]), bytes: Buffer.from(write[2].split(' ').filter(Boolean).map(Number)) }
  const close = text.match(/^\(close (\d+)\)$/)
  if (close) return { type: 'close', id: Number(close[1]) }
  return { type: 'unknown', text }
}

// sourceFor(key, path) returns a module's source text, or null when there is none.
export const createRelay = ({ httpServer, sourceFor, port = 37146, log = console.log }) => {
  const sockets = new WebSocketServer({ noServer: true })
  // Open pages, oldest first; a new REPL client talks to the newest. Each client stays
  // with the page it started on.
  const pages = []
  const clients = new Map()
  let nextId = 0
  // (web socket) in Hoot only reads binary frames.
  const send = (page, text) => page.send(Buffer.from(text))

  httpServer.on('upgrade', (request, socket, head) => {
    if (!new URL(request.url, 'http://host').pathname.match(/^\/@roost-repl\/[^/]+\/repl$/)) return
    sockets.handleUpgrade(request, socket, head, page => {
      pages.push(page)
      const split = messageSplitter()
      page.on('message', data => {
        for (const message of split(data.toString()).map(parseMessage)) {
          if (message.type === 'write') clients.get(message.id)?.socket.write(message.bytes)
          else if (message.type === 'close') clients.get(message.id)?.socket.end()
          else log(`roost repl: unexpected message ${message.text}`)
        }
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
    clients.set(id, { socket, page })
    send(page, `(new ${id})`)
    socket.on('data', bytes => send(page, `(write ${id} #vu8(${[...bytes].join(' ')}))`))
    socket.on('close', () => {
      clients.delete(id)
      if (pages.includes(page)) send(page, `(close ${id})`)
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
