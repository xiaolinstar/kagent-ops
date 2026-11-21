# 创建 Agent（v1alpha3）

部署源（本地与云端相同）：

- Agent：`kagent-config/crds/agents.yaml`
- Harness：`kagent-config/crds/harness.yaml`（南大源 + 多架构 digest + `GODEBUG`）
- 总览：[docs/overview.md](docs/overview.md)

Harness 需要 substrate、workload 与一种运行时（当前 Go ADK）。`snapshotPolicy.location` 使用 `gs://ate-snapshots/kagent/`。

```bash
kubectl -n kagent get agents.api.kagent.dev,harnesses.api.kagent.dev
kubectl -n kagent describe agent sre-readonly
```

Ready 依赖模型/工具引用、Harness 兼容性与 **golden snapshot**（atelet 拉齐 workload 镜像）。CLI：先 `session create`，再 `invoke --session`。

`kagent-config/crds/agents/` 下其它 Agent 须单独验收后再部署。
