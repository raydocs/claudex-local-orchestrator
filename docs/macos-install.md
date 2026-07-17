# macOS 安装

1. 安装 Homebrew、Node 18+、Claude Code 和 CLIProxyAPI：

```bash
brew install node cliproxyapi
curl -fsSL https://claude.ai/install.sh | bash
claude
```

最后一个命令由账号持有人完成浏览器登录。

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

如目标配置已存在，脚本会停止。检查后才可使用 `--replace-existing`；它会建立时间戳备份。安装位置包括 `~/.config/claudex-local`、`~/.local/bin/claudex-local`、`~/.local/share/claudex-local` 和对应 LaunchAgent。

4. 完成 provider 认证、运行 `./scripts/doctor.sh --require-models`，再启动 `claudex-local`。如希望命令名为 `claudex`，先确认没有同名文件，再手动创建 symlink。

回滚时先 `brew services stop cliproxyapi`，再 `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.claudex-local.model-filter.plist`，逐个检查并恢复备份。不要批量删除含 OAuth 的 `~/.cli-proxy-api`。
