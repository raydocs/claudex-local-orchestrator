# 架构

ClaudeX Local 是配置层，不是远程 SaaS，也不是 claudex-flow/workflowgrok runtime。主线程由 GPT-5.6 Sol 负责；自定义 Agent profiles 只接受独立、可验证的切片。Agent 最多并发三个，写路径必须互斥，主线程保留一个有用切片并负责最终集成。

请求链路为 Claude Code → `127.0.0.1:8318` Node adapter → `127.0.0.1:8317` CLIProxyAPI。adapter 只对 Sol 的原生 compact prompt 改写 model 为 Luna，其余请求原样转发。普通 `claude` 不加载这套 settings，继续使用独立 Claude.ai subscription。

Amp-style 指工作原则：验收先行、按独立切片并行、最小上下文、一次收集、主线程验证、通过即停。本项目与 Amp 无隶属关系。
