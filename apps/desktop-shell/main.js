'use strict'

const { app, BrowserWindow, Tray, Menu, nativeImage, screen, dialog } = require('electron')
const { spawn } = require('child_process')
const fs = require('fs')
const http = require('http')
const net = require('net')
const os = require('os')
const path = require('path')

const HOST = process.env.DSH_HOST || '127.0.0.1'
const PORT = Number(process.env.DSH_PORT || 3080)
const WEB_URL = `http://${HOST}:${PORT}`

const ROOT_DIR = path.resolve(__dirname, '..', '..')
const NODE_BIN = path.join(ROOT_DIR, 'runtime', 'node', 'node.exe')
const CLI_BIN = path.join(ROOT_DIR, 'src', 'apps', 'cli', 'lib', 'bin.js')

function resolveDSHHome() {
  if (process.env.DSH_HOME) return process.env.DSH_HOME
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'launcher-config.json'), 'utf8'))
    if (cfg && typeof cfg.dataDir === 'string' && cfg.dataDir.trim()) return cfg.dataDir.trim()
  } catch {
    // no launcher-config yet (dev mode): fall through to the default
  }
  return path.join(os.homedir(), '.dsh')
}

const DSH_HOME = resolveDSHHome()
const STATE_FILE = path.join(DSH_HOME, 'shell-state.json')

const SMOKE = process.argv.includes('--smoke')
const TRAY_ICON_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAC8SURBVFhHY2AYBVAgb93tIGvZ2UAvDLIPxQEgwTkrzvw/fu4RzTHIHpB9GA4ASdIDgOzB64CPn39guJoaGGQuUQ4A0XJWXVTHyOaPOmDUAUPZAVv+HwKrQgWPVi3AopaWDjixBSHWcZsoR9DOAVZd/2tPgARv/6/FUE8nBwSvevf///93/xemoKsfdQCdHDCwaSDlxH+QTvrmAjRAyHIqOoB8POqAUQcMHQcMeKuY1gCnAwa0ZzTgfcOBAgChuzf5Mrkq6QAAAABJRU5ErkJggg=='

let win = null
let tray = null
let serverProc = null
let serviceExited = false
let isQuitting = false
let lang = 'zh'

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function debounce(fn, ms = 400) {
  let timer = null
  return (...args) => {
    clearTimeout(timer)
    timer = setTimeout(() => fn(...args), ms)
  }
}

function checkPort() {
  return new Promise((resolve) => {
    const sock = net.connect({ host: HOST, port: PORT })
    const done = (ok) => {
      sock.destroy()
      resolve(ok)
    }
    sock.setTimeout(700)
    sock.once('connect', () => done(true))
    sock.once('timeout', () => done(false))
    sock.once('error', () => done(false))
  })
}

function httpOk(timeout = 1200) {
  return new Promise((resolve) => {
    const req = http.get(WEB_URL, { timeout }, (res) => {
      res.resume()
      resolve(res.statusCode === 200)
    })
    req.once('timeout', () => {
      req.destroy()
      resolve(false)
    })
    req.once('error', () => resolve(false))
  })
}

async function waitForWeb(maxTries = 80, interval = 500) {
  for (let i = 0; i < maxTries; i += 1) {
    if (serviceExited) return false
    if (await httpOk()) return true
    await sleep(interval)
  }
  return false
}

function startService() {
  const args = [CLI_BIN, 'web', '--host', HOST, '--port', String(PORT), '--no-open']
  serverProc = spawn(NODE_BIN, args, {
    env: { ...process.env, DSH_HOME },
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  })
  serverProc.stdout.on('data', (chunk) => process.stdout.write(`[dsh] ${chunk}`))
  serverProc.stderr.on('data', (chunk) => process.stderr.write(`[dsh] ${chunk}`))
  serverProc.once('exit', (code) => {
    serviceExited = true
    serverProc = null
    if (!isQuitting && !SMOKE) {
      dialog.showErrorBox(
        'DSH-Portable',
        lang === 'zh'
          ? `DSH web 服务意外退出（code=${code}），应用将关闭。`
          : `The DSH web service exited unexpectedly (code=${code}). The app will close.`
      )
      isQuitting = true
      app.quit()
    } else if (isUpdating) {
      isQuitting = true
      app.quit()
    }
  })
}

function stopService() {
  if (!serverProc) return Promise.resolve()
  const proc = serverProc
  return new Promise((resolve) => {
    const killer = spawn('taskkill', ['/pid', String(proc.pid), '/T', '/F'], {
      windowsHide: true,
      stdio: 'ignore',
    })
    const timer = setTimeout(() => resolve(), 3000)
    killer.once('exit', () => {
      clearTimeout(timer)
      resolve()
    })
  })
}

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'))
  } catch {
    return {}
  }
}

function saveState(patch) {
  try {
    const next = { ...loadState(), ...patch }
    fs.mkdirSync(DSH_HOME, { recursive: true })
    fs.writeFileSync(STATE_FILE, JSON.stringify(next, null, 2))
  } catch (err) {
    console.error('[shell] failed to save state:', err.message)
  }
}

function detectLanguage() {
  if (process.env.DSH_LANG) {
    return process.env.DSH_LANG.toLowerCase().startsWith('zh') ? 'zh' : 'en'
  }
  try {
    const pref = fs.readFileSync(path.join(DSH_HOME, 'locale.preference'), 'utf8').trim()
    if (pref.toLowerCase().startsWith('zh')) return 'zh'
    if (pref.length > 0) return 'en'
  } catch {
    // no locale preference yet; fall through to system language
  }
  return app.getLocale().toLowerCase().startsWith('zh') ? 'zh' : 'en'
}

async function showFirstRunNotice() {
  const state = loadState()
  if (state.noticeShown === true) return true
  const detail =
    lang === 'zh'
      ? '本软件基于 DeepSeek 官方 MIT 开源代码构建，属非官方发行版；与 DeepSeek 无关联、未获背书。\n\n按现状提供，不提供任何担保；使用风险与 API 费用由使用者自担。\n\nAPI Key 等凭据仅保存在本机数据目录（默认 ~/.dsh），不会上传；遥测默认关闭。'
      : 'This software is an unofficial build based on DeepSeek\u0027s official MIT-licensed open source code; not affiliated with or endorsed by DeepSeek.\n\nProvided "AS IS" without warranty; users bear all risks and API costs.\n\nCredentials such as API keys are stored only in your local data directory (default ~/.dsh) and are never uploaded; telemetry is off by default.'
  const { response } = await dialog.showMessageBox({
    type: 'info',
    title: 'DSH-Portable',
    message: lang === 'zh' ? '非官方声明与隐私须知' : 'Unofficial Build Notice & Privacy',
    detail,
    buttons: lang === 'zh' ? ['我知道了', '退出'] : ['I understand', 'Quit'],
    defaultId: 0,
    cancelId: 1,
    noLink: true,
  })
  if (response !== 0) {
    isQuitting = true
    app.quit()
    return false
  }
  saveState({ noticeShown: true })
  return true
}

function minWindowSize() {
  if (process.env.DSH_MIN_SIZE === '0') return { width: 0, height: 0 }
  return {
    width: Number(process.env.DSH_MIN_WIDTH) || 640,
    height: Number(process.env.DSH_MIN_HEIGHT) || 480,
  }
}

function isBoundsVisible(bounds) {
  const margin = 80
  return screen.getAllDisplays().some((display) => {
    const wa = display.workArea
    return (
      bounds.x + bounds.width > wa.x + margin &&
      bounds.x < wa.x + wa.width - margin &&
      bounds.y + bounds.height > wa.y + margin &&
      bounds.y < wa.y + wa.height - margin
    )
  })
}

const saveWindowState = debounce(() => {
  if (!win) return
  const b = win.getBounds()
  saveState({ x: b.x, y: b.y, width: b.width, height: b.height })
})

function createWindow() {
  const state = loadState()
  const min = minWindowSize()
  const options = {
    width: state.width || 1100,
    height: state.height || 760,
    minWidth: min.width,
    minHeight: min.height,
    show: false,
    title: 'DSH-Portable',
    autoHideMenuBar: true,
    backgroundColor: '#111827',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  }
  if (Number.isFinite(state.x) && Number.isFinite(state.y) && isBoundsVisible(state)) {
    options.x = state.x
    options.y = state.y
  }
  win = new BrowserWindow(options)
  win.once('ready-to-show', () => win.show())
  win.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault()
      hideToTray()
    }
  })
  win.on('resize', saveWindowState)
  win.on('move', saveWindowState)
  win.on('closed', () => {
    win = null
  })
  win.loadURL(WEB_URL)
}

function createTray() {
  const icon = nativeImage.createDataURL(`data:image/png;base64,${TRAY_ICON_B64}`)
  tray = new Tray(icon)
  tray.setToolTip('DSH-Portable')
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: lang === 'zh' ? '显示主界面' : 'Show', click: showWindow },
    { type: 'separator' },
    { label: lang === 'zh' ? '退出' : 'Exit', click: quitApp },
  ]))
  tray.on('double-click', showWindow)
}

function showWindow() {
  if (!win) return
  if (win.isMinimized()) win.restore()
  win.show()
  win.focus()
}

function hideToTray() {
  if (!win) return
  win.hide()
  const state = loadState()
  if (!state.trayHintShown && tray) {
    saveState({ trayHintShown: true })
    tray.displayBalloon({
      title: 'DSH-Portable',
      content:
        lang === 'zh'
          ? '已最小化到托盘，服务仍在后台运行；右键托盘图标选择"退出"即可完全关闭。'
          : 'Minimized to tray; the service keeps running in the background. Right-click the tray icon and choose "Exit" to quit.',
    })
  }
}

function quitApp() {
  isQuitting = true
  if (win) win.close()
  stopService().finally(() => app.quit())
}

async function runSmoke() {
  const listening = await checkPort()
  console.log(`SMOKE port_${PORT}_listening=${listening}`)
  let ok = false
  if (listening) {
    ok = await httpOk()
  } else {
    startService()
    ok = await waitForWeb()
  }
  console.log(`SMOKE web_200=${ok}`)
  if (serverProc) await stopService()
  console.log(ok ? 'SMOKE_OK' : 'SMOKE_FAIL')
  app.exit(ok ? 0 : 1)
}

async function main() {
  app.setAppUserModelId('com.dsh.portable')
  lang = detectLanguage()

  if (SMOKE) {
    await runSmoke()
    return
  }

  const proceed = await showFirstRunNotice()
  if (!proceed) return

  const listening = await checkPort()
  if (!listening) {
    startService()
    const ready = await waitForWeb()
    if (!ready) {
      dialog.showErrorBox(
        'DSH-Portable',
        lang === 'zh'
          ? `无法启动 DSH web 服务（${WEB_URL} 未响应），应用将关闭。`
          : `Failed to start the DSH web service (${WEB_URL} did not respond). The app will close.`
      )
      isQuitting = true
      await stopService()
      app.quit()
      return
    }
  }

  createWindow()
  createTray()
}

const gotSingleInstanceLock = SMOKE ? true : app.requestSingleInstanceLock()

if (!gotSingleInstanceLock) {
  app.quit()
} else {
  app.on('second-instance', () => showWindow())
  app.on('before-quit', () => {
    isQuitting = true
  })
  app.on('window-all-closed', () => {
    // keep running in the tray until the user explicitly exits
  })
  app.whenReady().then(main)
}
