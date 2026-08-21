# Building DSH-Portable from source

This document walks through building the installer from scratch. It is the path the author used (Phases 1–6); adapt paths as needed.

## Prerequisites

- Windows 10/11 x64, PowerShell 5.1+ (7 is fine for most steps)
- **Node.js** ≥ 22.19 (build toolchain; the *product* carries its own bundled Node)
- **pnpm** 11.x (the repo pins `pnpm@11.7.0` via `packageManager`; corepack handles it)
- **Git** 2.x (with `core.longpaths true`: `git config --global core.longpaths true`)
- Network reachable to GitHub, or a mirror (see below). For mainland-China networks, `ghfast.top` / `ghproxy.com` prefixes work.
- [Inno Setup 7](https://jrsoftware.org/isinfo.php) (portable `iscc.exe` is used here, no install) + [7-Zip](https://www.7-zip.org) (`7zr.exe`).

## 1. Fetch and build the official source (Phase 1)

```powershell
# Mirror clone (GitHub direct may be blocked)
git clone https://ghfast.top/https://github.com/deepseek-ai/deepseek-harness.git src
cd src
git checkout dsh-v0.1.0-rc.8          # or the tag you want to package

pnpm install --frozen-lockfile
pnpm run typecheck
pnpm run build
```

> Keep `src/` **zero-modified**. All custom code lives outside it.

## 2. Stage the runtime & shell (Phase 1–2)

```powershell
# Bundled Node (same version as your build toolchain)
# copy your Node installation to runtime\node (node.exe + npm + corepack)

# Electron shell
cd shell
npm install          # pulls electron; on slow networks set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
node node_modules\electron\install.js   # ensure dist\electron.exe exists
```

## 3. Prepare the hoisted, flattened source tree (Phase 4 packaging)

pnpm's default layout uses **junctions**, which break when the tree is moved and explode Inno Setup's compiler (it follows junctions). The packaging flow:

1. In `src/`, set `nodeLinker: hoisted` in `pnpm-workspace.yaml` (pnpm 11: camelCase key in the workspace yaml) and reinstall:

```powershell
cd src
pnpm install --frozen-lockfile   # hoisted layout
```

2. Flatten workspace packages into the root `node_modules` (real directories, no junctions):

```powershell
node ..\build\flatten.js .
```

This deletes package-level `node_modules` and re-creates each workspace package under the root `node_modules` via hard links/copies.

3. Localize the built-in command descriptions (packaging-layer patch; official source stays zero-modified):

```powershell
node ..\build\localize-commands.js .
```

The official upstream hardcodes English descriptions for `compact` / `export` / `feedback` / `goal` / `permission` / `plan`. This script rewrites them to Chinese in the **built output only** (`packages/*/lib` and the flattened `node_modules/@deepseek-ai/*/lib`). It is idempotent and fails loudly if upstream changes a source string.

4. Compress into the installer payload:

```powershell
..\tools\7zr.exe a -t7z -mx=9 -mmt=on ..\staging\src.7z .
```

## 4. Assemble the staging tree

```
staging/
├── src.7z                 # from step 3
├── 7zr.exe                # build tool (7-Zip 26.02)
├── runtime/               # bundled Node
├── shell/                 # Electron shell (EXCLUDE launcher-config.json, install-log.txt)
├── addons/                # this repo's addons/
├── scripts/               # stop/clean
├── README.md
├── upstream-lock.json     # pin the upstream tag/commit you built
├── version-manifest.json  # commit + artifact SHA-256s
├── 停止DSH-Portable.cmd
└── 清理DSH-Portable.cmd
```

`version-manifest.json` / `upstream-lock.json` are produced by `addons/update-engine/update-dsh.ps1` (`-Mode apply`) or written manually; keep them truthful — the update engine verifies against them.

## 5. Compile the installer (Phase 4)

```powershell
tools\InnoSetup7\ISCC.exe /DSourceRoot=staging installer\DSH-Portable.iss
# output: dist\DSH-Portable-Setup-<version>.exe
```

Notes:

- `/DSourceRoot` is **camelCase** — `/DSOURCE_ROOT` silently falls back to the default and will build the wrong tree.
- The `.iss` contains Chinese; keep it **UTF-8 with BOM** (Inno reads it as ANSI otherwise and the Chinese text/files get garbled).
- The installer requires no admin (`PrivilegesRequired=lowest`), is bilingual, writes the data directory into `shell\launcher-config.json`, and creates shortcuts via `{userdesktop}`.

## 6. Verify the installer

```powershell
# silent install into a scratch dir
dist\DSH-Portable-Setup-0.1.0-rc.8.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="C:\tmp\dsh-inst" /DATADIR="C:\tmp\dsh-data" /NODESKTOP /NOSTARTMENU /NOAUTOSTART

# smoke: boot the web service from the installed tree
& "C:\tmp\dsh-inst\runtime\node\node.exe" "C:\tmp\dsh-inst\src\apps\cli\lib\bin.js" web --host 127.0.0.1 --port 3099
# expect HTTP 200 at http://127.0.0.1:3099, then kill it

# uninstall
"C:\tmp\dsh-inst\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

> **Caution**: a silent uninstall removes the real desktop shortcut and the `{AppId}` uninstall registry key even when the install was into a scratch dir. Always use `/NODESKTOP /NOSTARTMENU`, and back up `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{AFF08DAB-DFB3-4474-9ED0-38E83ACC6521}_is1` before uninstall tests.

## 7. Updating (for maintainers)

`addons/update-engine/update-dsh.ps1 -Mode check|apply` performs tag enumeration (multi-mirror, OpenSSL fallback, GitHub-API fallback), download, verification, staging build, atomic swap, node_modules relink, self-check and rollback. Run it from the installed tree (or with `-ProgramRoot`). The Web UI card (`dsh-update-check` plugin) and the tray menu both invoke it.

## 8. Plugin install compatibility vetting（插件装前自检）

rc.8 的 keyed 槽位强制要求 `options.key`（契约定义在官方 `packages/client/ui-slots`，例如 `settings.plugin.item`）。旧插件（如 rc.6 时代）常漏写 `key`，装进去后 HARNESS 会直接报
`Failed to load plugins … keyed slot "…" requires options.key`，整个界面不可用。另外，**任何在 app 的 `src` 里执行的 pnpm 操作都会冲坏封装好的扁平化 node_modules**（`src/node_modules/@deepseek-ai` 会被清空，启动报 `Cannot find package '@deepseek-ai/dsh-app-boot'`）。因此装插件必须走下面的自检流程。

**装前自检流程（5 步）**

1. **查资料**：读插件 README、`dsh.plugin.json`、`cordis.patch.yml` 与 client 源码，确认目标 rc 兼容性（如 README 写明的 Harness 版本）。
2. **跑检测**：用 `tools/slots-rc8.json`（从官方 slot-catalog 抽出的 rc.8 槽位契约表，keyed 槽位必须带 key）+ `tools/vet-plugin.py` 检查：manifest 声明、peer 版本 vs rc.8、client 槽位注册逐个核对（keyed 缺 key → FAIL；注册不存在的槽位 → WARN）、`cordis.patch`、构建脚本。
3. **FAIL 先修，用 pnpm 补丁机制固化**（不要直接改 `node_modules`，否则下次 pnpm install 会被覆盖）：

```yaml
# profiles/web/pnpm-workspace.yaml
patchedDependencies:
  beav-creator-dsh@0.1.2: patches/beav-creator-dsh@0.1.2.patch
```

```diff
// patches/beav-creator-dsh@0.1.2.patch
@@ -14828,6 +14828,7 @@ function apply(ctx) {
   ctx.slots.inject("settings.plugin.item", () => ctx.slots.register({
     name: "settings.plugin.item",
     id: "beav",
+    key: "beav",
     order: 40,
```

4. **安装**：把插件写进 `$DSH_HOME/profiles/web/package.json` 的 `dsh.profile.bundles` + `dependencies`，然后**只在 profile 目录**执行 `pnpm install`（`cd $DSH_HOME/profiles/web`），绝不把 pnpm 指向 app 的 `src`。
5. **验证**：重启 web 服务 → HARNESS 无报错；`dump-config` 复核；已装插件可随时跑 `vet --installed <包名>` 复查。

> 已知案例：`beav-creator-dsh@0.1.2` 注册 `settings.plugin.item` 缺 `options.key` → 用上述补丁固化。仓库内另有 `build/patch-beav-key.cjs` 作为"安装已被覆盖时"的一键应急修复。

## Troubleshooting quick hits

- `pnpm install` hits the 260-char path limit → enable `core.longpaths`, keep staging dir names short (`stg`).
- iscc hangs/explodes memory → the source tree still has junctions; run `flatten.js`.
- Installer garbles Chinese → the `.iss` lost its BOM; re-save as UTF-8 with BOM.
- `dsh plugin add "file:…"` fails with `ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND` → the path contains spaces; use a space-free path.
