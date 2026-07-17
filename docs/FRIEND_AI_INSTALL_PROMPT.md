# 发给朋友 AI 的 Prompt

你要在一台新 Mac 上安装公开仓库 `raydocs/claudex-local-orchestrator`。先阅读 README 和 docs。不要复制任何其他人的配置目录、token、OAuth 文件、cookie 或 Keychain 数据，不要要求用户把 key 发到聊天。

目标：安装 Claude Code、Node、CLIProxyAPI；clone 仓库；运行 `./scripts/bootstrap-macos.sh --check`；检查所有现有目标文件；获得人类允许后运行 `--install` 或 `--install --replace-existing`；让账号持有人亲自完成 provider 登录和 Moonshot key 隐藏输入；运行 adapter test、`bash scripts/verify.sh` 和 `./scripts/doctor.sh --require-models`。

强制规则：8317/8318 只绑定 127.0.0.1；不要发明 provider login flag；不要用误导 alias 假装缺失模型；不要自动运行付费 live canary；不要覆盖未检查的配置；不要修改普通 `claude` 的原生 subscription 配置；不要把 `KIMI_API_KEY` 放进命令历史、仓库或聊天。Kimi K3 是独立计费模型（Kimi Code 订阅或 Moonshot 按量 key，端点不同，见 docs/cliproxyapi-setup.md），Fable 5 Oracle 走本机原生订阅且只读。

网关必需模型应从 `config/models.json` 派生，当前为 `gpt-5.6-sol`、`gpt-5.6-luna`、`gpt-5.6-terra`、`grok-4.5`、`kimi-k3`、`gemini-3.5-flash`、`glm-5.2`；`fable-5` 不参加网关目录检查。

执行顺序：

```bash
command -v brew node python3 claude cli-proxy-api
brew install node cliproxyapi
curl -fsSL https://claude.ai/install.sh | bash
git clone https://github.com/raydocs/claudex-local-orchestrator.git
cd claudex-local-orchestrator
./scripts/bootstrap-macos.sh --check
./scripts/bootstrap-macos.sh --install
node --test adapter/model-filter-proxy.test.mjs
bash scripts/verify.sh
./scripts/doctor.sh --require-models
```

安装依赖、覆盖文件、浏览器 OAuth、Moonshot key 注入和付费 canary 前都要停下来获得人类批准。最终报告必须包含：安装状态、路径、8317/8318、required model 缺失项、requested/resolved identity、Oracle 可用性、运行过的验证、备份和剩余的人类步骤；不得输出 secret。
