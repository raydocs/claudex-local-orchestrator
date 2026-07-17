# 安全边界

可以复制代码和无密钥模板；禁止复制另一台 Mac 的 `~/.config/claudex-local`、`~/.cli-proxy-api`、OAuth 文件、浏览器 cookie、Keychain、shell history 或 provider token。

8317 和 8318 必须只监听 `127.0.0.1`。安装器不自动做 OAuth，不打印生成的本地 key 或 Moonshot key，不启用云同步，也不自动运行付费模型探针。

`KIMI_API_KEY` 必须由账号持有人在装机时通过环境变量或隐藏输入提供，只能渲染到权限为 `0600` 的本机 CLIProxyAPI 配置。不得把它写入仓库、文档、聊天、截图、日志或 shell history；若曾暴露，立即在对应控制台（kimi.com 或 platform.moonshot.ai）轮换。`config/models.json` 只保存模型元数据，绝不保存凭据。

Kimi K3 独立计费（订阅配额或按量）。运行 live canary 或把非视觉任务升级到 Kimi 前，要由账号持有人确认调用范围和费用。Fable 5 Oracle 通过原生 `claude` 订阅侧通道运行，只允许 Read/Grep/Glob，不接写任务。

认证失败、model mismatch 或 timeout 不能通过伪造 alias、降低测试标准或隐藏错误解决。

向 GitHub 提交前运行 `bash scripts/verify.sh`，并检查 `git diff --check` 与 staged secret scan；verify 会同时扫描 Moonshot key 形状并核对 Agent frontmatter 与 `config/models.json`。
