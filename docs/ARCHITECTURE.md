# DSH-Portable — Architecture & Design Process

This document describes how DSH-Portable is put together, why it is shaped this way, and the full design/implementation process (Phases 1–6) with the lessons learned along the way.

> Status: implemented against DeepSeek Harness `0.1.0-rc.8` (commit `141eb6fef83422698aef7a981029e843e8161534`).

---

## 1. Overview / 概述

DSH-Portable wraps the official [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (MIT, developer preview `0.1.0-rc.8`) into a **self-contained Windows desktop application**:

- **Official source, zero modification.** `src/` is a pristine build of the upstream repository; every custom capability lives out-of-tree in `addons/`, `shell/`, `installer/`, `scripts/`, `build/`.
- **Bundled Node runtime** (`runtime/node/`) — the app does not depend on a system Node/pnpm install (verified PATH-independent).
- **Electron shell** (`shell/`) — window + tray experience; the DSH web service runs on `127.0.0.1:3080` as a child process.
- **Extension layer** (`addons/`) — update engine, audit ledger, privacy center, plugin security review, plugin market, translation layer, plugin workshop, and the "Update Check" settings card.

Data (credentials, audit, profiles) lives in a separate **data directory** (`~/.dsh` by default, configurable at install time) as a **process-level `DSH_HOME`** — the system environment is never modified.

---

## 2. Repository layout / 目录结构

```
DSH-Portable/
├── addons/                  # out-of-tree extension layer
│   ├── audit/dsh-audit.ps1          # M1: chained SHA-256 audit ledger
│   ├── update-engine/update-dsh.ps1 # M1: update engine (check/apply)
│   ├── privacy/dsh-privacy.ps1      # M1: privacy center (status/reset-id/backup/restore/cleanup)
│   ├── plugin-review/               # M2: static plugin security review
│   │   ├── review-plugin.ps1
│   │   ├── rules/rules.json         # 8 rule classes + tiers
│   │   ├── allowlist.json           # persistent RISK exemptions
│   │   ├── malicious-hashes.json    # known-malicious SHA-256 library
│   │   └── docs/m2-review.md
│   ├── market/dsh-market.ps1        # M3: plugin market CLI (search/info/install/installed)
│   ├── translate/dsh-translate.ps1  # M3: Chinese translation layer
│   ├── workshop/dsh-workshop.ps1    # M4: plugin workshop (clarify/new/test/install/list)
│   └── update-ui/                   # M5: "Update Check" settings card (dsh-update-check plugin)
│       ├── lib/index.js             # host side: GET /dsh-update/check, POST /dsh-update/apply
│       ├── src/client/              # client side: settings.section React card
│       ├── tsdown.config.ts         # client bundle build (mirrors the upstream preset)
│       └── client/client.js         # built __ModuleLoader__ bundle (committed artifact)
├── shell/                    # Electron desktop shell
│   ├── main.js               # all shell logic (tray, port probe, window state, update hooks)
│   ├── package.json
│   └── launcher-config.json  # dataDir (written by the installer; excluded from the installer)
├── installer/
│   ├── DSH-Portable.iss     # Inno Setup 7 wizard (bilingual, HKCU-only)
│   └── license.txt
├── scripts/
│   ├── stop-dsh.ps1         # kill by port 3080 + command-line tree, no residue
│   └── clean-dsh.ps1        # stop → shortcuts → optional data → silent uninstall
├── build/                   # packaging scripts (flatten.js, materialize.js, repair-junctions.js)
├── tools/                   # build-time only: portable Inno Setup 7 + 7zr (see BUILDING.md)
├── docs/                    # this document + BUILDING.md
├── 停止DSH-Portable.cmd     # stop entry
├── 清理DSH-Portable.cmd     # clean entry
└── src.7z / 7zr.exe         # produced at packaging time (src compressed for the installer)
```

The installed tree additionally contains `src/` (extracted from `src.7z` at install time) and `runtime/node/`.

---

## 3. Design process (Phases 1–6)

### Phase 1 — Base packaging

- Clone the official repo **via mirrors** (`ghfast.top` first) at tag `dsh-v0.1.0-rc.8` into `src/`, zero modifications.
- `pnpm install --frozen-lockfile` (pnpm 11.7.0 pinned via `packageManager`), `pnpm run typecheck`, `pnpm run build` — all exit 0.
- Bundle Node v24.19.0 into `runtime/node` (same major as the build toolchain, so native modules keep ABI compatibility).
- Generate `version-manifest.json` (commit + artifact SHA-256) and `upstream-lock.json` (upstream pinning).
- Smoke test: temporary `DSH_HOME` + bundled node → `dsh web` → HTTP 200 on `127.0.0.1:3080`.

**Why a manifest?** Every later update and audit can verify the build provenance (`bin.js` / `web dist/index.html` / `pnpm-lock.yaml` hashes) — a cheap supply-chain guard for a self-built distribution.

### Phase 2 — Electron desktop shell

- Port probe on `127.0.0.1:3080`: if free, spawn `dsh web` with the bundled Node; if busy, just attach (never kills an external service).
- Window: standard frame, resizable (min 640×480 configurable), **state memory** (size/position persisted in `$DSH_HOME/shell-state.json`, multi-monitor visibility correction).
- X / Alt+F4 → hide to tray, service keeps running; tray menu (Show / Exit, bilingual); Exit kills the whole process tree (`taskkill /T /F`), releases the port.
- Single-instance lock; second launch just focuses the window. First X shows a one-time balloon tip.
- Language: `DSH_LANG` → `$DSH_HOME/locale.preference` → system language.
- First-run notice: "Unofficial Build & Privacy" dialog, shown once (`noticeShown` flag).
- `打开浏览器版.cmd`: bundled-node web + open default browser (console-window lifecycle).

**Update hooks** (added later): the shell detects a `.updating` marker next to the app root (written by the update-apply route) and exits quietly instead of showing the "service exited unexpectedly" error box when an update stops the web service on purpose.

### Phase 3 — Extension layer (M1–M4, later M5)

See §4 for module details. All modules are CLI tools out-of-tree; every install path passes the M2 review; every state change is written to the audit ledger.

### Phase 4 — Installer (Inno Setup 7)

- Portable `iscc.exe` (no registry writes, build-time only).
- Bilingual wizard (中文/English), license + disclaimer (declining aborts), install dir (default `D:\Software Installation\DSH-Portable`), options (desktop shortcut default-on, Start Menu optional, auto-start default-off), advanced page (data directory, process-level `DSH_HOME`).
- Packaging strategy: pnpm `nodeLinker: hoisted` reinstall → `build/flatten.js` flattens workspace packages into the root `node_modules` (no junctions — iscc follows junctions and would explode) → `src` compressed into `src.7z` (~238 MB) → installer ships `src.7z` + runtime/shell/addons/scripts → install extracts with `7zr x` and deletes the archive → uninstall deletes `{app}\src` via `filesandordirs`.
- Shortcuts use `{userdesktop}` (known-folder API, follows desktop redirection/OneDrive); failures are logged (`install-log.txt`), never fatal.
- **Uninstall safety (fixed later)**: the uninstaller now deletes **only** shortcuts this install actually created (recorded in `install-log.txt` by `CreateShortcut`), so a setup test run in another directory can never touch the real desktop/Start-Menu shortcuts.

### Phase 5 — Stop / clean scripts

- `停止DSH-Portable.cmd` → `scripts/stop-dsh.ps1`: kill by port 3080 listener **and** by command-line match on the app root (electron.exe/node.exe), `taskkill /T /F`, no residue.
- `清理DSH-Portable.cmd` → `scripts/clean-dsh.ps1`: stop → remove desktop/Start-Menu shortcuts → optionally delete the data directory (`-DeleteData` / `-KeepData` / interactive) → silent uninstall via `unins*.exe`.

### Phase 6 — Delivery close-out

- README (usage), backup→restore drill, PATH-independence verification (minimal PATH still boots), custom-data-directory verification, uninstall-no-residue verification.

---

## 4. Extension modules (M1–M5)

### M1 — Update engine (`addons/update-engine/update-dsh.ps1`)

`check` and `apply` modes; the primary update path is **source update** (self-built, no hosted binaries):

1. **Enumerate upstream tags** with a resilience chain: configured mirror → `ghfast.top` → `ghproxy` → GitHub direct; each `git ls-remote` retries with the OpenSSL backend when the default (schannel) TLS fails; **if git is absent entirely**, falls back to the GitHub API via the bundled Node (`Get-UpstreamTagsViaApi`, unauthenticated 60 req/h is plenty for version checks).
2. **Download** the tag zip through the same multi-mirror chain; `.NET` download failures fall back to the bundled Node (OpenSSL/undici) download.
3. **Verify**: extract, compare `package.json` version against the tag; reject zip < 1 MB (proxy error page heuristic).
4. **Build in a staging dir** (`stg`, short name to dodge the 260-char path limit): `pnpm install --frozen-lockfile` (pinned pnpm via corepack shim), `typecheck`, `build`.
5. **Atomic swap**: `src` → `src.bak` (one rollback kept), staging → `src`; verify the CLI bin exists, else roll back.
6. **Re-link node_modules at the final path** — pnpm junctions carry absolute paths that break on `Move-Item`, so the final `node_modules` is reinstalled at the final location.
7. **Self-check**: boot the new build on the same port with a temp `$DSH_HOME`, require HTTP 200, ensure the port is released after kill; on failure, restore `src.bak`.
8. **Update manifests** (`version-manifest.json`, `upstream-lock.json`) and the audit ledger at each step.
9. Before anything: **back up `$DSH_HOME`** via `robocopy /XJ` (junctions skipped).

End-to-end `apply` was exercised repeatedly during development, including a real self-check failure → automatic rollback.

### M1 — Audit ledger (`addons/audit/dsh-audit.ps1`)

- JSONL ledger at `$DSH_HOME/audit/audit.jsonl`: seq/time/operator/type/pluginId/detail/before/after/result/evidence/session.
- **SHA-256 chaining** (`prevHash` + `selfHash`): tampering breaks the chain and `verify` reports it.
- Commands: `log / list / filter / timeline / export / verify / cleanup / review`.

### M1 — Privacy center (`addons/privacy/dsh-privacy.ps1`)

- Telemetry status (default DISABLED), anonymous-ID view/reset, backup (dir or zip, `robocopy /XJ`), restore, audit cleanup. Credentials are never part of backups by design choice of paths.

### M2 — Plugin security review (`addons/plugin-review/`)

Static review before any plugin install:

- **RED** (reject): DYN-EXEC, OBFUSCATION-B64, CRED-READ, OOB-WRITE, BINARY-PAYLOAD, MALICIOUS-HASH (against a local SHA-256 library).
- **RISK** (must be confirmed): INSTALL-SCRIPT, NET-EGRESS, CHILD-PROC, SESSION-READ, FILE-WRITE, DEP-VULN (npm audit).
- **INFO** (allowed, recorded): ENV-ACCESS, FILE-READ, MINIFIED, loopback-only network downgrades.
- Exit codes: `0` allow / `2` confirm needed (approve by rule id or allowlist) / `3` reject. Evidence carries file:line. Optionally emits a runtime-gate contract for the official approval API.
- Explicitly scoped as a **best-effort static layer, not a sandbox**.

### M3 — Plugin market (`addons/market/dsh-market.ps1`)

- `search` (npmmirror registry API), `info` (license + deps), `install` (npm pack → **M2 gate** → official `dsh plugin add`; `-Approve`, `-DryRun`, `-LocalPath` review mode), `installed`.
- Node/npm resolution: bundled `runtime\node` first, then system Node, then PATH; npm cache is redirected to `$DshHome\.npm-cache` for restricted environments. `.NET` registry fetches fall back to the bundled Node (OpenSSL).

### M3 — Translation layer (`addons/translate/dsh-translate.ps1`)

- Dictionary overrides aligned with the official locale lookup chain (`ns → common → zh → key`), per-plugin forced translation, model translation with local cache (API key only from environment), `export-override` for runtime plugins.

### M4 — Plugin workshop (`addons/workshop/dsh-workshop.ps1`)

- `clarify` (missing-field question list), `new` (generates a Cordis plugin: `ctx.commands.register` + `ctx.on` + tool/service stubs), `test` (syntax + apply export + **M2 review**), `install` (backup profile → M2 gate → official `dsh plugin --profile web add "file:<dir>"` → automatic profile restore on failure), `list`.
- Real install E2E verified, including a forced-failure rollback that restored the profile byte-for-byte.

### M5 — Update Check UI (`addons/update-ui/`, plugin `dsh-update-check`)

A settings-page card ("更新检查") that runs the update engine from the Web UI:

- Host side (`lib/index.js`): loopback-only routes — `GET /dsh-update/check` (runs `update-dsh.ps1 check`, returns JSON), `POST /dsh-update/apply` (writes a `.updating` marker, spawns a **detached** `apply -KillRunning` process, returns immediately).
- Client side: a `settings.section` React card with a "Check" button, and an "Update now" button when an update is available (confirm dialog → POST → "update started" state).
- Built as a standard dsh plugin (`__ModuleLoader__` bundle via tsdown, mirroring the upstream client preset); installs with `dsh plugin --profile web add "file:<path>"`.
- The Electron shell exits quietly when `.updating` is present (see Phase 2).

---

## 5. Security model

- **Loopback-only HTTP** for every custom route (`/dsh-update/*`), origin-checked against `127.0.0.1`/`localhost`.
- **M2 static review gate** before any plugin install; RED rejects, RISK requires explicit per-rule approval.
- **Chained audit ledger** makes tampering visible; update/build events are all logged.
- **Credentials never leave the data directory**; translation keys are environment-variable-only; backups exclude junctions and are user-managed (README warns against uploading the data dir).
- **No admin rights**: `PrivilegesRequired=lowest`, HKCU-only, no services, no auto-start unless chosen.
- **Known boundary**: M2 is static analysis, not a sandbox — runtime plugin behavior relies on the official harness's own approval mechanisms.

---

## 6. Design decisions & trade-offs

| Decision | Rationale |
|---|---|
| Zero-modification `src/` + out-of-tree `addons/` | Upstream updates stay clean; custom layer is versionable and re-appliable |
| Source updates over hosted binaries | No hosting/infra needed; the build pipeline makes it reproducible; rollback via `src.bak` |
| Electron shell | Familiar desktop UX (tray, window state) without web-server licensing concerns |
| Hoisted+flattened node_modules packaging | pnpm junctions are absolute and break when moved; flat tree is relocatable and iscc-safe |
| `src.7z` + 7zr extraction at install | 701 MB installer ships 1.5 GB source compressed; `Compression=none` keeps install fast |
| `launcher-config.json` dataDir | Process-level `DSH_HOME`; no system env mutation; uninstall keeps data |
| Multi-mirror + TLS fallback chains | GitHub is blocked/partial in China; schannel can be broken on some systems; OpenSSL backend + GitHub API cover both |

## 7. Known limitations

- Installer ~700 MB; installed tree ~2 GB (Electron + source + node_modules).
- `apply` rebuilds from source: can take 30+ minutes on slow machines.
- Update engine needs `git` for the primary path (falls back to GitHub API when missing) and needs network for downloads.
- The M2 review regexes are heuristic; treat as a review aid, not a guarantee.
- The plugin market requires network access to npm registries.

## 8. Notable lessons (condensed)

- **PowerShell 5.1**: `.ps1` files containing Chinese **must be UTF-8 with BOM**; native stderr under `$ErrorActionPreference='Stop'` is an exception — judge native commands by `$LASTEXITCODE` with `EAP=Continue`.
- **Long paths**: `LongPathsEnabled=0` breaks `Remove-Item -Recurse` on deep node_modules — use the bundled Node's `fs.rmSync`. Keep staging dir names short (`stg`).
- **pnpm junctions are absolute**: after any `Move-Item` of a built tree, reinstall `node_modules` at the final path.
- **iscc follows junctions**: never point it at a pnpm-linked tree; flatten first.
- **`Start-Process -ArgumentList` splits on spaces**: quote paths manually.
- **Setup uninstall tests pollute real user state**: the uninstaller (by design) touches the real desktop shortcuts and the `{AppId}` uninstall registry key even when run from a test directory. Always test with `/NODESKTOP /NOSTARTMENU`, back up the uninstall registry key, or use an isolated environment.
- **Quotes get eaten** when PowerShell passes arguments to native exes (npm/node/powershell): write embedded scripts without quote characters (`String.fromCharCode`), or use `--%`.
- **`dsh plugin add "file:<path>"` breaks on spaces**: keep the plugin path space-free.
- **`for ... in` is not supported** in Inno Setup Pascal Script — use index loops.

## 9. Roadmap / possible follow-ups

- Prebuilt-binaries update mode (download staged builds instead of building from source).
- A `启动DSH-Portable.cmd` launcher (browser mode without the Electron shell).
- Installer validation script with uninstall-registry backup.
- More runtime enforcement for plugins (bridge to the official approval API beyond the static review).
