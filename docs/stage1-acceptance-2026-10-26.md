# 第一阶段验收：本地 v1 只读 SRE Agent

验收时间：2026-10-26，Asia/Shanghai。

## 结果

现有本地 kind 集群上的第一阶段基线已运行并完成验收。专用 context 为 **kind-kagent**，集群名为 **kagent**，节点为 **kagent-control-plane / linux/arm64**。docker-desktop 是独立的 Docker Desktop 内置 Kubernetes；本次未修改该集群，也未修改 kubeconfig 的 current-context（前后均为 kind-kagent）。

| 验收项 | 结果与证据 |
| --- | --- |
| 固定版本 | CLI、kagent、kagent-crds 均为 1.0.0-alpha13；Substrate、PodCertificate 保持既有 0.5.0-alpha2 |
| 安装包完整性 | CLI 与两份 Chart 的本地 SHA256 校验通过，记录于 kagent-config/artifacts.sha256 |
| 依赖恢复 | ate-system 的 API、controller、router、egress、credential provider、RustFS 与 atelet 均运行 |
| kagent 组件 | controller、UI、tools、kmcp、PostgreSQL、WorkerPool 对应的 6 个 Deployment 均 1/1 Available |
| 数据库 | 单 PostgreSQL Pod，数据库与证书 sidecar 共 2/2 Ready；不是数据库主从两副本 |
| v1 配置 | Agent/Harness 服务端 dry-run 通过；旧 kagent.dev/v1alpha2 配置已归档 |
| Agent 运行时 | sre-readonly Ready=True；golden snapshot 完成，模型、工具引用和 Harness 兼容性均通过 |
| 真实模型响应 | TASK_STATE_COMPLETED，回复“只读 SRE Agent 已连接模型。” |
| 真实工具调用 | 调用 k8s_get_resources，namespace=kagent、resource_type=pod；工具返回 6 个实际 Pod，全部 Ready/Running |
| 权限边界 | 11 项 RBAC 检查全部通过，见下文 |
| 重复执行 | scripts/local-up.sh 完整重跑成功；Agent 仍 Ready，无配置漂移导致的服务中断 |
| 可复用验收脚本 | scripts/smoke-agent.sh 执行成功，同时校验真实模型输出、function_call 和 function_response |
| Secret 管理 | 模型改为引用独立 kagent-deepseek-runtime Secret；当前 Helm values 无内联 Key，Chart 渲染不创建模型 Secret |
| 当前 Helm revision | kagent=8，kagent-crds=4，均 deployed |

Agent 当前 prepared revision：`023105ab7d55b68c3aeac69948c9e43a00f2aa0bb882b6d9c344f6203c991c01`。

手动端到端验收会话：`01a178a6-6c44-7063-a4da-2b8395894afe`；工具查询任务：`01a178a7-b809-72d8-a458-78d764968807`。

可复用 smoke 脚本验收会话：`01a178aa-e6ad-746f-a8b8-1a21217b3612`。这些会话保留在本地数据库，可用于复核调用记录；报告不保存模型凭证。

Harness 清单已被服务端接受，Agent 的 ResolvedRefs/Compatible/Ready 均为 True。此 alpha13 环境未给 Harness 填充独立 Ready 状态，因此不以 `kubectl get harness` 的空白 READY 列作为失败或成功依据。

## 权限验收

工具身份：`system:serviceaccount:kagent:kagent-tools`。原集群管理员绑定已由 Helm 清理，最终仅有 kagent 命名空间的 kagent-tools-read-rolebinding。

| 权限 | 预期 / 实际 |
| --- | --- |
| get pods -n kagent | yes / yes |
| get pods/log -n kagent | yes / yes |
| create pods -n kagent | no / no |
| delete pods -n kagent | no / no |
| patch deployments -n kagent | no / no |
| create pods/exec -n kagent | no / no |
| get secrets -n kagent | no / no |
| list secrets -n kagent | no / no |
| get pods -n default | no / no |
| get pods -n kube-system | no / no |
| create rolebindings -n kagent | no / no |

此外，工具服务已启用 --read-only、仅注册 k8s provider，Agent 显式绑定四个查询工具。RBAC 检查使用 Kubernetes 授权接口，不通过真实删除或修改工作负载验证。

## 本次解决的问题

- 将旧运维 Agent、ModelConfig 与安装说明归档，实际基线使用 api.kagent.dev/v1alpha3。ModelConfig 由 Helm 统一生成。
- 修复仓库 Substrate localhost 覆盖，保留服务地址和 PodCertificate 配置；使用固定 Worker 与 ADK 镜像摘要。
- kind 节点直连 GHCR 超时，改用可达镜像源的同摘要 ARM64 运行时；官方及镜像源 manifest digest 已核对一致。
- 镜像源 HTTP/2 下载发生 PROTOCOL_ERROR；为 atelet 和运行时配置 GODEBUG=http2client=0 后，下载及快照生成成功。
- Helm 4 服务端合并与旧 Secret 字段所有权冲突，改用客户端合并。随后发现复用安装器历史值会将占位 Key 写回 Secret，最终改为完整 values + --reset-values，并使用独立 Secret。真实模型凭证未写入新的 Helm values。
- 自动审批拒绝了“把真实 Key 同步到 Helm values”的中间修复方案，原因是可能持久化到 Helm 历史。该方案未执行，已使用独立 Kubernetes Secret 完成替代修复，验收无遗留审批阻塞。

## 使用入口与边界

```bash
./scripts/local-up.sh
./scripts/verify-readonly.sh

# 前台保持该转发运行
kubectl --context kind-kagent -n kagent port-forward svc/kagent-controller 18083:8083 --address 127.0.0.1
# 另一个终端执行；会实际调用模型
./scripts/smoke-agent.sh
```

UI：本次已启动 127.0.0.1:8080 → kagent-ui 的本地转发；选择 sre-readonly。转发进程退出后，按 README 的命令重开。

本次验收基于既有集群恢复与重复应用，**未销毁现有环境或新建空集群重装**。脚本提供固定版本的新装分支，但新装路径仍需在另一测试集群单独验收。

本阶段不包含业务集群访问、Prometheus/Grafana、集中日志、告警接入或自动修复。当前控制面采用本机回环访问的 insecure 模式，非生产部署。运行时镜像固定为 ARM64，脚本会拒绝架构不匹配的集群。
