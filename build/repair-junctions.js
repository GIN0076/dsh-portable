'use strict'

// repair-junctions.js — 修复 pnpm hoisted 布局产生的"悬空 junction"。
// pnpm 11（跨卷 store 时）会在工作区包的 node_modules 里创建指向 .pnpm 虚拟 store
// 的 junction，但 hoisted 布局不生成该 store -> 全部悬空，iscc 无法打包。
// 修复：按 Node require 解析语义，找到该依赖在 hoisted 根目录的真实包，
// 用硬链接把内容物化到原位置（同一 D 盘卷，零复制）；解析不到则留空目录。
// 用法：node repair-junctions.js <srcRoot>

const fs = require('fs')
const path = require('path')
const { createRequire } = require('module')

const srcRoot = process.argv[2]
if (!srcRoot) {
  console.error('usage: node repair-junctions.js <srcRoot>')
  process.exit(2)
}

let fixed = 0
let kept = 0
let empty = 0
let links = 0
let copies = 0

function hardlinkOrCopy(srcFile, dstFile) {
  try {
    fs.linkSync(srcFile, dstFile)
    links += 1
  } catch (err) {
    if (err.code === 'EEXIST') return
    if (['EPERM', 'EXDEV', 'ENOTSUP', 'EACCES', 'UNKNOWN', 'ENAMETOOLONG', 'EINVAL'].includes(err.code)) {
      fs.copyFileSync(longPath(srcFile), longPath(dstFile))
      copies += 1
      return
    }
    throw err
  }
}

function longPath(p) {
  const resolved = path.resolve(p)
  return resolved.startsWith('\\\\?\\') ? resolved : '\\\\?\\' + resolved
}

function mkdirLong(dir) {
  if (dir.length > 240) fs.mkdirSync(longPath(dir), { recursive: true })
  else fs.mkdirSync(dir, { recursive: true })
}

// 从 resolved 文件路径向上找最近的 package.json 所在目录（包根）
function packageRootFrom(resolvedFile) {
  let dir = path.dirname(resolvedFile)
  while (true) {
    if (fs.existsSync(path.join(dir, 'package.json'))) return dir
    const parent = path.dirname(dir)
    if (parent === dir) return path.dirname(resolvedFile)
    dir = parent
  }
}

// 递归物化一个真实目录（内部若还有悬空 junction 也一并处理）
function materializeDir(srcDir, dstDir) {
  fs.mkdirSync(dstDir, { recursive: true })
  let entries
  try {
    entries = fs.readdirSync(srcDir, { withFileTypes: true })
  } catch (err) {
    console.error('[warn] cannot read:', srcDir, err.message)
    return
  }
  for (const ent of entries) {
    const src = path.join(srcDir, ent.name)
    const dst = path.join(dstDir, ent.name)
    let isLink = false
    try {
      isLink = ent.isSymbolicLink()
    } catch {
      // ignore
    }
    if (isLink) {
      // 目标包目录内部的链接：按真实目标物化；悬空则跳过（留空）
      let target = null
      try {
        target = fs.realpathSync(src)
      } catch {
        // dangling inside a real package dir: resolve via require
        try {
          const req = createRequire(path.join(srcDir, '__dangling__.cjs'))
          target = packageRootFrom(req.resolve(ent.name))
        } catch {
          target = null
        }
      }
      if (target && fs.statSync(target).isDirectory()) {
        materializeDir(target, dst)
      } else {
        mkdirLong(dst)
        empty += 1
      }
    } else if (ent.isDirectory()) {
      materializeDir(src, dst)
    } else if (ent.isFile()) {
      hardlinkOrCopy(src, dst)
    }
  }
}

function walk(nodeModulesDir) {
  let entries
  try {
    entries = fs.readdirSync(nodeModulesDir, { withFileTypes: true })
  } catch {
    return
  }
  for (const ent of entries) {
    if (ent.isSymbolicLink()) {
      const linkPath = path.join(nodeModulesDir, ent.name)
      // 作用域包：node_modules/@scope/pkg —— pkg 才是 junction
      let pkgName = ent.name
      if (ent.name.startsWith('@') && ent.isDirectory()) {
        // 作用域目录本身不处理，其下子项在递归 walk 中处理
        continue
      }
      const parentName = path.basename(nodeModulesDir)
      if (parentName.startsWith('@')) pkgName = parentName + '/' + ent.name

      let target = null
      try {
        target = fs.realpathSync(linkPath)
      } catch {
        // dangling junction —— 需要修复
      }
      if (target) {
        // 目标存在（工作区包链接等）：保留
        kept += 1
        continue
      }

      // 修复：按 Node 解析语义找真实包
      let resolvedRoot = null
      try {
        const req = createRequire(path.join(nodeModulesDir, '__repair__.cjs'))
        resolvedRoot = packageRootFrom(req.resolve(pkgName))
      } catch {
        resolvedRoot = null
      }

      fs.rmSync(linkPath, { recursive: true, force: true }) // 删除悬空链接本身
      if (resolvedRoot && fs.statSync(resolvedRoot).isDirectory()) {
        materializeDir(resolvedRoot, linkPath)
        fixed += 1
      } else {
        mkdirLong(linkPath)
        empty += 1
      }
    } else if (ent.isDirectory()) {
      walk(path.join(nodeModulesDir, ent.name))
    }
  }
}

walk(srcRoot)
console.log(JSON.stringify({ fixed, kept, empty, links, copies }, null, 2))
