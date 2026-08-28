# Changelog

All notable changes to DSH-Portable (the packaging layer). The upstream DeepSeek Harness version is tracked in `upstream-lock.json` / `version-manifest.json`.

## 0.1.2-alpha.1 (2026-08-28)

### Upstream rebase onto alpha.1

- **Upstream**: rebased onto official `deepseek-ai/deepseek-harness` `dsh-v0.1.2-alpha.1` (commit `cd5ef81`); built on Windows; `pnpm install --frozen-lockfile` / `build` all green (hoisted + flattened packaging with `pnpm@11.7.0`); 218 client artifacts recorded.
- **Security hardening (dev configs)** re-applied to upstream `src/vitest.config.ts` (path-existence check) and `src/website/.vitepress/config.ts` (`llms.txt` plain-text download).
- **In-app auto-update remains disabled**: GUI entry points (tray item / Web settings card) still hidden; `packages/update-engine/update-dsh.ps1` retained for advanced users; `packages/update-ui` excluded from install.
- **Installer**: `DSH-Portable-Setup-0.1.2-alpha.1.exe` (~747 MB, SHA-256 `20e2996b747fc019cee4c899612582c7361151e3c595d59f22da68dc35861f74`), verified: silent install, installed tree boot (bundled Node, HTTP 401 expected due to upstream `?token=` auth).

## 0.1.1-rc.2 (2026-08-28)

### Upstream rebase + repository restructure + packaging fixes

- **Upstream**: rebased onto official `deepseek-ai/deepseek-harness` `dsh-v0.1.1-rc.2` (commit `b150a551`); built on Windows; `pnpm install --frozen-lockfile` / `typecheck` / `build` all green (hoisted + flattened packaging with `pnpm@11.7.0`).
- **Repository layout**: `shell/` → `apps/desktop-shell/`; `addons/*` → `packages/*` (audit, plugin-market, plugin-review, plugin-workshop, privacy, translation, update-engine, update-ui); Windows cmd wrappers → `scripts/windows/`.
- **Fix `build/flatten.js`**: `path.resolve(p) !== rootNm` compared an absolute path against a relative one, so the root `node_modules` was always deleted and third-party dependencies were dropped from `src.7z`. Now compares `path.resolve(...).toLowerCase()` on both sides.
- **Fix installer** (`installer/DSH-Portable.iss`): leftover `shell\` paths for `launcher-config.json` write/delete, shortcut params, and autostart; added `scripts\stop-dsh.ps1` / `clean-dsh.ps1` copy so the `scripts\windows\*.cmd` wrappers resolve.
- **Manifests**: `version-manifest.json` / `upstream-lock.json` pinned to `dsh-v0.1.1-rc.2` with artifact SHA-256.
- **Docs**: added `docs/RELEASE-CHECKLIST.md`; aligned `docs/BUILDING.md` with ISCC 7 (`--define=SourceRoot=<abs>`); updated README/ARCHITECTURE to the new layout and version.
- **Security hardening (dev configs)**: replaced the `spawnSync` pwsh probe in `src/vitest.config.ts` with a path-existence check; served `llms.txt` through a plain-text download helper in `src/website/.vitepress/config.ts`.
- **Installer**: `DSH-Portable-Setup-0.1.1-rc.2.exe` (~728 MB, SHA-256 `16a2158405912491a5a356e00b9f184594bd33d1101179dce904270f696c2b97`), verified: silent install, installed tree boot (HTTP 200 with bundled Node), stop script, uninstall keeps data dir, plugin-review gate, update check.
- **Security notes**: added `docs/SECURITY.md` recording the Mimosa deep scan result — packaging-layer code has no real high-severity finding (the single hit was a false positive); the 75 static findings all belong to upstream `src/`; scan itself ran `partial/inconclusive`, so this build does **not** claim to have passed a full security audit.
- **In-app auto-update gated by default**: real-machine testing of `0.1.1-rc.2 → 0.1.2-alpha.1` showed three "update" clicks produced zero `update.apply` events (Electron's Job Object kills the detached updater on `app.quit()`). The GUI entry points (tray "Check for updates", Web "更新检查" card) are now hidden unless `DSH_ENABLE_UPDATE=1` or `"enableUpdate": true` in `apps/desktop-shell/launcher-config.json`. `packages/update-engine/update-dsh.ps1` remains for advanced users; installer excludes `packages/update-ui` so the card does not render.

## 0.1.0-rc.8 (2026-08-20)

### Upstream rebase + shell polish

- **Upstream**: rebased onto official `deepseek-ai/deepseek-harness` `dsh-v0.1.0-rc.8` (commit `141eb6f`), built on Windows, installed and verified (web HTTP 200, Electron smoke).
- **Shell**: `dsh web` is launched with `--no-open` so the desktop app no longer opens an extra browser tab on start.
- **Installer**: `DSH-Portable-Setup-0.1.0-rc.8.exe` (~727 MB).
- **发布方式调整**：因官方更新器在 Windows 下无法可靠自动升级，本次 RC8 改为直接封装发布（手工构建 + 验证），不再依赖自动更新器，请用户谅解。

## 0.1.0-rc.7 (2026-08-18 → 2026-08-19)

### Initial release — full packaging (Phases 1–6)

- **Phase 1** Base packaging: mirrored clone of official `deepseek-ai/deepseek-harness` at `dsh-v0.1.0-rc.7` (commit `99f6f02f`), zero-modified; `pnpm install --frozen-lockfile` / `typecheck` / `build` all green; bundled Node v24.19.0; `version-manifest.json` + `upstream-lock.json` with SHA-256 provenance.
- **Phase 2** Electron desktop shell: tray, window-state memory, single-instance, port probe (3080), first-run notice, bilingual, browser-mode cmd.
- **Phase 3** Extension layer:
  - M1 update engine (source update, atomic swap, rollback, self-check, auto data backup)
  - M1 chained audit ledger (SHA-256)
  - M1 privacy center
  - M2 plugin security review (8 rule classes, malicious-hash library, allowlist)
  - M3 plugin market CLI (M2-gated installs)
  - M3 Chinese translation layer
  - M4 plugin workshop (generate → review → install with rollback)
- **Phase 4** Inno Setup installer: bilingual, HKCU-only, custom data dir, hoisted+flattened packaging via `src.7z`, silent-install verified.
- **Phase 5** Stop/clean scripts (port + command-line process tree kill, no residue).
- **Phase 6** README, backup→restore drill, PATH-independence verified, custom data dir verified, uninstall-no-residue verified.

### Hardening pass (same day)

- **P0 portability**: `market`/`plugin-review` no longer hard-code `C:\Program Files\nodejs` — bundled `runtime\node` first, system Node, then PATH; npm cache redirected to `$DshHome\.npm-cache`.
- **P2 encoding**: addons README restored from GBK-mangled copy to the full UTF-8 source; scripts saved as UTF-8 with BOM (PS 5.1 Chinese-safety); README examples get `-ExecutionPolicy Bypass`.
- **P1 network resilience**:
  - Update engine: multi-mirror tag enumeration (`$Mirror → ghfast.top → ghproxy → GitHub direct`), schannel→OpenSSL git fallback, GitHub-API fallback when git is missing, `.NET` download fallback to bundled Node (OpenSSL).
  - Plugin market: registry fetches fall back to bundled Node.
- **M5 Update Check UI**: new `dsh-update-check` plugin — settings-page card with check + one-click apply (loopback-only routes `/dsh-update/check`, `/dsh-update/apply`); `.updating` marker so the shell exits quietly during updates.
- **Installer uninstall safety**: uninstaller now deletes only shortcuts the install actually created (recorded in `install-log.txt`), preventing setup-test runs from removing real shortcuts.
- **Repackaged**: `DSH-Portable-Setup-0.1.0-rc.7.exe` (~701 MB) containing all fixes.
