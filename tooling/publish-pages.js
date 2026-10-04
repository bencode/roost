// pnpm pages: build the examples for GitHub Pages and push them to the gh-pages branch.
// The branch holds one commit, the latest build; each publish replaces it.
import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const dist = path.join(repoRoot, 'dist')
const base = process.env.ROOST_PAGES_BASE ?? '/roost/'

const run = (command, args, cwd = repoRoot) =>
  execFileSync(command, args, { cwd, stdio: 'inherit' })
const output = (command, args) => execFileSync(command, args, { cwd: repoRoot, encoding: 'utf8' }).trim()

const remote = output('git', ['remote', 'get-url', 'origin'])
const source = output('git', ['rev-parse', '--short', 'HEAD'])

run('pnpm', ['exec', 'vite', 'build', `--base=${base}`])
// Serve the files as they are, without Jekyll.
writeFileSync(path.join(dist, '.nojekyll'), '')

run('git', ['init', '--quiet', '--initial-branch=gh-pages'], dist)
run('git', ['add', '--all'], dist)
run('git', ['commit', '--quiet', '--message', `Publish the examples from ${source}`], dist)
run('git', ['push', '--force', '--quiet', remote, 'gh-pages'], dist)
console.log(`Published ${source} to the gh-pages branch of ${remote}`)
