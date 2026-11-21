# kagent-ops：AI 运维基线配置仓

**kagent 1.0.0-alpha13** 的部署/运维配置（非上游源码）。**一套业务配置**覆盖本地 kind 与云端 k3s；环境差异见云端附录。

**先读：[概念与依赖](docs/overview.md)** · [文档索引](docs/README.md)

## 环境

| 环境 | 说明 |
| --- | --- |
| 本地 | `kind-kagent`；[阶段 1 验收](docs/stage1-acceptance-2026-10-26.md) |
| 云端 | ECS + k3s 1.37.x；[云端附录](docs/cloud-deployment.md) |

脚本显式指定 context，不改 current-context。

## 唯一配置入口

- Helm：`kagent-config/helm/values.yaml`
- 安装器：`kagent-install-config.yaml`
- Agent / Harness：`kagent-config/crds/agents.yaml`、`harness.yaml`
- 版本：kagent alpha13；Substrate / PodCertificate 0.5.0-alpha2
- 历史：`docs/legacy/`、`kagent-config/legacy/`（禁止当现行 apply）

## 本地

需要 kubectl、Helm、Ruby、alpha13 macOS CLI（gitignore，自行下载）。

```bash
./scripts/local-up.sh
./scripts/verify-readonly.sh
```

```bash
kubectl --context kind-kagent -n kagent port-forward svc/kagent-ui 8080:8080 --address 127.0.0.1
kubectl --context kind-kagent -n kagent port-forward svc/kagent-controller 18083:8083 --address 127.0.0.1
```

暂停：`./scripts/local-stop.sh`。冒烟：`./scripts/smoke-agent.sh`。DeepSeek Key 仅放 Secret `kagent-deepseek-runtime`。

## 云端

镜像加速、gVisor、Linux CLI 等见 [docs/cloud-deployment.md](docs/cloud-deployment.md)。`deploy/cloud/` 仅保留 CLI 校验和与 registries 示例。

## 本阶段不做

跨命名空间/业务集群诊断；`kagent-config/monitoring/`；legacy 文档中的旧方案。
