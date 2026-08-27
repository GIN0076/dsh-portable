# DSH-Portable addons（附加层，out-of-tree）

> 全部内容独立于官方 `src\` 克隆，符合"官方零修改"原则。工作区源码在 `E:\codex\开发应用\DSH-Portable\addons\`，部署目标 `D:\Software Installation\deepseek-harness\addons\`。

## 目录

| 模块 | 路径 | 说明 |
|---|---|---|
| M1 审计留痕 | `audit\dsh-audit.ps1` | `$DSH_HOME/audit/audit.jsonl` JSONL 台账：序号/时间/操作者/类型/插件ID/详情/变更前后/结果/证据/会话；链式 SHA-256 防篡改；筛选/导出/单插件时间线/问题复盘/保留期清理/链校验 |
| M1 更新引擎 | `update-engine\update-dsh.ps1` | 自用版源码更新：镜像拉上游 tag → zip 下载 → 完整性校验（解压+版本对比）→ pnpm install/typecheck/build → 原子替换 + 自检（HTTP 200 + 端口释放）→ 失败回滚；更新前自动备份 `$DSH_HOME`；"下载预构建产物"模式留作未来开关 |
| M1 隐私中心 | `privacy\dsh-privacy.ps1` | 遥测状态（默认 DISABLED）、匿名 ID 查看/重置（`$DSH_HOME/.anonymous-user-id`）、反馈分享状态、审计保留期清理、数据备份导出 |
| M2 插件安全审查 | `plugin-review\review-plugin.ps1` | 安装前静态审查：8 类规则（安装脚本/网络外发/子进程/越界写/凭据会话读取/代码混淆/动态执行/二进制载荷）+ 证据行号；依赖漏洞白名单（可选 npm audit）+ 恶意 SHA-256 库；红旗→拒绝 / 风险→逐项确认（-Approve 或 allowlist）/ 提示→放行记录；运行时门禁契约输出（对接官方 user-approval） |
| M3 插件市场 | `market\dsh-market.ps1` | `search`（npmmirror 搜索）/ `info`（包信息+许可证+依赖）/ `install`（npm pack → **过 M2 审查** → 官方 `dsh plugin add`；`-Approve` 逐项确认；`-DryRun` 演练）/ `installed`（profile 已装列表） |
| M3 中文翻译层 | `translate\dsh-translate.ps1` | 字典覆盖（dicts→override.json，对齐官方 ns→common→zh→key 查找链）、强力翻译模式（逐插件 force-on/off）、模型翻译+本地缓存（OpenAI 兼容接口，key 只从环境变量读）、export-override 供运行时插件消费 |
| M4 插件工坊 | `workshop\dsh-workshop.ps1` | `clarify`（需求澄清：缺失字段出问题清单）/ `new`（按官方 Cordis 格式生成插件：`ctx.commands.register` 命令 + `ctx.on` 事件 + 工具/服务占位）/ `test`（node 语法检查 + apply 导出校验 + **M2 审查**）/ `install`（备份 profile → M2 门禁 → 官方 `dsh plugin add "file:..."` → 失败自动恢复 profile）/ `list` |
| M5 更新检查 UI | `update-ui\`（dsh-update-check 插件） | Web 设置页新增「更新检查」卡片：一键运行 `update-dsh.ps1 -Mode check` 并显示当前/最新版本；Host 侧注册 loopback-only 路由 `/dsh-update/check`，Client 侧注入 `settings.section`；安装：`dsh plugin --profile web add "file:<addons>\update-ui"`（路径勿含空格） |

## 使用

```powershell
# 审计：写一条记录
.\audit\dsh-audit.ps1 log -Type update.apply -PluginId dsh-portable -Detail "applied rc.8" -Before 0.1.0-rc.7 -After 0.1.0-rc.8 -Result ok -Session $env:CODEX_SESSION_ID

# 审计：列出 / 筛选 / 单插件时间线 / 链校验 / 保留期清理 / 问题复盘 / 导出
.\audit\dsh-audit.ps1 list -Limit 20
.\audit\dsh-audit.ps1 filter -Type update -Result fail
.\audit\dsh-audit.ps1 timeline -PluginId dsh-portable
.\audit\dsh-audit.ps1 verify
.\audit\dsh-audit.ps1 cleanup -Days 90
.\audit\dsh-audit.ps1 review
.\audit\dsh-audit.ps1 export -Out D:\tmp\audit-export.jsonl

# 更新引擎：只检查 / 执行更新
.\update-engine\update-dsh.ps1 -Mode check
.\update-engine\update-dsh.ps1 -Mode apply          # 端口被占时先退出应用；或 -KillRunning 强制停止本程序进程

# 隐私中心
.\privacy\dsh-privacy.ps1 status
.\privacy\dsh-privacy.ps1 reset-id
.\privacy\dsh-privacy.ps1 backup -Out D:\backup\dsh.zip
.\privacy\dsh-privacy.ps1 cleanup-audit -Days 90

# 插件安全审查（退出码 0=放行 2=需确认 3=拒绝）
.\plugin-review\review-plugin.ps1 -Path D:\tmp\some-plugin -ReportOut D:\tmp\review.txt -GateOut D:\tmp\gate.json
.\plugin-review\review-plugin.ps1 -Path D:\tmp\some-plugin -Approve INSTALL-SCRIPT,NET-EGRESS
.\plugin-review\review-plugin.ps1 -Path D:\tmp\some-plugin -AuditDeps

# 插件市场（安装强制过 M2 审查）
.\market\dsh-market.ps1 search -Query "dsh plugin"
.\market\dsh-market.ps1 info -Package dshmarket
.\market\dsh-market.ps1 install -Package some-plugin -Approve INSTALL-SCRIPT -DryRun   # 演练
.\market\dsh-market.ps1 install -Package some-plugin                                  # 真实安装
.\market\dsh-market.ps1 installed

# 中文翻译层
.\translate\dsh-translate.ps1 status
.\translate\dsh-translate.ps1 dict-add -Name my-pack -Path D:\tmp\dict.json
.\translate\dsh-translate.ps1 force-on -PluginId dshmarket
.\translate\dsh-translate.ps1 translate -Source D:\tmp\plugin-i18n.json -DryRun
.\translate\dsh-translate.ps1 export-override -Out D:\tmp\override.json

# 插件工坊（生成 → 澄清 → 自测 → 安装，全程过 M2 审查）
.\workshop\dsh-workshop.ps1 clarify -Name my-plugin -Description "what it does"
.\workshop\dsh-workshop.ps1 new -Name my-plugin -Description "what it does" -Features command,event -CommandName hello
.\workshop\dsh-workshop.ps1 test -Path D:\path\to\my-plugin
.\workshop\dsh-workshop.ps1 install -Path D:\path\to\my-plugin -DryRun
.\workshop\dsh-workshop.ps1 install -Path D:\path\to\my-plugin
.\workshop\dsh-workshop.ps1 list
```

所有脚本可用 `-DshHome <路径>` 指定数据目录（测试隔离用），更新引擎另支持 `-ProgramRoot`、`-Mirror`、`-Force`、`-KillRunning`。

## 已知边界

- 脚本输出为英文（PowerShell 5.1 中文 .ps1 编码坑，见 HANDOVER）；中文说明一律放 .md。
- 更新引擎自检用临时 `$DSH_HOME`，不写真实数据；备份数据目录用 robocopy `/XJ` 跳过 junction，防止误拷/误删 src。
- M3 决策门已通过：npm 上 `dshmarket@1.12.1`（MIT，github.com/dsh-market/dsh-market）存在，市场集成方案按计划落地，安装动作仍过 M2 审查。
- M2 定位"尽力而为的审查层，非完整沙箱"；运行时真正拦截插件内 `child_process/net` 调用需另做 dsh 运行时插件（后续可选项，见 `plugin-review\docs\m2-review.md`）。
- M3 市场集成：`dshmarket@1.12.2`（MIT）可作为市场 UI；社区插件列表通过 npm search 获取（dshmarket 仓库无 plugins.json）。翻译层模型翻译需用户自行创建 `$DSH_HOME/translate/config.json`（API key 只从环境变量读，不落盘）。
- M4 工坊：生成的插件走官方 Cordis 格式（`apply(ctx)` + `name` 导出），安装用官方 `dsh plugin --profile web add "file:<dir>"`（真实 E2E 已验证，profile 自动创建并带官方 bundle）；热激活需运行中的 harness 重载 profile（或重启 DSH-Portable）。
- M1–M4 以 CLI 工具形态交付；"附加层页面"（隐私中心/市场等 UI）属于后续可选项，待用户确认是否用 dsh 插件做页面。
