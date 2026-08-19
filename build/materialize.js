'use strict'

// materialize.js — 把含 junction 的 pnpm 工作区树展开为"完全无 junction 的真实目录树"。
// 用法：node materialize.js <源根> <目标根>
//
// 背景：pnpm 工作区（isolated 或 hoisted）的 node_modules 是 junction 组成的 DAG，
//       Inno Setup 的 iscc 会跟读 junction，遇到工作区依赖环（vendor/* 互链）会无限展开。
//       且安装后 junction 的绝对路径会失效。
// 策略：
//   - 真实文件一律硬链接（同卷，零字节复制）；目标根必须与源根同卷。
//   - 每个唯一 junction 目标（canonical）只完整展开一次，之后所有指向它的位置
//     从 stage 内已展开目录做"硬链接复制"（复刻目录结构，不重复计算）。
//   - 环（目标正在展开中）-> 在该位置留空目录占位，避免无限递归。
//   - 悬空 junction -> 用 Node require 解析语义找真实包；找不到则留空目录。

const fs = require('fs')
const path = require('path')
const { createRequire } = require('module')

const srcRoot = process.argv[2]
const dstRoot = process.argv[3]
if (!srcRoot || !dstRoot) {
  console.error('usage: node materialize.js <srcRoot> <dstRoot>')
  process.exit(2)
}

const inProgress = new Set() // canonical 小写路径，正在展开中（环检测）
const done = new Map() // canonical 小写路径 -> stage 中已展开目录

let links = 0
let copies = 0
let dirs = 0
let junctions = 0
let placeholders = 0
let replicated = 0

function canonicalKey(p) {
  try {
    return fs.realpathSync(p).toLowerCase()
  } catch {
    return path.resolve(p).toLowerCase()
  }
}

function longPath(p) {
  const resolved = path.resolve(p)
  return resolved.startsWith('\\\\?\\') ? resolved : '\\\\?\\' + resolved
}

function hardlinkOrCopy(srcFile, dstFile) {
  const tooLong = srcFile.length > 240 || dstFile.length > 240
  if (!tooLong) {
    try {
      fs.linkSync(srcFile, dstFile)
      links += 1
      return
    } catch (err) {
      if (err.code === 'EEXIST') return
      if (!['EPERM', 'EXDEV', 'ENOTSUP', 'EACCES', 'UNKNOWN', 'ENAMETOOLONG', 'EINVAL'].includes(err.code)) throw err
    }
  }
  fs.copyFileSync(longPath(srcFile), longPath(dstFile))
  copies += 1
}

function mkdirLong(dir) {
  if (dir.length > 240) fs.mkdirSync(longPath(dir), { recursive: true })
  else fs.mkdirSync(dir, { recursive: true })
}

function packageRootFrom(resolvedFile) {
  let dir = path.dirname(resolvedFile)
  while (true) {
    if (fs.existsSync(path.join(dir, 'package.json'))) return dir
    const parent = path.dirname(dir)
    if (parent === dir) return path.dirname(resolvedFile)
    dir = parent
  }
}

// 从真实源目录展开（源里可能有 junction）
function materializeSource(srcDir, dstDir) {
  mkdirLong(dstDir)
  dirs += 1
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
      junctions += 1
      materializeLink(src, dst, srcDir, ent.name)
    } else if (ent.isDirectory()) {
      materializeSource(src, dst)
    } else if (ent.isFile()) {
      hardlinkOrCopy(src, dst)
    }
  }
}

// 把 stage 中已展开（无 junction）的目录复刻到新位置：只建目录+硬链接文件
function replicateDir(stageSrcDir, dstDir) {
  mkdirLong(dstDir)
  dirs += 1
  replicated += 1
  let entries
  try {
    entries = fs.readdirSync(stageSrcDir, { withFileTypes: true })
  } catch {
    return
  }
  for (const ent of entries) {
    const src = path.join(stageSrcDir, ent.name)
    const dst = path.join(dstDir, ent.name)
    if (ent.isDirectory()) replicateDir(src, dst)
    else if (ent.isFile()) hardlinkOrCopy(src, dst)
  }
}

function materializeLink(linkPath, dstDir, parentSrcDir, name) {
  let target = null
  try {
    target = fs.realpathSync(linkPath)
  } catch {
    // 悬空 junction：按 Node 解析语义找真实包
    try {
      let pkgName = name
      if (path.basename(parentSrcDir).startsWith('@')) pkgName = path.basename(parentSrcDir) + '/' + name
      const req = createRequire(path.join(parentSrcDir, '__repair__.cjs'))
      target = packageRootFrom(req.resolve(pkgName))
    } catch {
      target = null
    }
  }

  if (!target) {
    mkdirLong(dstDir)
    placeholders += 1
    return
  }

  let st
  try {
    st = fs.statSync(target)
  } catch {
    mkdirLong(dstDir)
    placeholders += 1
    return
  }

  if (st.isFile()) {
    hardlinkOrCopy(target, dstDir)
    return
  }
  if (!st.isDirectory()) {
    mkdirLong(dstDir)
    placeholders += 1
    return
  }

  const key = canonicalKey(target)
  if (inProgress.has(key)) {
    // 环：留空占位，Node 解析会沿父链继续向上找
    mkdirLong(dstDir)
    placeholders += 1
    return
  }
  const existing = done.get(key)
  if (existing) {
    // 已完整展开过：从 stage 内复刻（同卷硬链接，零字节）
    replicateDir(existing, dstDir)
    return
  }
  inProgress.add(key)
  materializeSource(target, dstDir)
  done.set(key, dstDir)
  inProgress.delete(key)
}

materializeSource(srcRoot, dstRoot)
console.log(JSON.stringify({ dirs, links, copies, junctions, placeholders, replicated }, null, 2))
