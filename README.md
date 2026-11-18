# kagent-ops：本地 AI 运维基线

本项目使用 **kagent 1.0.0-alpha13**，以 Agent + Harness + Substrate 运行只读 SRE 诊断助手。当前阶段仅诊断专用 kind 集群的 `kagent` 命名空间；后续再接入业务集群、Prometheus、日志和告警。

## 本地环境

| Context | 用途 |
| --- | --- |
| `kind-kagent` | 专用 kind 集群，集群名 `kagent`；本项目的部署目标 |
| `docker-desktop` | Docker Desktop 内置 Kubernetes（底层同样可使用 kind）；本阶段不修改 |

所有脚本固定指定 `kind-kagent`，不会修改 kubeconfig 的 current-context。两者是独立集群，不能通过另一个集群的 Service DNS 直接访问业务。

## 版本与配置入口

- kagent / CRD / CLI：`1.0.0-alpha13`，不是 v1 稳定版。
- Substrate / PodCertificate：`0.5.0-alpha2`，与现有安装一致。
- PostgreSQL：安装器管理的 PostgreSQL 18，连接使用 Secret 与 PodCertificate。
- 运行时：Go ADK alpha13，固定 ARM64 镜像摘要。当前使用可达的 GHCR 镜像源，见 `kagent-config/crds/harness.yaml`。
- 唯一 Helm 配置：`kagent-config/helm/values.yaml`。
- 唯一安装器配置：`kagent-install-config.yaml`。
- v1 清单：`kagent-config/crds/`；ModelConfig 由 Helm 生成，不重复 apply。
- 旧 v0.10 配置和说明：`kagent-config/legacy/`、`docs/legacy/`，仅用于历史参考。

## 启动与更新

需要 kubectl、Helm 4、Ruby 和本地 alpha13 CLI。当前仓库保存了 macOS ARM64 CLI 及 Chart 压缩包；缺少 Chart 时脚本拉取固定版本 OCI Chart。

```bash
./scripts/local-up.sh
```

脚本校验 CLI 与本地安装包摘要，恢复既有数据库和 Substrate，统一 Helm 配置，校验并创建 `sre-readonly` Agent/Harness，验证只读权限，等待运行时快照就绪。既有安装会复用独立的 `kagent-deepseek-runtime` Secret，不要求重新输入 API Key。真实 Key 不传给 Helm；安装器只收到初始化占位值，最终升级使用完整基线清除该值。

全新安装需要先创建名为 `kagent` 的 kind 集群，使 `kind-kagent` context 可用，并通过环境变量提供 `DEEPSEEK_API_KEY` 后运行同一脚本。安装器负责数据库、PodCertificate 和 Substrate 的初始化。全新集群安装路径尚需单独验收，不能将既有集群恢复结果视作重建验收。

## 访问与调用

暂停并释放专用 kind 节点资源：`./scripts/local-stop.sh`。脚本缩容应用后停止 `kagent-control-plane` 容器，保留数据、PVC、Secret 和会话；不停止 Docker Desktop 集群。下次执行 `./scripts/local-up.sh` 会自动启动节点并恢复组件。

```bash
# UI（前台保持运行）
kubectl --context kind-kagent -n kagent port-forward svc/kagent-ui 8080:8080 --address 127.0.0.1
# 浏览器打开 http://localhost:8080，选择 sre-readonly

# CLI 控制面（另开终端并保持运行）
kubectl --context kind-kagent -n kagent port-forward svc/kagent-controller 18083:8083 --address 127.0.0.1

# 创建会话，记录输出的 Session ID
./kagent-darwin-arm64 --api-url http://127.0.0.1:18083 --gateway-url http://127.0.0.1:18083 \
  agent session create --agent sre-readonly -o json

# 用真实 Session ID 替换 SESSION_ID
./kagent-darwin-arm64 --api-url http://127.0.0.1:18083 --gateway-url http://127.0.0.1:18083 \
  agent invoke --session SESSION_ID --task '请调用工具列出 kagent 命名空间的 Pod，并说明是否就绪。'
```

## 只读边界

工具服务仅注册 Kubernetes 工具，启用 `--read-only`。其 ServiceAccount 仅在 `kagent` 命名空间拥有只读 Role，不允许读取 Secret、执行容器命令或访问其他命名空间。Agent 仅绑定资源查询、describe、Pod 日志和事件四个 MCP 工具。

```bash
./scripts/verify-readonly.sh
./scripts/smoke-agent.sh  # 先启动 18083 转发；会实际调用模型及只读工具
kubectl --context kind-kagent get pods,agents.api.kagent.dev,harnesses.api.kagent.dev -n kagent
```

本地控制面采用 insecure 模式，仅通过回环地址 port-forward 使用。模型请求发送到公网 DeepSeek，输入的诊断内容可能离开集群。不要向模型提供凭证；本地 `deepseek-secret.yaml` 已忽略，禁止提交真实 API Key。

## 后续阶段

1. 当前阶段：统一 v1 基线、启动 Agent、验证模型对话与受限工具调用。
2. 接入实际业务集群、Prometheus 与日志，形成有证据的诊断报告。
3. 告警接入、去重、异步诊断与恢复归档。
4. 独立执行服务、审批、幂等、回滚与恢复验证。

审查依据见 `docs/aiops-review-2026-10-26.md`；本次实测验收见 `docs/stage1-acceptance-2026-10-26.md`。`kagent-config/monitoring/` 保留原有监控设计，本阶段未部署。

## 云端试点

独立 ECS 的准备、安装和验收步骤见 [云端部署](docs/cloud-deployment.md)。
