# DSH-Portable — Release Checklist / 发布前检查清单

> 在打发布包（`DSH-Portable-Setup-*.exe`）之前逐项核对。任何一项未通过都在发版前修掉，不要把“已知问题”拖进发布版。

---

## 当前最新发布（2026-08-28）

- **DSH-Portable 0.1.2-alpha.1**  ← 基于 DeepSeek Harness `dsh-v0.1.2-alpha.1` (commit `cd5ef81`)
- 安装包：`dist/DSH-Portable-Setup-0.1.2-alpha.1.exe`
- SHA-256：`20e2996b747fc019cee4c899612582c7361151e3c595d59f22da68dc35861f74`
- 状态：✅ 通过清单验证（安装 / 启动 / update-ui 排除 / 无 GUI 自动更新残留）

历史版本：`v0.1.0-rc.8`、`v0.1.0-rc.7`、`v0.1.1-rc.2` 通过 `git tag` 留档；旧安装包不保留在 `dist/`（需要时可由对应 commit 重新构建）。

---

## 0. 前置准备

- [ ] 确定目标版本号，并同步更新：
  - `installer/DSH-Portable.iss` 中的 `MyAppVersion` / `MyAppVerNum`
  - `apps/desktop-shell/package.json` 的 `version`
  - 各 `packages/*/package.json` 的 `version`（如需）
  - `version-manifest.json`、`upstream-lock.json`（如为源码构建）
  - `docs/BUILDING.md`、`docs/ARCHITECTURE.md`、`README.md` 中的版本号与 tag
- [ ] `CHANGELOG.md` 已记录本次变更（含本次结构重构说明）。
- [ ] 确认 `packages/` 与 `apps/desktop-shell/` 目录已按新结构就位，无旧的 `addons/` / `shell/` 目录残留。
- [ ] 全仓库检索旧路径引用，确认残留在“可接受范围”内（仅构建产物 `.map`、生成物注释允许，运行时路径必须为 0）：
  ```powershell
  grep -RIn --exclude-dir=.git -E 'addons/|shell/' . | Select-String -NotMatch '\.map'
  ```
  > 预期：无 `addons/`、`shell/` 的运行时引用；`.map` 里的旧源路径可忽略。

---

## 1. 上游源码（`src/`）

- [ ] `src/` 为**从零修改**的上游克隆（用 `git status` 对照 `src/` 应无本地改动）。
- [ ] 上游锁定在目标 tag（如 `dsh-v0.1.1-rc.2`），与 `upstream-lock.json` 一致。
- [ ] `src/` 未被提交到本仓库（在 `.gitignore` 中，`/src/` 规则生效）。
- [ ] 打包时 `pnpm install --frozen-lockfile`、`pnpm run typecheck`、`pnpm run build` 全部退出码 0。

---

## 2. 打包链路（`build/`）

- [ ] 在 `src/` 内设置 `nodeLinker: hoisted`，并重新 `pnpm install --frozen-lockfile`。
- [ ] 运行 `build/flatten.js`（结果：全树无 junction，`node_modules` 平铺在根目录，`iscc` 可安全跟进）。
- [ ] 若要本地化命令描述，运行 `build/localize-commands.js`（仅改构建产物，不改 `src/`）。
- [ ] 用 `7zr.exe` 生成 `src.7z`，确认压缩大小符合预期（约 238 MB）。
- [ ] 用 `tools/InnoSetup7/ISCC.exe /DSourceRoot=staging installer/DSH-Portable.iss` 编译。
  - 注意 `/DSourceRoot` 为 camelCase。
  - `.iss` 保持 **UTF-8 带 BOM**，否则中文/界面乱码。
- [ ] 确认 `installer/DSH-Portable.iss` 中 `[Files]` 段指向新路径：
  - `apps\desktop-shell\*`
  - `packages\*`
  - `scripts\windows\*`
- [ ] 确认 `[Run]` 处启动的是 `{app}\apps\desktop-shell\...\electron.exe`。

---

## 3. 安装器验证（Inno Setup）

- [ ] 用隔离目录静默安装，路径不含空格：
  ```powershell
  dist\DSH-Portable-Setup-<version>.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="C:\tmp\dsh-inst" /DATADIR="C:\tmp\dsh-data" /NODESKTOP /NOSTARTMENU /NOAUTOSTART
  ```
- [ ] 安装后 `src.7z` 被解压且压缩包被删除。
- [ ] `{app}\apps\desktop-shell\launcher-config.json` 正确写入 `dataDir`（默认空）。
- [ ] 双语向导正常，license/免责声明被拒绝时中止安装。
- [ ] 桌面/开始菜单快捷方式可选，创建失败只写 `install-log.txt`，不中断。
- [ ] 开机自启默认关闭，仅勾选时写 `HKCU\Run`。
- [ ] **卸载安全性**：确认卸载器只删除“本次安装创建的快捷方式”，且不误删数据目录。

> ⚠️ 静默卸载会连带清除真实的桌面/开始菜单快捷方式与 `{AppId}` 卸载注册表键。测试务必用 `/NODESKTOP /NOSTARTMENU`，并在卸载测试前备份：
> `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{AFF08DAB-DFB3-4474-9ED0-38E83ACC6521}_is1`

---

## 4. 启动 / 运行冒烟

- [ ] 从安装树启动 `runtime\node\node.exe` 的 CLI web 服务，期望 `127.0.0.1:3099` 返回 HTTP 200：
  ```powershell
  & "C:\tmp\dsh-inst\runtime\node\node.exe" "C:\tmp\dsh-inst\src\apps\cli\lib\bin.js" web --host 127.0.0.1 --port 3099
  ```
- [ ] 桌面壳 `apps/desktop-shell/main.js` 能拉起服务并加载 `http://127.0.0.1:3080`。
- [ ] 托盘菜单（显示 / 检查更新 / 退出）可用；点 X 隐藏到托盘，服务不退出。
- [ ] 单实例锁生效：第二次启动只唤醒窗口，不重复拉起服务。
- [ ] 首次运行弹出“非官方声明与隐私”须知，且只弹一次（`noticeShown`）。
- [ ] 端口被占用时：若为外部服务则只附着不杀；若为自身则能正常复用。

---

## 5. 停止 / 清理脚本

- [ ] `scripts/windows/停止DSH-Portable.cmd` 能通过端口 3080 + 命令行匹配清掉整棵进程树，无残留。
- [ ] `scripts/windows/清理DSH-Portable.cmd` 能：停止 → 删除快捷方式 → 可选删数据目录 → 静默卸载。
- [ ] 数据目录解析走 `launcher-config.json`，否则回落到 `~/.dsh`。
- [ ] 含凭据/审计的数据目录删除前有交互确认，非默认不删。

---

## 6. 更新引擎（`packages/update-engine/update-dsh.ps1`）

- [ ] `-Mode check` 能枚举上游 tag（多镜像 + OpenSSL 回退 + GitHub API 回退）。
- [ ] `-Mode apply` 能下载 tag 源码 zip，并拒绝 < 1 MB（代理错误页启发式）。
- [ ] 源码在 `stg` 级联目录构建，避免 260 字符路径上限。
- [ ] 原子替换 `src` → `src.bak`，自检（HTTP 200 + 端口释放）失败自动回滚。
- [ ] 更新前已用 `robocopy /XJ` 备份 `$DSH_HOME`（跳过 junction）。
- [ ] 更新中途由 `.updating` 标记驱动，壳能安静退出而非弹“意外退出”。
- [ ] `version-manifest.json` / `upstream-lock.json` 更新后与构建产物一致。

---

## 7. 插件审查 / 市场 / 工坊

- [ ] `packages/plugin-review/review-plugin.ps1` 退出码语义正确：
  - `0`=ALLOW / `2`=CONFIRM（需逐项批准）/ `3`=REJECT。
- [ ] RED 项（DYN-EXEC、OBFUSCATION-B64、CRED-READ、OOB-WRITE、BINARY-PAYLOAD、MALICIOUS-HASH）能拒绝。
- [ ] install（市场/工坊）路径都经过 M2 门禁，不通过则中止。
- [ ] 审查报告带文件:行号证据；`.gitignore` 已忽略 `.npm-cache/`、`backups/`。
- [ ] 已知边界：M2 是静态审查，不是沙箱——文档已说明运行时拦截交由官方 approval 机制。

---

## 8. 安全 / 隐私 / 合规

- [ ] 所有自定义路由（`/dsh-update/*`）仅走回环 `127.0.0.1` / `localhost`，并做 origin 校验。
- [ ] 遥测默认关闭；匿名 ID、反馈状态可查看/重置。
- [ ] 凭据仅存本地数据目录（默认 `~/.dsh`），不上传；翻译模型 key 只从环境变量读。
- [ ] 无管理员权限：`PrivilegesRequired=lowest`，仅 HKCU 写入，无服务。
- [ ] `LICENSE`、`THIRD-PARTY-NOTICES.md` 与 README 许可说明一致（本项目 MIT，上游 MIT，第三方各自授权）。
- [ ] README 明确 unofficial build 免责声明（与 DeepSeek 无关联、未获背书）。

---

## 9. 文档一致性

- [ ] `README.md` 仓库结构/许可/使用说明与新布局一致。
- [ ] `docs/ARCHITECTURE.md`、`docs/BUILDING.md` 旧路径已清理到可接受范围。
- [ ] `CHANGELOG.md` 已记录本次改动（结构重构 + 路径对齐）。
- [ ] `docs/RELEASE-CHECKLIST.md` 已随版本更新。

---

## 10. 发布产物

- [ ] 安装包 `dist\DSH-Portable-Setup-<version>.exe` 生成成功。
- [ ] 记录安装包 SHA-256，写入 release 说明（用户可核验）。
- [ ] GitHub Release 附上：安装包、`CHANGELOG.md` 摘要、本清单勾选结果、（可选）`upstream-lock.json` / `version-manifest.json`。
- [ ] 确认没有把 `.updating`、`launcher-config.json`、`install-log.txt` 等运行时文件打进安装包。

---

## 一键速查（TL;DR）

打包 → 隔离安装 → 冒烟 → 更新引擎回滚演练 → 插件审查门禁 → 卸载不留残留 → 同步文档与许可 → 附 SHA-256 发布。
