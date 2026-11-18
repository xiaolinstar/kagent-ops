# 本地部署与验证

本项目以配置为主，统一入口为根目录 `scripts/local-up.sh`。基线和调用方法见 README.md。

```bash
./kagent-darwin-arm64 --config kagent-install-config.yaml config validate
helm template kagent ./kagent-1.0.0-alpha13.tgz -n kagent -f kagent-config/helm/values.yaml > /tmp/kagent-rendered.yaml
kubectl --context kind-kagent apply --dry-run=server -f kagent-config/crds/
./scripts/local-up.sh
./scripts/verify-readonly.sh
```

`helm template` 通过不等于可运行；需同时观察 Agent Ready、真实模型响应、实际 MCP 调用和拒绝越权的结果。首次准备运行时要下载镜像并生成快照，Agent 在此期间为 ActorTemplatePending。

排查使用显式 context：

```bash
kubectl --context kind-kagent get pods -n kagent
kubectl --context kind-kagent get pods -n ate-system
kubectl --context kind-kagent get agent sre-readonly -n kagent -o yaml
kubectl --context kind-kagent logs deployment/kagent-controller -n kagent --tail=30
kubectl --context kind-kagent logs daemonset/atelet -n ate-system --tail=30
```

日志可能包含工具数据，分享前需审查脱敏。不要输出 Secret 或完整 Helm values；安装器可能在 Helm release 历史中保存模型凭证。网络排查需区分宿主机、kind 节点与沙箱：宿主机可访问 GHCR 不代表 atelet 可访问。

不使用旧目录的 v1alpha2 资源。当前阶段仅管理固定的本地 ARM64 环境；其他架构要先核对对应镜像摘要。历史开发文档位于 docs/legacy/development-v0.10.md。
