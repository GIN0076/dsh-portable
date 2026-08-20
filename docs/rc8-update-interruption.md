# RC8 更新中止情况说明 / Update Interruption Notice

> 记录时间：2026-08-20
> 场景：DSH-Portable 0.1.0-rc.7 通过官方更新器（`update-dsh.ps1` / `safe-update.cjs`）尝试升级到 0.1.0-rc.8 时，更新流程反复中止。
> **一句话结论：更新中止的直接原因是官方更新器在当前 Windows 权限与文件系统环境下处理临时目录失败。** 与本机硬件、RC7→RC8 升级可行性、数据完整性和既有依赖修复均无关。

## 一、先排除：不是这些原因

| 排除项 | 说明 |
|---|---|
| 电脑硬件损坏 | 全程无硬件报错；构建、运行、网络均正常，最终 RC8 构建与安装成功 |
| RC7 不能升级 RC8 | 升级路径本身可行——RC8 已用手工直装方式成功构建、安装并运行（web HTTP 200、Electron smoke 通过） |
| 数据损坏 | 数据目录 `$DSH_HOME` 全程未触碰，备份、配置、凭据完好 |
| 此前修复的依赖再次破坏 | sharp / landlock-run / profiles `@deepseek-ai` 的修复均未回退；RC8 为全新构建，不依赖旧修复 |

## 二、直接原因：更新器处理临时目录失败

更新器在更新流程中会创建多个临时/暂存目录（`.safe-tmp-*`、`stg-safe*`），并在失败后尝试用**系统回收站 / 第三方 trash 工具**删除它们。在本机 Windows 权限与文件系统环境下，这些删除操作反复失败：

- `Some operations were aborted` —— 回收站删除被系统中止；
- `genie-trash ... ETIMEDOUT` —— 第三方 trash 工具（genie-trash）超时；
- 7816～35616 个文件的批量删除触发"需要确认"保护，直接失败。

临时目录清不掉 → 更新器出于安全拒绝继续（如 `staging path already exists; refusing to delete it`）→ 更新流程卡死在中止状态。**这就是"RC8 更新中止"的直接原因。**

## 三、最准确的结论

这是**官方更新器与当前 Windows 环境之间的兼容性 / 异常处理问题，责任更偏向更新器**：

- 更新器对"临时目录清理失败"没有健壮兜底：失败即中止，且残留目录会阻塞下一次运行；
- 未覆盖 Windows 长路径（>260 字符）与 `node_modules` 深树（`LongPathsEnabled=0`）场景；
- 依赖第三方 trash 工具而非系统原生删除，异常路径下既慢又不稳定。

本机的 **PowerShell 执行策略与临时目录状态是触发条件**，而非根因：

- 受限/沙箱环境下注入的变量与策略放大了异常路径；
- 多次中止残留的 `.safe-tmp-*` 让后续清理更难成功，形成恶性循环；
- 跨卷 pnpm store（E:）与项目目录（D:）的 junction/硬链接布局，进一步加剧了临时目录的复杂性。

## 四、证据链（日志摘要）

- 解压环节：内置 `7zr` 只支持 7z、读不了 ZIP；`tar` 误解析；`Expand-Archive` 兜底存在 `$zip is not defined` 缺陷；改用 Python `zipfile` 后成功；
- 依赖安装：`pnpm install` 偶发 `node-pty` 链接不完整（`Cannot find package '...node-pty\index.js'`），时好时坏；
- 构建环节：`pnpm run build` 因 zip 源码无 `.git` 直接失败（`git rev-parse HEAD`），显式传入 `DSH_CLIENT_COMMIT_HASH` 后通过；
- 清理环节：`.safe-tmp-*` 删除反复失败（见第二节），最终阻断更新。

## 五、验证与现状

- 故障期间数据目录未动，RC7 未被破坏；
- 已用手工直装路径完成 RC8：官方源码 zip → `pnpm install/typecheck/build` → hoisted 扁平化 → `src.7z` → Inno Setup 安装包 → 静默安装 → 冒烟验证（HTTP 200 / Electron smoke / 桌面快捷方式）；
- 当前状态：DSH-Portable 0.1.0-rc.8 正常运行。

## 六、给后续更新器改进的备忘

- 临时目录清理改用 `fs.rmSync` 直删（不依赖回收站/trash），失败不阻塞下一次运行；
- 使用固定短路径暂存，规避 260 字符长路径；
- ZIP 解压用 Python `zipfile`（或可靠的系统解压 API），不要用 `7zr` 读 ZIP；
- 构建时显式传入 `DSH_CLIENT_COMMIT_HASH`，避免对 `.git` 的隐式依赖；
- npm 下载失败时自动切换镜像（如 npmmirror）。

---

## English Summary

The RC7 → RC8 auto-update interruption was caused by the **official updater failing to clean up its temporary/staging directories** under this machine's Windows permissions and filesystem conditions (trash-based deletion aborted or timed out, large batch deletions blocked). It was **not** caused by hardware failure, an impossible RC7→RC8 upgrade, corrupted user data, or regression of the previously repaired dependencies. The local PowerShell policy and leftover temp-directory state were trigger conditions, not the root cause. The compatibility/exception-handling responsibility lies mainly with the updater. RC8 was subsequently built, installed, and verified manually.
