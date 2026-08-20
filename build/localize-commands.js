'use strict'

// localize-commands.js — 汉化 DSH-Portable 内置命令描述。
//
// 背景：官方上游 rc.8 的命令描述大多硬编码英文（compact / export / feedback /
// goal / permission / plan），只有少数客户端命令走了中文词典。本脚本只修改
// **构建产物**（packages/*/lib 与 node_modules/@deepseek-ai/*/lib 下的 .js），
// 不改官方源码，维持"官方源码零修改"的封装原则。
//
// 用法：node localize-commands.js <srcRoot>
// 应在 flatten / repair-junctions 之后、压缩 src.7z 之前执行。
// 找不到原文会报错退出（防止上游改文案后补丁静默失效）。

const fs = require('fs')
const path = require('path')

const srcRoot = process.argv[2]
if (!srcRoot) {
  console.error('usage: node localize-commands.js <srcRoot>')
  process.exit(2)
}

const REPLACEMENTS = [
  ['Compact older conversation history', '压缩较早的对话历史记录。'],
  ['Download this Session log as a ZIP archive', '将本次会话记录以压缩文件（ZIP 格式）的形式下载下来'],
  ['record feedback about this session', '记录本次会议的反馈信息'],
  ['set or view the goal for a long-running task', '设定目标或明确长期任务的目标'],
  ['Switch the permission preset (sandbox mode + approval policy)', '切换权限预设（沙盒模式 + 审批策略）'],
  ['Enter or leave plan mode', '进入或退出计划模式'],
]

const counts = new Map(REPLACEMENTS.map(([k]) => [k, 0]))
let changedFiles = 0

function walk(dir) {
  let entries
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const ent of entries) {
    const p = path.join(dir, ent.name)
    if (ent.isDirectory()) {
      if (ent.name === '.pnpm') continue
      walk(p)
    } else if (ent.isFile() && ent.name.endsWith('.js') && !ent.name.endsWith('.map')) {
      processFile(p)
    }
  }
}

function processFile(file) {
  let text
  try {
    text = fs.readFileSync(file, 'utf8')
  } catch {
    return
  }
  let changed = false
  for (const [from, to] of REPLACEMENTS) {
    const parts = text.split(from)
    if (parts.length > 1) {
      counts.set(from, counts.get(from) + (parts.length - 1))
      text = parts.join(to)
      changed = true
    }
  }
  if (changed) {
    fs.writeFileSync(file, text, 'utf8')
    changedFiles += 1
  }
}

walk(srcRoot)

const missing = REPLACEMENTS.filter(([k]) => counts.get(k) === 0).map(([k]) => k)
console.log(JSON.stringify({ changedFiles, replacements: Object.fromEntries(counts) }, null, 2))
if (missing.length === REPLACEMENTS.length && changedFiles === 0) {
  console.log('localize-commands: already localized, nothing to do')
  process.exit(0)
}
if (missing.length) {
  console.error('MISSING source strings (upstream may have changed them):')
  for (const m of missing) console.error('  - ' + m)
  process.exit(1)
}
console.log('localize-commands: OK')
