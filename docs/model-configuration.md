# 模型配置

`config/models.json` 是角色、模型、通道、网关目录要求和计费属性的单一来源。launcher、bootstrap、doctor 与 verify 都从这里读取或核对；`agents/*.md` 保持静态、可人工审查，并由 verify 与清单做双向一致性检查。

## 分工

| 角色 | 模型 | 通道 | 用途 |
|---|---|---|---|
| 主线程 Supervisor | `gpt-5.6-sol` | gateway | 分解、调度、集成和最终验收；effort 只作用于主线程 |
| Oracle | `claude-fable-5` | 原生 `claude` 订阅 | 架构裁决、疑难根因和高风险 diff 的只读复核 |
| 通用编码 worker | `grok-4.5` | gateway | 默认的有界实现与测试 |
| 前端/视觉 worker | `kimi-k3` | gateway / Kimi key | 视觉与图形密集工程；独立计费（订阅配额或按量），仅用于前端、dataviz、游戏/shader、设计还原或明确升级切片 |
| 外部研究 | `grok-4.5` | gateway | 外部 OSS、库、API 文档和上游源码研究 |
| 仓库探索 | `gpt-5.6-terra` | gateway | 大范围只读仓库映射与依赖追踪 |
| URL/媒体摘要 | `gemini-3.5-flash` | gateway | 已知 URL、图片和 PDF 的可见内容摘要 |
| transcript 读取 | `glm-5.2` | gateway | 指定历史 transcript/log 的有界提取 |
| Compaction | `gpt-5.6-luna` | adapter 改写 | 只处理 Sol 的原生 compact 请求 |
| Titling | 刻意不设 | — | 低频需求，本轮明确不引入专用角色 |

网关精确模式需要 `/v1/models` 返回 `config/models.json` 派生的七个 ID：`gpt-5.6-sol`、`gpt-5.6-luna`、`gpt-5.6-terra`、`grok-4.5`、`kimi-k3`、`gemini-3.5-flash`、`glm-5.2`。`claude-fable-5` 走原生订阅，不参加网关目录检查。requested 与 resolved identity 不一致应视为失败，不能静默 fallback。

## Honest fork

如果朋友没有相同模型访问权，应根据真实 `/v1/models` 建立替代模型 fork。至少同步修改 `config/models.json`、对应 Agent frontmatter、provider 模板和文档，然后重新验证；若改动 compaction 模型，还要核对 plist 渲染和 adapter 行为。不要把完全不同模型仅改名成 Sol/Terra/Luna，也不要让 alias 冒充访问权限。

Agent profile 位于 `agents/`，安装后复制到 `~/.config/claudex-local/claude/agents/`。每个 profile 禁止递归 delegation，并要求返回简短证据。
