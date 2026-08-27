'use strict'

// patch-beav-key.cjs — 为 beav-creator-dsh 的 settings.plugin.item 槽位注册
// 补上缺失的 options.key（插件 v0.1.2 写漏；rc8 keyed 槽位要求必须带 key）。
// 用法：node patch-beav-key.cjs <beav-creator-dsh/lib/client.js>

const fs = require('fs')

const file = process.argv[2]
if (!file) {
  console.error('usage: node patch-beav-key.cjs <client.js>')
  process.exit(2)
}

let text = fs.readFileSync(file, 'utf8')
const pattern = /(id: "beav",)(\r?\n)(\s*order: 40,)/g
let count = 0
text = text.replace(pattern, (m, id, nl, order) => {
  count += 1
  return id + nl + '    key: "beav",' + nl + order
})

if (count === 0) {
  console.error('PATTERN_NOT_FOUND (already patched or upstream changed)')
  process.exit(1)
}

fs.writeFileSync(file, text, 'utf8')
console.log('PATCHED occurrences: ' + count)
