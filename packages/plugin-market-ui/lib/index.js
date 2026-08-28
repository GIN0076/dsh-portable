/**
 * dsh-market-ui host entry: mounts loopback-only HTTP routes that drive the
 * plugin market CLI (packages/plugin-market/dsh-market.ps1):
 *   GET  /dsh-market/search    — npm search (JSON)
 *   GET  /dsh-market/info      — package info (JSON)
 *   GET  /dsh-market/installed — installed plugins in the web profile (JSON)
 *   POST /dsh-market/install   — install a package (goes through M2 review)
 */

import { execFile } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-market-ui'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

/** Locate dsh-market.ps1: prefer the Portable install tree (packages/), then
 * walk up from this file (source tree / copied install). */
function resolveMarketScript() {
  const candidates = []
  try {
    candidates.push(path.join(process.cwd(), 'packages', 'plugin-market', 'dsh-market.ps1'))
  } catch {
    // ignore
  }
  let dir = __dirname
  for (let i = 0; i < 8; i += 1) {
    candidates.push(path.join(dir, '..', 'plugin-market', 'dsh-market.ps1'))
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

const MARKET_SCRIPT = resolveMarketScript()

function dshHome() {
  return process.env.DSH_HOME || path.join(process.env.USERPROFILE || '', '.dsh')
}

/** Run dsh-market.ps1 with args; resolves with { code, out } (out = stdout+stderr). */
function runMarket(args) {
  return new Promise((resolve) => {
    execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', MARKET_SCRIPT, ...args], {
      timeout: 300000,
      windowsHide: true,
      maxBuffer: 8 * 1024 * 1024,
    }, (err, stdout, stderr) => {
      const out = `${stdout || ''}${stderr || ''}`
      resolve({ code: err && typeof err.code === 'number' ? err.code : 0, out })
    })
  })
}

/** Extract the last JSON line from mixed stdout/stderr output. */
function lastJson(out) {
  const lines = out.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    try {
      return JSON.parse(lines[i])
    } catch {
      // keep scanning for the last JSON payload
    }
  }
  return null
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

      // GET /dsh-market/search?q=...
      disposers.push(host.webServer.register({
        kind: 'exact',
        path: '/dsh-market/search',
        handler: async (request, response) => {
          if (request.method !== 'GET') { response.writeHead(405, { allow: 'GET' }); response.end(); return }
          if (!isTrustedOrigin(request.headers.origin)) { sendJson(response, 403, { error: 'market is limited to loopback requests' }); return }
          const url = new URL(request.url, 'http://localhost')
          const q = (url.searchParams.get('q') || '').trim()
          if (!q) { sendJson(response, 400, { error: 'missing q' }); return }
          try {
            const { out } = await runMarket(['search', '-Query', q, '-Json', '-DshHome', dshHome()])
            const data = lastJson(out)
            if (!data) { sendJson(response, 500, { error: 'unparseable market output', detail: out.slice(0, 600) }); return }
            sendJson(response, 200, { ok: true, packages: data })
          } catch (err) {
            sendJson(response, 500, { error: String(err && err.message ? err.message : err) })
          }
        },
      }))

      // GET /dsh-market/info?pkg=...
      disposers.push(host.webServer.register({
        kind: 'exact',
        path: '/dsh-market/info',
        handler: async (request, response) => {
          if (request.method !== 'GET') { response.writeHead(405, { allow: 'GET' }); response.end(); return }
          if (!isTrustedOrigin(request.headers.origin)) { sendJson(response, 403, { error: 'market is limited to loopback requests' }); return }
          const url = new URL(request.url, 'http://localhost')
          const pkg = (url.searchParams.get('pkg') || '').trim()
          if (!pkg) { sendJson(response, 400, { error: 'missing pkg' }); return }
          try {
            const { out } = await runMarket(['info', '-Package', pkg, '-Json', '-DshHome', dshHome()])
            const data = lastJson(out)
            if (!data) { sendJson(response, 500, { error: 'unparseable market output', detail: out.slice(0, 600) }); return }
            sendJson(response, 200, { ok: true, ...data })
          } catch (err) {
            sendJson(response, 500, { error: String(err && err.message ? err.message : err) })
          }
        },
      }))

      // GET /dsh-market/installed
      disposers.push(host.webServer.register({
        kind: 'exact',
        path: '/dsh-market/installed',
        handler: async (request, response) => {
          if (request.method !== 'GET') { response.writeHead(405, { allow: 'GET' }); response.end(); return }
          if (!isTrustedOrigin(request.headers.origin)) { sendJson(response, 403, { error: 'market is limited to loopback requests' }); return }
          try {
            const { out } = await runMarket(['installed', '-Json', '-DshHome', dshHome()])
            const data = lastJson(out)
            sendJson(response, 200, { ok: true, plugins: data || [] })
          } catch (err) {
            sendJson(response, 500, { error: String(err && err.message ? err.message : err) })
          }
        },
      }))

      // POST /dsh-market/install { pkg, approve?: string[] }
      disposers.push(host.webServer.register({
        kind: 'exact',
        path: '/dsh-market/install',
        handler: async (request, response) => {
          if (request.method !== 'POST') { response.writeHead(405, { allow: 'POST' }); response.end(); return }
          if (!isTrustedOrigin(request.headers.origin)) { sendJson(response, 403, { error: 'market is limited to loopback requests' }); return }
          let body = ''
          for await (const chunk of request) body += chunk
          let payload = {}
          try { payload = JSON.parse(body || '{}') } catch { sendJson(response, 400, { error: 'invalid JSON body' }); return }
          const pkg = String(payload.pkg || '').trim()
          if (!pkg) { sendJson(response, 400, { error: 'missing pkg' }); return }
          const approve = Array.isArray(payload.approve) ? payload.approve.map(String) : []
          const args = ['install', '-Package', pkg, '-DshHome', dshHome()]
          if (approve.length > 0) args.push('-Approve', approve.join(','))
          try {
            const { code, out } = await runMarket(args)
            // 0 = installed, 2 = needs confirmation (M2 RISK), 3 = rejected (M2 RED)
            if (code === 2) { sendJson(response, 409, { ok: false, status: 'needs-approval', detail: out.trim().slice(0, 1000) }); return }
            if (code === 3) { sendJson(response, 422, { ok: false, status: 'rejected', detail: out.trim().slice(0, 1000) }); return }
            if (code !== 0) { sendJson(response, 500, { ok: false, status: 'error', detail: out.trim().slice(0, 1000) }); return }
            sendJson(response, 200, { ok: true, status: 'installed', detail: out.trim().slice(0, 1000) })
          } catch (err) {
            sendJson(response, 500, { ok: false, status: 'error', detail: String(err && err.message ? err.message : err) })
          }
        },
      }))

      return () => disposers.forEach((dispose) => dispose())
    }, 'dsh-market-ui: http routes')
  })
}
