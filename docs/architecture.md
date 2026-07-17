# 架构

ClaudeX Local 是配置层，不是远程 SaaS，也不是 claudex-flow/workflowgrok runtime。主线程由 GPT-5.6 Sol 负责；自定义 Agent profiles 只接受独立、可验证的切片。Agent 最多并发三个，写路径必须互斥，主线程保留一个有用切片并负责最终集成。

请求链路仍为 Claude Code → `127.0.0.1:8318` Node adapter → `127.0.0.1:8317` CLIProxyAPI。adapter 只对 Sol 的原生 compact prompt 改写 model 为 Luna，其余请求原样转发。通用实现默认路由到 Grok；前端、dataviz、游戏/shader、设计还原等视觉/图形密集切片才路由到独立计费的 Kimi K3。

`oracle-consult` 不经过上述网关：它清除网关环境变量，通过本机原生 `claude` 订阅调用 Fable 5，并只开放 Read/Grep/Glob。Oracle 只提供复核证据，不写文件、不替代主线程决策。普通 `claude` 同样不加载这套 gateway settings，继续使用独立 Claude.ai subscription。

会话隔离：launcher 通过独立 `CLAUDE_CONFIG_DIR` 隔断 `~/.claude` 的 plugins/skills，`--strict-mcp-config` 与 `--disallowedTools "Skill,mcp__*"` 再挡住任何 scope 的 skill 与 MCP 注入（实测三者叠加后 skills/MCP 为零、六个自定义 agent 完整可用）。`--setting-sources` 必须包含 `user`——该 scope 已被重定向到隔离目录，排除它会把自家 agent profiles 一并关掉。orchestrator 同时禁止通过 Bash 调用其他 AI CLI；唯一的网关外模型调用是 `oracle-consult`。

模型与角色分配集中在 `config/models.json`；Agent prompt 仍是静态安全产物，由 `scripts/verify.sh` 检查双向一致性。

Amp-style 指工作原则：验收先行、按独立切片并行、最小上下文、一次收集、主线程验证、通过即停。本项目与 Amp 无隶属关系。
