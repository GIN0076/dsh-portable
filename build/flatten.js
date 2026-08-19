'use strict'

// flatten.js — 把 hoisted 的 pnpm 工作区树平面化，供安装包打包：
//  1. 删除所有"包级 node_modules"（其内容只是 junction / 指向根目录的重复链接）。
//  2. 把全部工作区包（vendor/*、packages/*/*、apps/*、native/... 等）以真实目录
//     （同卷硬链接）平铺进根 node_modules，按 package.json 的 name 落位。
//  3. 结果：全树无 junction，Node 解析一律走根 node_modules。
// 用法：node flatten.js <srcRoot>

const fs = require('fs')
const path = require('path')

const srcRoot = process.argv[2]
if (!srcRoot) {
  console.error('usage: node flatten.js <srcRoot>')
  process.exit(2)
}

const rootNm = path.join(srcRoot, 'node_modules')
let removedNm = 0
let links = 0
let copies = 0
let pkgs = 0

function longPath(p) {
  const resolved = path.resolve(p)
  return resolved.startsWith('\\\\?\\') ? resolved : '\\\\?\\' + resolved
}

function mkdirLong(dir) {
  if (dir.length > 240) fs.mkdirSync(longPath(dir), { recursive: true })
  else fs.mkdirSync(dir, { recursive: true })
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

// 收集所有名为 node_modules 的目录（不含根），删除
function collectNodeModules(dir, out) {
  let entries
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const ent of entries) {
    if (!ent.isDirectory() && !ent.isSymbolicLink()) continue
    const p = path.join(dir, ent.name)
    if (ent.name === 'node_modules') {
      if (path.resolve(p) !== rootNm) out.push(p)
    } else if (ent.isDirectory()) {
      collectNodeModules(p, out)
    }
  }
}

// 复制包目录（排除其 node_modules）到目标
function copyPackage(srcDir, dstDir) {
  let entries
  try {
    entries = fs.readdirSync(srcDir, { withFileTypes: true })
  } catch {
    return
  }
  for (const ent of entries) {
    if (ent.name === 'node_modules') continue
    const src = path.join(srcDir, ent.name)
    const dst = path.join(dstDir, ent.name)
    if (ent.isDirectory()) {
      mkdirLong(dst)
      copyPackage(src, dst)
    } else if (ent.isFile()) {
      hardlinkOrCopy(src, dst)
    }
  }
}

// 1) 删除所有包级 node_modules
const nmDirs = []
collectNodeModules(srcRoot, nmDirs)
for (const nm of nmDirs) {
  try {
    fs.rmSync(nm, { recursive: true, force: true, maxRetries: 5, retryDelay: 300 })
    removedNm += 1
  } catch (err) {
    console.error('[warn] cannot remove:', nm, err.message)
  }
}

// 清掉根 node_modules/.pnpm（只剩 lock.yaml 元数据）
try {
  fs.rmSync(path.join(rootNm, '.pnpm'), { recursive: true, force: true, maxRetries: 5, retryDelay: 300 })
} catch (err) {
  console.error('[warn] cannot remove .pnpm:', err.message)
}

// 2) 把工作区包平铺到根 node_modules
const wsDirs = []
for (const pattern of [
  'vendor',
  'packages',
  'apps',
  'native/landlock-run',
  'native/landlock-run/packages',
  'website',
  'examples',
  'python/sdk-runtime',
]) {
  const base = path.join(srcRoot, pattern)
  if (fs.existsSync(base)) {
    if (fs.statSync(base).isDirectory() && fs.existsSync(path.join(base, 'package.json'))) {
      wsDirs.push(base)
    } else {
      try {
        for (const ent of fs.readdirSync(base, { withFileTypes: true })) {
          if (!ent.isDirectory()) continue
          const sub = path.join(base, ent.name)
          if (fs.existsSync(path.join(sub, 'package.json'))) wsDirs.push(sub)
        }
      } catch {
        // ignore
      }
    }
  }
}

// 逐级展开 packages/*/*（两层层级）与 native/landlock-run/packages/*
function expandTwoLevel(base) {
  let entries
  try {
    entries = fs.readdirSync(base, { withFileTypes: true })
  } catch {
    return
  }
  for (const ent of entries) {
    if (!ent.isDirectory()) continue
    const sub = path.join(base, ent.name)
    let subs
    try {
      subs = fs.readdirSync(sub, { withFileTypes: true })
    } catch {
      continue
    }
    for (const s of subs) {
      if (!s.isDirectory()) continue
      const leaf = path.join(sub, s.name)
      if (fs.existsSync(path.join(leaf, 'package.json'))) wsDirs.push(leaf)
    }
  }
}
expandTwoLevel(path.join(srcRoot, 'packages'))
expandTwoLevel(path.join(srcRoot, 'native', 'landlock-run', 'packages'))

const seen = new Set()
for (const pkgDir of wsDirs) {
  let name
  try {
    name = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8')).name
  } catch {
    continue
  }
  if (!name || seen.has(name)) continue
  seen.add(name)
  const rel = name.split('/')
  const dst = path.join(rootNm, ...rel)
  mkdirLong(dst)
  copyPackage(pkgDir, dst)
  pkgs += 1
}

console.log(JSON.stringify({ removedNm, pkgs, links, copies }, null, 2))
