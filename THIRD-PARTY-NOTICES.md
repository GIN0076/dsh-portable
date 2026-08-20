# Third-Party Notices

DSH-Portable is a packaging of third-party software. Each component below retains its own license; this file lists them for compliance. This project does not modify or redistribute the DeepSeek Harness source tree — it is fetched and built at packaging time (see `docs/BUILDING.md`).

## Bundled / built from

| Component | Version | License | Notes |
|---|---|---|---|
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | 0.1.0-rc.8 | MIT | The agent framework being packaged. Fetched from upstream, built, kept **zero-modified**. |
| [Node.js](https://nodejs.org) | v24.19.0 | MIT | Bundled into `runtime/node/` for PATH independence. |
| [Electron](https://www.electronjs.org) | 43.4.0 | MIT (app shell) + BSD-3-Clause & others (Chromium components) | `shell/node_modules/electron`. See `shell/node_modules/electron/LICENSE` and `LICENSES.chromium.html`. |
| [Inno Setup](https://jrsoftware.org/isinfo.php) | 7.1.0 | Inno Setup License (free for commercial use; see its license) | Build-time only (`tools/InnoSetup7/`), portable, no registry writes. |
| [7-Zip / 7zr](https://www.7-zip.org) | 26.02 | LGPL-2.1-or-later (core); LZMA SDK public domain | `tools/7zr.exe` used to compress/extract `src.7z` during install. |
| Git | ≥ 2.x | GPL-2.0-only (with OpenSSL exception / LGPL at runtime) | Used by the update engine (`git ls-remote`). Users may also have their own Git installation. |

## Referenced / fetched at runtime (never bundled in this repo)

| Component | License | Where it comes from |
|---|---|---|
| [dshmarket](https://github.com/dsh-market/dsh-market) | MIT | Installed from npm by the plugin market at user request. |
| [modlens](https://github.com/liustack/modlens) | MIT | Installed from npm by the plugin market at user request. |
| Any other plugin from [awesome-dsh-plugin](https://awesome-dsh-plugin.com) | per-plugin | Installed via the plugin market; each carries its own license. |
| npm registry packages | per-package | `pnpm install` inside the profile. |

## Design inspirations (ideas only, no code copied)

The packaging was designed with reference to the following projects **for ideas only**; no code, text, or assets were copied from them. Their licenses govern their own repositories; check each before reusing anything from them directly.

| Project | License (as noted during design) | What was borrowed (idea-level) |
|---|---|---|
| [Links2008](https://github.com/Links2008) | MIT (per its repo) | Update model (download → stop → swap), `upstream-lock` pinning, release verification checklist, unofficial-build disclaimer wording |
| [xiincs](https://github.com/xiincs) | check its repo | Release SHA-256 checksums, lean packaging approach |
| [hairyf / deepseek-harness-desktop](https://github.com/hairyf/deepseek-harness-desktop) | non-standard "MIT + non-commercial restriction" | Concept only (desktop packaging of DSH). **Not compatible with this MIT project** — no code was taken |
| [dsh-market](https://github.com/dsh-market/dsh-market) | MIT | The plugin market is **integrated at runtime** (installed from npm by the user), not copied into this repo |
| [dsh-plugin-marketplace](https://github.com/uluckystar/dsh-plugin-marketplace) | check its repo | Marketplace concept only |

## Compliance notes

- **DeepSeek trademark**: "DeepSeek" is a trademark of DeepSeek (深度求索). This project uses it only to refer to the upstream project, and states clearly that it is unofficial and not endorsed. The project name "DSH-Portable" deliberately avoids claiming to be an official DeepSeek product.
- **MIT attribution**: if you distribute DSH-Portable or its source, keep the upstream MIT copyright and license texts. The official DeepSeek Harness LICENSE is reproduced inside the built `src/` (it is part of the upstream repository) and must not be removed.
- **Electron**: the Electron license texts ship inside `shell/node_modules/electron/` in the built product and must be retained.
- **7-Zip**: 7-Zip is distributed under LGPL; see <https://www.7-zip.org/license.txt>.

If you build from source, run the license verification built into the repo when available (see `docs/BUILDING.md`).
