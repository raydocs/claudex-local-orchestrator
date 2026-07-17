# 模型配置

默认职责：Sol 主线程；Grok 实现和外部研究；Terra 仓库探索；Gemini 已知 URL 提取；GLM 选定 transcript 提取；Luna compact。

精确模式需要 CLIProxyAPI 的 `/v1/models` 返回六个模型 ID。requested 与 resolved identity 不一致应视为失败，不能静默 fallback。

如果朋友没有相同模型访问权，应建立替代模型 fork：使用真实 `/v1/models` 结果，修改 launcher、Agent frontmatter、compact adapter 和文档，再重新验证。不要把完全不同模型仅改名成 Sol/Terra/Luna。

Agent profile 位于 `agents/`，安装后复制到 `~/.config/claudex-local/claude/agents/`。每个 profile 禁止递归 delegation，并要求返回简短证据。
