# CLIProxyAPI 配置

官方项目：<https://github.com/router-for-me/CLIProxyAPI>。Homebrew 安装为 `brew install cliproxyapi`，服务名为 `cliproxyapi`，默认端口 8317。

本项目模板仅绑定 `127.0.0.1`，并生成一个新的本地 client key。该 key 只保护本机网关，不是供应商 API key。

Codex OAuth 的官方入口是：

```bash
brew services stop cliproxyapi
cli-proxy-api --codex-login
brew services start cliproxyapi
```

Gemini、xAI/Grok、GLM 或其他 upstream 必须按当前官方 provider 文档配置。不要猜 login flag，不要把 token 发给 AI，不要把端口改成 `0.0.0.0`。`oauth-model-alias` 只能映射真实可访问模型，不能制造权限。

## Kimi K3

Kimi K3 走 OpenAI-compatible API，模板按本机 CLIProxyAPI schema 写入 `openai-compatibility`、`api-key-entries` 和 `models[].alias`。key 有两种来源，端点不同，不能混用：

- **Kimi Code 订阅**（`sk-kimi-…`，在 <https://www.kimi.com/code> 管理）：端点 `https://api.kimi.com/coding/v1`，按订阅配额计费。模板默认此端点。
- **Moonshot 开放平台**（在 <https://platform.moonshot.ai/> 创建）：端点 `https://api.moonshot.ai/v1`，按 token 计费（$3/M 输入、$15/M 输出）。使用时改模板的 `base-url`。

key 被拒时先确认 key 类型与端点匹配，再怀疑 key 本身。

安装时的注入顺序是：非空 `KIMI_API_KEY` 环境变量 → 交互式 TTY 隐藏输入 → `unset-kimi-key` sentinel。最后一种方式会完成安装，但 `kimi-k3` 在人工更新 `~/.cli-proxy-api/config.yaml` 前无法通过 doctor。安装器不会回显 key；渲染后的配置权限为 `0600`。

Kimi K3 独立计费（订阅配额或按量），只应接视觉/图形密集切片或 lead 明确标记的升级任务。key 绝不能写进仓库、贴给 AI、放入文档或 shell history；若 key 曾在聊天、日志或屏幕共享中暴露，应立即在对应控制台（kimi.com 或 platform.moonshot.ai）轮换，然后只更新本机配置。
