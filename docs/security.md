# 安全边界

可以复制代码和无密钥模板；禁止复制另一台 Mac 的 `~/.config/claudex-local`、`~/.cli-proxy-api`、OAuth 文件、浏览器 cookie、Keychain、shell history 或 provider token。

8317 和 8318 必须只监听 `127.0.0.1`。安装器不自动做 OAuth，不打印生成的本地 key，不启用云同步，也不自动运行付费模型探针。

运行 live canary 前要由账号持有人确认调用范围和费用。认证失败、model mismatch 或 timeout 不能通过伪造 alias、降低测试标准或隐藏错误解决。

向 GitHub 提交前运行 `bash scripts/verify.sh`，并检查 `git diff --check` 与 staged secret scan。
