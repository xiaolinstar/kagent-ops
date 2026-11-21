# v1 架构

概念与依赖总览见 [overview.md](overview.md)。下文以本地 `kind-kagent` 为主；云端为独立 k3s context，组件链路相同。Docker Desktop 的 `docker-desktop` context 是另一个集群，本阶段不接入。

```text
本地 UI / CLI（127.0.0.1 port-forward）
  → kagent-controller → PostgreSQL 18（会话与配置）
  → Agent sre-readonly + Harness sre-readonly
  → Substrate API / Router / RustFS / atelet
  → WorkerPool kagent-default（gVisor）
  → Go ADK alpha13 Actor → DeepSeek 公网模型
                         → kagent-tools MCP → kagent 命名空间只读 Role
```

Agent 使用 `api.kagent.dev/v1alpha3`，行为位于 `spec.template.inline`，运行时由 `spec.harnessRef` 指定。Harness 明确 WorkerPool、快照位置和固定摘要的 OCI 镜像。每个会话的 Actor 由 Substrate 运行，不对应一个独立 Agent Deployment。

ModelConfig 由 Helm 的 providers 配置生成；模型凭证通过既有 Secret 引用。MCP Agent 白名单、工具只读模式、Kubernetes Role 三层共同限定操作。当前未启用 Prometheus/Grafana 工具，未部署告警入口。

完整安装与验证命令见根目录 README.md。
