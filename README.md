# DSH-Portable

> ⭐ **If DSH-Portable helps you, please give it a star — it helps others find it. / 如果这个项目对你有帮助，欢迎点个 Star 支持！**

**A self-contained Windows desktop build of [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)** — Electron shell + bundled Node runtime, running the official MIT-licensed agent framework on `127.0.0.1` with zero system dependencies. Built for personal use, now open-sourced.

**基于 DeepSeek 官方 MIT 开源代码构建的非官方 Windows 桌面发行版**：Electron 桌面壳 + 内置 Node，无需安装 Node/pnpm，装完即用。

> ⚠️ **Unofficial build.** This software is an independent packaging of DeepSeek's official MIT-licensed open-source code. It is **not affiliated with, endorsed by, or supported by DeepSeek**. Provided "AS IS" without warranty; users bear all risks and API costs.
>
> **非官方发行版**：与 DeepSeek 无关联、未获背书；按现状提供，不提供任何担保；使用风险与 API 费用由使用者自担。

---

## ✨ Features / 特性

| | Feature | 说明 |
|---|---|---|
| 🖥 | **Electron desktop shell** | Tray icon, window-state memory, single-instance lock, first-run notice. X = minimize to tray, service keeps running |
| 📦 | **Bundled Node runtime** | No system Node/pnpm needed; PATH-independent (verified) |
| 🔄 | **One-click update engine** | Check via tray or the Web settings "Update Check" card; multi-mirror downloads (ghfast.top → ghproxy → GitHub direct), schannel→OpenSSL fallback, GitHub-API fallback when git is missing, atomic swap with rollback, self-check (HTTP 200 + port released), automatic `$DSH_HOME` backup |
| 🛡 | **Plugin security review (M2)** | Static review before install: 8 rule classes, malicious SHA-256 library, allowlist, evidence with line numbers; RED→reject / RISK→confirm / INFO→allow |
| 🧾 | **Chained audit log** | JSONL ledger with SHA-256 chaining (tamper-evident): seq/time/operator/type/plugin/detail/before/after/result/evidence |
| 🔒 | **Privacy center** | Telemetry off by default, anonymous-ID view/reset, backup/restore, audit cleanup |
| 🛒 | **Plugin market** | Integrated [dshmarket](https://github.com/dsh-market/dsh-market) — 1250+ community plugins, one-click install (still gated by M2 review) |
| 🌐 | **Network resilience** | Works in regions where GitHub is blocked (China-friendly mirrors) |
| 🗣 | **Bilingual** | Chinese/English installer wizard, shell, docs |

## 📦 Installation / 安装

Download the installer from [Releases](../../releases) (`DSH-Portable-Setup-0.1.2-alpha.1.exe`, ~747 MB):

1. Run the installer. Language follows the system (中文 / English), switchable.
2. Read the license & disclaimer — **declining aborts the install**.
3. Choose the install directory (default `D:\Software Installation\DSH-Portable`; SSD recommended).
4. Options: desktop shortcut (default on), Start Menu shortcut (optional), auto-start with Windows (default off).
5. **Advanced: data directory** (default `~/.dsh`) — a **process-level** `DSH_HOME`, no system environment changes.
6. Optionally launch immediately.

**First launch** shows a one-time "Unofficial Build Notice & Privacy" dialog. Credentials are stored only in the local data directory (`~/.dsh\.credentials.yaml`); telemetry is off by default.

**Tray behavior**: clicking X hides to tray (service keeps running); right-click the tray icon → Show / Exit. First hide shows a one-time balloon tip.

**Stop / Uninstall**: `停止DSH-Portable.cmd` (stop processes, release port, no residue) and `清理DSH-Portable.cmd` (remove shortcuts → optionally delete data → silent uninstall).

## 🏗 Repository layout / 仓库结构

```
DSH-Portable/
├── packages/        # Out-of-tree extension layer (not part of official src)
│   ├── audit/          # M1 chained audit ledger
│   ├── update-engine/  # M1 update engine (check/apply, multi-mirror, rollback)
│   ├── privacy/        # M1 privacy center
│   ├── plugin-review/  # M2 static plugin security review
│   ├── plugin-market/  # M3 plugin market CLI (search/info/install via M2 gate)
│   ├── translation/    # M3 Chinese translation layer
│   ├── plugin-workshop/ # M4 plugin workshop (generate → review → install)
│   └── update-ui/      # M5 "Update Check" settings card (dsh-update-check plugin)
├── apps/desktop-shell/ # Electron desktop shell (main.js + package.json)
├── installer/         # Inno Setup wizard (DSH-Portable.iss)
├── scripts/           # shared maintenance scripts
│   └── windows/       # Windows cmd wrappers
├── build/             # packaging scripts (flatten.js, materialize.js, …)
├── docs/              # architecture & building docs
└── tools/             # (build-only) portable Inno Setup 7 + 7zr — see docs/BUILDING.md
```

> `src/` (the official DeepSeek Harness source tree) is **not** committed — see [docs/BUILDING.md](docs/BUILDING.md). The official clone is kept **zero-modified**; all custom work lives in `packages/`, `apps/desktop-shell/`, `installer/`, `scripts/`, `build/`.

## 📋 Update Interruption Notice / 更新中止说明

> 2026-08-20：RC7 → RC8 自动更新中止的直接原因是官方更新器在当前 Windows 权限/文件系统环境下**处理临时目录失败**——不是硬件问题、不是 RC7 无法升级 RC8、不是数据损坏、也不是依赖修复回退。详见 [docs/rc8-update-interruption.md](docs/rc8-update-interruption.md)。
>
> 由于官方更新器在当前 Windows 环境下无法可靠完成自动升级，**本项目现已改为直接封装发布 RC8 安装包**（手工构建、验证后提供），不再依赖官方更新器自动升级。给您带来不便，请谅解。

## 🔧 Development / 开发

- **Architecture**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — full design process (Phase 1–6), module docs, security model, and the history of lessons learned.
- **Build from source**: [docs/BUILDING.md](docs/BUILDING.md) — fetch official source → `pnpm install --frozen-lockfile` → typecheck → build → package with Inno Setup.

## 📜 Licensing / 许可

- This project's own code (`packages/`, `apps/desktop-shell/`, `installer/`, `scripts/`, `build/`, docs): **MIT** — see [LICENSE](LICENSE).
- Upstream: [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) is MIT. Electron, Node.js, Inno Setup, 7-Zip and third-party plugins each carry their own licenses — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
- No third-party plugins are bundled in this repository; the plugin market fetches them at install time under their own licenses.

## 🙏 Credits / 借鉴

Design inspirations (ideas only, no code copied) from [Links2008](https://github.com/Links2008) (update model, upstream locking), [xiincs](https://github.com/xiincs) (checksums, lean packaging), [hairyf/deepseek-harness-desktop](https://github.com/hairyf/deepseek-harness-desktop) (concept only — its non-commercial license is incompatible, so nothing was taken), [dsh-market](https://github.com/dsh-market/dsh-market) and the DeepSeek Harness community. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the full license rundown. Built with the help of Codex.
