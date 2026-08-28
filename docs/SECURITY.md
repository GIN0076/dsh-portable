# Security Notes / 安全说明

> 本节如实记录 DSH-Portable 的安全扫描状态与结论。**本项目不宣称"已通过安全审计"**，以下内容仅陈述已执行检查及其实结果。

## 更新机制状态（按 0.1.1-rc.2 实测）

- 在真实桌面机上对 `rc.2 → alpha.1` 原地升级进行了**三次**实测（监控进程、审计日志、`.updating` 标记、磁盘状态）；
- **三次 apply 都未启动**：审计日志仅有 `update.check`，从未出现 `update.apply`；监控显示 `update-dsh.ps1` powershell 进程从未存活超过 1 秒；
- 根因定位：Electron 在 Windows 上通过 Job Object 管理子进程，detach 子进程在 `app.quit()` 时会被一起终止，即便设置了 `CREATE_BREAKAWAY_FROM_JOB`，Node.js `child_process.spawn` 仍把 stdout/stderr 通过 Job 持有的句柄传给父进程，父进程退出即失效；
- 这是**发布策略**问题，不是构建/签名问题：默认将 GUI 入口（设置页更新检查卡片 + 托盘菜单"检查更新"）隐藏，保留 `packages/update-engine/update-dsh.ps1` 作为高级用户/运维手动升级入口；
- GUI 入口重新打开方法：在 `apps/desktop-shell/launcher-config.json` 设置 `"enableUpdate": true` 或设置环境变量 `DSH_ENABLE_UPDATE=1`。

## 扫描记录

- 工具：Mimosa 深度安全扫描（static + cross-file taint）
- 范围：`dsh-portable` 仓库全量（含 `src/` 上游源码）
- 最近一次：`scan-2026-08-28T00-23-52.589Z-0fc749dcfe30`
- 运行状态：**partial / inconclusive**（工具的威胁建模与发现阶段未完整覆盖；本次结果不能作为完整审计结论）

## 结论摘要

### 封装层（本项目自有代码）

- 静态扫描命中 **1 项**：`packages/update-ui/tsdown.config.ts:6` 报"命令注入"。
- **判定为误报**：该行是注释文本（`__ModuleLoader__.load(...)`），文件仅调用 `readFile`，不存在任何命令执行路径。
- 封装层其余代码（`apps/desktop-shell`、`packages/*`、`build/`、`installer/`、`scripts/`）**无真实高危发现**。

### 上游源码（`src/`，DeepSeek Harness 官方 0.1.1-rc.2）

- 扫描命中 **75 项**静态风险提示（代码注入、命令注入、SSRF、不可信程序选择、硬编码凭据等），**全部位于官方上游代码**，非本次封装引入。
- 上游作为 agent 框架天然包含大量子进程、网络与沙箱操作，静态扫描器会对这类模式批量报警；是否跟进属于上游（deepseek-ai/deepseek-harness）的职责。
- 其中"硬编码凭据"类（`dsh_e2b_passwd`、`DEEPSEEK_API_KEY`、`api_key`，位于 `src/scripts/smoke-python-runtime.py`、`src/scripts/publish-npm-baseline.ts`、`src/packages/e2b/subprocess-e2b`）大概率是上游测试占位符，建议向上游核实，**不应**在本仓库视为已确认泄露。

### 原则

- `src/` 保持上游 **zero-modified**；本仓库不修改、不打包分发上游源码的二进制，仅按官方构建流程封装。
- 插件安装前经过 M2 静态审查门禁（`packages/plugin-review`）；运行时插件行为依赖官方 approval 机制，M2 是"尽力而为的审查层，非沙箱"。

## Release 建议措辞（可直接引用）

> DSH-Portable 封装层新增代码经静态安全扫描未发现真实高危（唯一命中经核实为误报）；上游 DeepSeek Harness 为官方 `dsh-v0.1.1-rc.2` 源码原样封装，其静态扫描风险提示属于上游代码范畴。本发行版不宣称通过完整安全审计，请按非官方软件自行评估使用风险。
