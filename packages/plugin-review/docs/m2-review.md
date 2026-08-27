# M2 插件安全审查（尽力而为的审查层，非完整沙箱）

## 定位

这是**安装前静态审查 + 决策留痕**层，不是沙箱。运行时强制仍依赖官方 `user-approval`（`ctx.approval.request`，fail-closed），两者结合使用。

## 使用

```powershell
# 审查一个插件目录（默认排除 node_modules/.git）
.\review-plugin.ps1 -Path D:\tmp\some-plugin

# 审查并输出报告文件、运行时门禁建议
.\review-plugin.ps1 -Path D:\tmp\some-plugin -ReportOut D:\tmp\review.txt -GateOut D:\tmp\gate.json

# 风险项逐项确认后放行（只放行列出的规则 ID）
.\review-plugin.ps1 -Path D:\tmp\some-plugin -Approve INSTALL-SCRIPT,NET-EGRESS,CHILD-PROC

# 连同依赖一起扫（npm audit，联网；高危/严重默认 RISK）
.\review-plugin.ps1 -Path D:\tmp\some-plugin -AuditDeps

# 测试隔离：指定替代白名单/恶意哈希库
.\review-plugin.ps1 -Path D:\tmp\some-plugin -MaliciousListPath D:\tmp\my-hashes.json -AllowlistPath D:\tmp\my-allow.json
```

退出码：`0`=放行（无红旗且风险已批准）、`2`=需确认（存在未批准风险）、`3`=拒绝（存在红旗）。

## 判定规则

| 级别 | 含义 | 动作 |
|---|---|---|
| RED（红旗） | 混淆/动态执行/二进制载荷/凭据读取/越界写/恶意哈希命中 | **拒绝**（exit 3），白名单不可豁免 |
| RISK（风险） | 安装脚本/网络外发/子进程/会话读取/文件写入/依赖漏洞 | **逐项确认**（`-Approve <ID>` 或 allowlist.json），未确认不放行 |
| INFO（提示） | 环境变量访问/文件读取/压缩长行/仅本机网络 | 放行并记录 |

规则定义见 `rules\rules.json`（可自行增删正则）。

## 配套文件

- `allowlist.json`：按插件 ID 持久豁免 RISK 项（记录理由；RED 无法豁免）
- `vuln-allowlist.json`：`npm audit` 结果白名单（`包@版本` → 理由）
- `malicious-hashes.json`：恶意 SHA-256 库（`<sha256>` → 描述），命中即 RED
- `runtime-gate.json`：插件 → 运行时高危 API 清单（模板；由 `-GateOut` 生成）

## 运行时审批对接（官方 user-approval）

官方 seam：`ctx.approval.request({ agent, tool, callId, reason })` → `allowed-once / rejected / cancelled / unavailable`，消费方 fail-closed（无应答默认 `unavailable`）。参见 `src\docs\subsystems\approval.md`。

对接方式：
1. `review-plugin.ps1 -GateOut gate.json` 生成插件的高危 API 清单（CHILD-PROC / NET-EGRESS / DYN-EXEC / OOB-WRITE）。
2. 插件作者在调用这些 API 前调用 `ctx.approval.request`；官方工具（bash/fs）本身已走该 seam。
3. 行为审计：运行时高危调用结果写入审计台账：
   ```powershell
   .\..\audit\dsh-audit.ps1 log -Type plugin.runtime -PluginId <id> -Detail "high-risk api call" -Result ok -Evidence "<event json>"
   ```

**边界（诚实声明）**：当前交付为静态审查 + 决策 + 门禁契约；真正在运行时拦截/包装插件模块里的 `child_process`/`net` 调用，需要再做一个 dsh 运行时插件（挂进 profile 的组合层）。这是后续可选项，不是本层承诺。

## 测试夹具

`tests\fixtures\` 下有三个样本：
- `benign\`：无风险插件 → 期望 ALLOW
- `risk\`：安装脚本 + 远端 fetch + 子进程 + 文件写入 → 期望 CONFIRM
- `red\`：eval + 凭据读取 + base64 混淆 + 二进制载荷 → 期望 REJECT
