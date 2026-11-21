# 概念、依赖与阅读地图

本仓库是 **kagent 运维配置仓**（非上游源码）。现行基线：kagent / CLI **1.0.0-alpha13**，Substrate / PodCertificate **0.5.0-alpha2**。

**一套业务配置，两处环境附录：** Agent / Harness / Helm / 安装器版本钉扎共用；仅集群形态、CLI 二进制、镜像加速方式因环境而异。

## 建议阅读顺序

1. 本文  
2. [架构](architecture.md)  
3. 根目录 [README.md](../README.md)（本地）  
4. [云端部署](cloud-deployment.md)（ECS / k3s 环境附录）  
5. [阶段 1 验收](stage1-acceptance-2026-10-26.md)  
6. 改 Agent：[development.md](development.md)、[AGENT-CREATION-GUIDE.md](../AGENT-CREATION-GUIDE.md)

协作红线：[CLAUDE.md](../CLAUDE.md)。监控目录 `kagent-config/monitoring/` 本阶段未部署。

## 核心概念

```text
你（浏览器 / CLI）→ 仅 127.0.0.1 port-forward（insecure）
  → kagent：controller / ui / tools / PG / ModelConfig(Helm)
  → Agent sre-readonly + Harness sre-readonly（同一份清单）
  → ate-system：atelet / WorkerPool+gVisor / rustfs
  → DeepSeek ← Secret kagent-deepseek-runtime
```

| 名词 | 含义 |
| --- | --- |
| **Agent** | 提示词与工具白名单 |
| **Harness** | 运行时镜像、WorkerPool、快照位置、`GODEBUG` |
| **atelet** | 自建 Image cache 拉 ADK、打 golden snapshot |
| **只读边界** | 仅诊断 `kagent` 命名空间 |

## 通用配置入口（唯一）

| 用途 | 路径 |
| --- | --- |
| Helm | `kagent-config/helm/values.yaml` |
| 安装器 | `kagent-install-config.yaml`（本地与云端共用） |
| Agent | `kagent-config/crds/agents.yaml` |
| Harness | `kagent-config/crds/harness.yaml`（南大源 + **多架构** digest `ae01c3a6...` + `GODEBUG`） |
| 脚本 | `scripts/local-up.sh` / `cloud-install.sh` / `verify-readonly.sh` / `smoke-agent.sh` |

`kagent-config/crds/agents/` 下其它 Agent 未纳入首期。

## 两套拉镜像路径

| 路径 | 谁拉 | 怎么配 | 典型对象 |
| --- | --- | --- | --- |
| **A. containerd** | kubelet | kind：[kind-registry-mirror.md](kind-registry-mirror.md)；k3s：`deploy/cloud/registries.yaml.example` | pause、postgres、rustfs、控制面、worker |
| **B. atelet** | atelet | Harness 的 `workload.image` + `kubectl -n ate-system set env daemonset/atelet GODEBUG=http2client=0` | **golang-adk** |

`ctr` 只喂 A，不喂 B。Helm Chart 是第三条路：优先仓库内 `kagent-*.tgz`。

## 环境差异（附录，不是第二套业务）

| 项 | 本地 kind | 云端 k3s |
| --- | --- | --- |
| Context | `kind-kagent` | 专用 ECS context（非 kind/docker-desktop） |
| 节点架构 | 多为 arm64 | 多为 amd64（Harness 多架构兼容两者） |
| CLI | `kagent-darwin-arm64`（gitignore） | `kagent-linux-*` + `deploy/cloud/cli.sha256` |
| gVisor | 环境已通 | 须自装 runsc + RuntimeClass `gvisor` |
| 镜像加速 | kind hosts.toml | `/etc/rancher/k3s/registries.yaml` |
| 模型 / Secret | 同一约定 | 同一约定 |
