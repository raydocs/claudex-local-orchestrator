# CLIProxyAPI 配置

官方项目：<https://github.com/router-for-me/CLIProxyAPI>。Homebrew 安装为 `brew install cliproxyapi`，服务名为 `cliproxyapi`，默认端口 8317。

本项目模板仅绑定 `127.0.0.1`，并生成一个新的本地 client key。该 key 只保护本机网关，不是供应商 API key。

Codex OAuth 的官方入口是：

```bash
brew services stop cliproxyapi
cli-proxy-api --codex-login
brew services start cliproxyapi
```

Gemini、xAI/Grok、GLM 或 OpenAI-compatible upstream 必须按当前官方 provider 文档配置。不要猜 login flag，不要把 token 发给 AI，不要把端口改成 `0.0.0.0`。`oauth-model-alias` 只能映射真实可访问模型，不能制造权限。
