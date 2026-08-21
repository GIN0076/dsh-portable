'use strict'

// patch-xueqiu-windows.cjs — dsh-xueqiu Windows 兼容补丁（应急/一键版）。
// 1) curl → curl.exe（PowerShell 把 curl 别名成 Invoke-WebRequest）
// 2) -o /dev/null → -o <NULL_DEV>（Windows curl 写不了 /dev/null，退出码 23，
//    导致 cookie 播种失败、雪球接口全部报错）
// 与 pnpm patchedDependencies（patches/dsh-xueqiu@1.19.0.patch）互补：
// pnpm 补丁管重装自动应用，本脚本管"已安装被覆盖时一键再修"。
// 用法：node patch-xueqiu-windows.cjs <src/index.js>

const fs = require('fs')

const file = process.argv[2]
if (!file) {
  console.error('usage: node patch-xueqiu-windows.cjs <src/index.js>')
  process.exit(2)
}

let text = fs.readFileSync(file, 'utf8')
let changed = false

const CURL_LINE = "const CURL_BIN = process.platform === 'win32' ? 'curl.exe' : 'curl'"
const NUL_LINE = "const NULL_DEV = process.platform === 'win32' ? 'NUL' : '/dev/null'"

if (!text.includes(CURL_LINE)) {
  const anchor = 'const DEFAULT_WATCHLIST = '
  const at = text.indexOf(anchor)
  if (at < 0) {
    console.error('ANCHOR_NOT_FOUND (upstream changed?)')
    process.exit(1)
  }
  const nl = text.indexOf('\n', at)
  const comment =
    '    // Windows fix: PowerShell aliases `curl` to Invoke-WebRequest, which mangles\n' +
    '    // curl-style args (-H etc.); use curl.exe explicitly to get the real binary.\n'
  text = text.slice(0, nl + 1) + comment + '    ' + CURL_LINE + '\n' + text.slice(nl + 1)
  changed = true
}

if (!text.includes(NUL_LINE)) {
  if (!text.includes(CURL_LINE)) {
    console.error('CURL_LINE missing after insert')
    process.exit(1)
  }
  text = text.replace(CURL_LINE, CURL_LINE + '\n    ' + NUL_LINE)
  changed = true
}

const OLD = '-o /dev/null '
const NEW = '-o " + NULL_DEV + " '
if (text.includes(OLD)) {
  text = text.split(OLD).join(NEW)
  changed = true
}

fs.writeFileSync(file, text, 'utf8')
console.log(changed ? 'PATCHED' : 'ALREADY_OK')
