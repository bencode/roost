#!/usr/bin/env node
// REPL client for a page served with ROOST_REPL=1.
//   pnpm repl                 interactive session
//   pnpm repl '(+ 1 2)' ...   evaluate each argument as one line, print, and exit;
//                             the exit code is 1 when an evaluation raises an error
import net from 'node:net'

const port = Number(process.env.ROOST_REPL_PORT ?? 37146)
const lines = process.argv.slice(2)
// A prompt ends the output of each line: "(roost-dev main)> " or "(store cart) [1]> ".
const prompt = /(?:^|\n)\([^\n]*\)(?: \[\d+\])?> $/

const socket = net.connect(port, '127.0.0.1')
// Decode as a stream: a character's bytes may arrive in two chunks.
socket.setEncoding('utf8')
socket.on('error', error => {
  console.error(`roost repl: cannot connect to port ${port} (${error.message}). Is \`ROOST_REPL=1 pnpm dev\` running with the page open?`)
  process.exit(1)
})

if (lines.length === 0) {
  socket.pipe(process.stdout)
  process.stdin.pipe(socket)
  socket.on('close', () => process.exit(0))
} else {
  let output = ''
  let pending = [...lines]
  let started = false
  let failed = false
  let done = false
  socket.on('data', chunk => {
    output += chunk
    if (!prompt.test(output)) return
    const text = output.replace(prompt, '').trim()
    output = ''
    if (started && text) console.log(text)
    if (/Scheme error:|While executing meta-command/.test(text)) failed = true
    started = true
    if (pending.length === 0) {
      done = true
      return socket.end()
    }
    socket.write(`${pending.shift()}\n`)
  })
  socket.on('close', () => {
    if (!started) console.error(output.trim() || 'roost repl: the page closed the connection')
    else if (!done) console.error(`${output.trim()}\nroost repl: the connection closed before every line ran`.trim())
    process.exit(failed || !done ? 1 : 0)
  })
}
