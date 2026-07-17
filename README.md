# ClaudeX Local Orchestrator

**本地 Claude Code 多模型、多 Agent 编排套件，采用 Amp-style 工作方式，但与 Amp 无隶属或官方关系。**

ClaudeX Local 是配置优先的本地工具：GPT-5.6 Sol 负责主线程，Grok/Terra/Gemini/GLM 通过自定义 Agent profiles 承担独立切片，CLIProxyAPI 提供本地模型网关。它不是 `claudex-flow` 或 workflowgrok runtime，也不包含其 Go 代码、路由账本或版本历史。

```text
claudex-local / GPT-5.6 Sol lead
  ├─ grok-implementer
  ├─ grok-researcher
  ├─ terra-explorer
  ├─ gemini-url-digester
  └─ glm-thread-reader

Claude Code -> 127.0.0.1:8318 adapter -> 127.0.0.1:8317 CLIProxyAPI
```

## 特性

- 独立 `claudex-local` launcher，不影响普通 `claude`；
- 启动前按任务选择 medium/high/xhigh effort；
- 最多三个并行 Agent，写范围必须互斥；
- Sol compact 请求可单独路由到 Luna；
- 配置模板无密钥，安装时生成新的本地 client key；
- macOS bootstrap、doctor、静态验证和 adapter 测试；
- 不静默安装供应商凭据，不伪造模型 alias。

## 快速开始

```bash
brew install node cliproxyapi
curl -fsSL https://claude.ai/install.sh | bash
git clone https://github.com/raydocs/claudex-local-orchestrator.git
cd claudex-local-orchestrator
./scripts/bootstrap-macos.sh --check
./scripts/bootstrap-macos.sh --install
```

然后由账号持有人在本机完成 CLIProxyAPI provider 登录，确认 `/v1/models` 中存在真实可用的模型，再运行：

```bash
./scripts/doctor.sh --require-models
claudex-local
```

详细文档：

- [架构](docs/architecture.md)
- [macOS 安装](docs/macos-install.md)
- [CLIProxyAPI](docs/cliproxyapi-setup.md)
- [模型配置](docs/model-configuration.md)
- [安全边界](docs/security.md)
- [直接发给朋友 AI 的 Prompt](docs/FRIEND_AI_INSTALL_PROMPT.md)

## 必需模型目录

精确复制模式要求：`gpt-5.6-sol`、`gpt-5.6-luna`、`gpt-5.6-terra`、`grok-4.5`、`gemini-3.5-flash`、`glm-5.2`。alias 不会赋予访问权；缺少真实模型时应停止并设计诚实的替代模型 fork。

## 验证

```bash
node --test adapter/model-filter-proxy.test.mjs
bash scripts/verify.sh
```

## License

MIT
