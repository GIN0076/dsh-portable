/**
 * dsh-update-check host entry: mounts loopback-only HTTP routes that run the
 * DSH-Portable update engine (addons/update-engine/update-dsh.ps1):
 *   GET  /dsh-update/check  — check mode, returns version status as JSON
 *   POST /dsh-update/apply  — apply mode, spawns a detached update process
 *                             and returns immediately (the web service is
 *                             stopped by the updater mid-flight).
 */

import { execFile, spawn } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-update-check'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

/** Locate update-dsh.ps1: the web process cwd is the Portable root (the
 * Electron shell launches it with WorkingDir={app}); walking up from this
 * file also covers pnpm file: installs that link back to the source tree. */
function resolveUpdateScript() {
  const candidates = []
  // 1. Process cwd (Electron shell launches dsh web with WorkingDir = app root).
  try {
    candidates.push(path.join(process.cwd(), 'addons', 'update-engine', 'update-dsh.ps1'))
  } catch {
    // ignore
  }
  // 2. Walk up from this file (source tree, or a copied install).
  let dir = __dirname
  for (let i = 0; i < 8; i += 1) {
    candidates.push(path.join(dir, 'addons', 'update-engine', 'update-dsh.ps1'))
    dir = path.dirname(dir)
  }
  for (const candidate of candidates) {
    try {
      if (fs.existsSync(candidate)) return candidate
    } catch {
      // ignore
    }
  }
  return candidates[0]
}

const UPDATE_SCRIPT = resolveUpdateScript()
const PROGRAM_ROOT = path.dirname(path.dirname(path.dirname(UPDATE_SCRIPT)))

function dshHome() {
  return process.env.DSH_HOME || path.join(process.env.USERPROFILE || '', '.dsh')
}

function runUpdateCheck() {
  return new Promise((resolve) => {
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', UPDATE_SCRIPT, 'check', '-DshHome', dshHome()]
    execFile('powershell.exe', args, { timeout: 180000, windowsHide: true, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
      const out = `${stdout || ''}${stderr || ''}`
      const current = (out.match(/current=([0-9A-Za-z.\-]+)/) || [])[1] || '?'
      const latest = (out.match(/latest=([0-9A-Za-z.\-]+)/) || [])[1] || '?'
      const tag = (out.match(/commit=([0-9a-f]{40})/) || [])[1] || ''
      let status = 'error'
      if (/UPDATE AVAILABLE/i.test(out)) status = 'update-available'
      else if (/up to date/i.test(out)) status = 'up-to-date'
      resolve({
        status,
        current,
        latest,
        tag,
        detail: err ? String(err.message) : out.trim().slice(0, 600),
      })
    })
  })
}

/** Start a detached update-apply process. The updater stops the running web
 * service (and this very process), so we write a `.updating` marker first —
 * the Electron shell checks it and exits quietly instead of showing an
 * "unexpected exit" error — and return before the kill lands. */
function runUpdateApply() {
  const programRoot = PROGRAM_ROOT
  const markFile = path.join(programRoot, '.updating')
  try {
    fs.writeFileSync(markFile, new Date().toISOString())
  } catch {
    // Marker is best-effort; the update can still proceed.
  }
  const logDir = path.join(programRoot, 'logs')
  try {
    fs.mkdirSync(logDir, { recursive: true })
  } catch {
    // ignore
  }
  const logFile = path.join(logDir, 'update-ui-apply.log')
  let logFd = 2 // stderr fallback
  try {
    logFd = fs.openSync(logFile, 'a')
  } catch {
    // ignore
  }
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', UPDATE_SCRIPT, 'apply', '-KillRunning', '-DshHome', dshHome()]
  const child = spawn('powershell.exe', args, {
    detached: true,
    windowsHide: true,
    stdio: ['ignore', logFd, logFd],
  })
  child.unref()
  return { status: 'started', log: logFile }
}

/** Loopback-only guard: refuse cross-origin / proxied requests. */
function isTrustedOrigin(origin) {
  if (!origin) return true
  try {
    const u = new URL(origin)
    return u.hostname === '127.0.0.1' || u.hostname === 'localhost' || u.hostname === '::1' || u.hostname === '[::1]'
  } catch {
    return false
  }
}

function sendJson(response, code, payload) {
  response.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  })
  response.end(JSON.stringify(payload))
}

export function apply(ctx) {
  ctx.inject(['webServer'], (host) => {
    host.effect(() => {
      const disposers = []

      disposers.push(host.webServer.register({
        kind: 'exact',
        path: '/dsh-update/check',
        handler: async (request, response) => {
          if (request.method !== 'GET') {
            response.writeHead(405, { allow: 'GET' })
            response.end()
            return
          }
          if (!isTrustedOrigin(request.headers.origin)) {
            sendJson(response, 403, { error: 'update check is limited to loopback requests' })
            return
          }
          try {
            sendJson(response, 200, await runUpdateCheck())
          } catch (err) {
            sendJson(response, 500, { status: 'error', detail: String(err && err.message ? err.message : err) })
          }
        },
      }))

      disposers.push(host.webServer.register({
        kind: 'exact',
        path: '/dsh-update/apply',
        handler: async (request, response) => {
          if (request.method !== 'POST') {
            response.writeHead(405, { allow: 'POST' })
            response.end()
            return
          }
          if (!isTrustedOrigin(request.headers.origin)) {
            sendJson(response, 403, { error: 'update apply is limited to loopback requests' })
            return
          }
          try {
            sendJson(response, 200, runUpdateApply())
          } catch (err) {
            sendJson(response, 500, { status: 'error', detail: String(err && err.message ? err.message : err) })
          }
        },
      }))

      return () => disposers.forEach((dispose) => dispose())
    }, 'dsh-update-check: http routes')
  })
}
