# macOS 安装

1. 安装 Homebrew、Node 18+、Claude Code 和 CLIProxyAPI：

```bash
brew install node cliproxyapi
curl -fsSL https://claude.ai/install.sh | bash
claude
```

最后一个命令由账号持有人完成浏览器登录；这也是 `oracle-consult` 调用 Fable 5 的原生订阅通道。

2. clone 并只读检查：

```bash
git clone https://github.com/raydocs/claudex-local-orchestrator.git
cd claudex-local-orchestrator
./scripts/bootstrap-macos.sh --check
```

3. 安装：

```bash
./scripts/bootstrap-macos.sh --install
```

Moonshot key 可通过非空 `KIMI_API_KEY` 环境变量提供；若未设置且 stdin 是 TTY，脚本会隐藏输入并允许留空。留空或非交互安装会写入 `unset-kimi-key` sentinel 并警告，之后必须由账号持有人手动更新本机 `~/.cli-proxy-api/config.yaml`，否则 `kimi-k3` 会缺失或调用失败。脚本绝不回显 key。

如目标配置已存在，脚本会停止。检查后才可使用 `--replace-existing`；它会建立时间戳备份。安装位置包括 `~/.config/claudex-local`（含 `models.json`）、`~/.local/bin/claudex-local`、`~/.local/bin/claudex-usage`、`~/.local/bin/oracle-consult`、`~/.local/share/claudex-local` 和对应 LaunchAgent。`claudex-usage` 可汇总本地 JSONL 用量账本。

4. 完成 provider 认证，确认网关目录包含 `config/models.json` 派生的 `gpt-5.6-sol`、`gpt-5.6-luna`、`gpt-5.6-terra`、`grok-4.5`、`kimi-k3`、`gemini-3.5-flash`、`glm-5.2`，运行 `./scripts/doctor.sh --require-models`，再启动 `claudex-local`。可运行 `./scripts/smoke.sh` 做不消耗模型 token 的端到端健康检查；只有显式添加 `--live` 才会花少量 token 运行真实 canary。`fable-5` 走原生订阅，不在网关目录内。如希望命令名为 `claudex`，先确认没有同名文件，再手动创建 symlink。

回滚时先 `brew services stop cliproxyapi`，再 `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.claudex-local.model-filter.plist`，逐个检查并恢复备份。不要批量删除含 OAuth 的 `~/.cli-proxy-api`。
