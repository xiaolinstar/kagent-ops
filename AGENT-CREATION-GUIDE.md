# v1 Agent 创建指南

当前固定使用 kagent 1.0.0-alpha13。实际部署入口是 `scripts/local-up.sh`，使用 `kagent-config/crds/agents.yaml` 与 `harness.yaml`；README.md 包含调用命令。

Agent 必需 `spec.harnessRef` 和 `spec.template`。本项目采用 inline template，引用 Helm 生成的 `default-model-config`。MCP 引用必须包含 `kind: RemoteMCPServer`、`name: kagent-tool-server`，alpha13 要求省略 apiGroup。显式 tools 列表限定可见工具；空列表会暴露该 Server 的全部工具。

Harness 必需 substrate、workload，以及 kagent/codex/claude/byo 中的一种运行时。当前使用 Go ADK、gVisor WorkerPool、RustFS 快照桶。镜像必须包含有效 sha256 摘要；本地 ARM64 镜像源及摘要已固定在实际清单中。snapshotPolicy.location 使用 gs://ate-snapshots/kagent/，存储后端来自 Substrate；不能用字面量 local 替代桶路径。

先执行服务端校验再部署：

```bash
kubectl --context kind-kagent apply --dry-run=server -f kagent-config/crds/
./scripts/local-up.sh
```

根目录 agent-example.yaml / harness-example.yaml、test-agent.yaml / test-harness.yaml 是完整的示例副本，名称为 test-agent / simple-harness，不是部署源。不要在实际基线上重复创建它们；修改实际配置请编辑 kagent-config/crds/。

Agent Ready 取决于模型和工具引用解析、Harness 兼容性及运行时 golden snapshot，不应只根据 Pod Running 判断。CLI 调用方式为先创建 Session，再使用 `agent invoke --session ID --task ...`；CLI 不接受 `invoke AGENT_NAME --context`。
