# Changelog

All notable changes to DSH-Portable (the packaging layer). The upstream DeepSeek Harness version is tracked in `upstream-lock.json` / `version-manifest.json`.

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
