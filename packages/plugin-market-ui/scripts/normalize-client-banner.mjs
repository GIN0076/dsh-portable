#!/usr/bin/env node
/**
 * Post-build normalization of client/client.js so the committed artifact is
 * machine-independent:
 * 1. Collapse the rolldown-folded loader banner onto the required one line
 *    `window.__ModuleLoader__.load({ id: "…", factory: (require) => {`.
 * 2. Rewrite absolute `\0dsh-css:<abs>\src\client\….css.mjs` virtual ids to
 *    a stable repo-relative form (`dsh-css:src/client/…`).
 */
import fs from 'node:fs'

const file = 'client/client.js'
const name = JSON.parse(fs.readFileSync('package.json', 'utf8')).name
const required = `window.__ModuleLoader__.load({ id: ${JSON.stringify(name)}, factory: (require) => {`

let code = fs.readFileSync(file, 'utf8')

// --- 1. one-line loader banner -------------------------------------------
if (!code.startsWith(required)) {
  const lines = code.split('\n')
  const head = [
    'window.__ModuleLoader__.load({',
    `\tid: ${JSON.stringify(name)},`,
    '\tfactory: (require) => {',
  ]
  if (lines[0] !== head[0] || lines[1] !== head[1] || lines[2] !== head[2]) {
    console.error(`normalize-client-banner: unexpected ${file} header:\n` + lines.slice(0, 3).join('\n'))
    process.exit(1)
  }
  lines[0] = required
  lines[1] = ''
  lines[2] = ''
  code = lines.join('\n')
}

// --- 2. machine-independent CSS virtual ids -------------------------------
// `\0dsh-css:<abs>/src/client/X.module.css.mjs` → `\0dsh-css:src/client/X.module.css.mjs`
code = code.replace(/(dsh-css:)([^\n"]*?)(src[/\\][^\n"]*?\.css\.mjs)/g, (_all, prefix, _dir, rel) =>
  prefix + rel.replaceAll('\\', '/'))

// Guard: no absolute drive path or root-anchored virtual id may survive.
const leaks = [
  ...code.matchAll(/dsh-css:(?:\/|[A-Za-z]:[/\\])[^\n"]*/g),
].map(match => match[0].slice(0, 60))
if (leaks.length > 0) {
  console.error(`normalize-client-banner: absolute path left in ${file}: ${leaks.slice(0, 3).join(', ')}`)
  process.exit(1)
}

fs.writeFileSync(file, code)
console.log(`normalize-client-banner ok: ${file}`)
