# kagent-ops - K8s AI 运维助手配置与实践

[kagent](https://kagent.dev) 的部署配置、运维指南和最佳实践，帮助你快速搭建基于大语言模型的 Kubernetes 智能运维助手。

## 🎯 项目概述

本仓库是 [kagent](https://github.com/kagent-dev/kagent) 的**配置与运维实践仓库**（非上游源码），包含 Helm values、监控配置、部署文档和 SRE 实践指南。kagent 是一个部署在 Kubernetes 集群中的 AI 运维助手系统，它将大语言模型（LLM）与 Kubernetes 运维工具结合，让用户可以通过自然语言完成复杂的运维任务。

### 核心特性

- **自然语言交互**：用日常语言描述需求，AI 自动执行运维操作
- **多 Agent 架构**：不同 Agent 专注不同领域（K8s、PromQL、Helm、可观测性）
- **MCP 工具集成**：通过 Model Context Protocol 集成 kubectl、Prometheus、Grafana 等工具
- **可观测性支持**：内置 Grafana MCP，支持监控数据分析和仪表盘操作
- **本地化部署**：完全在本地 K8s 集群运行，数据不出集群

## 🏗️ 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                      kagent-ui                          │
│                   (Web 交互界面)                         │
│            http://localhost:8080                         │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│                  kagent-controller                       │
│         (API Server + Agent 编排 + Session 管理)          │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
┌──────────────┐ ┌──────────┐ ┌──────────────┐
│  Agent Pods  │ │PostgreSQL│ │  MCP Tools   │
│ (LLM 对话)   │ │ (存储)    │ │ (工具执行)    │
└──────────────┘ └──────────┘ └──────────────┘
        │                              │
        ▼                              ▼
┌──────────────────┐          ┌──────────────────┐
│   LLM Provider   │          │   Grafana MCP    │
│ (DeepSeek/OpenAI)│          │   (监控工具)      │
└──────────────────┘          └──────────────────┘
```

### 组件说明

| 组件 | 作用 | 命名空间 |
|------|------|----------|
| **kagent-ui** | Web 交互界面 | kagent |
| **kagent-controller** | API 服务器、Agent 编排、会话管理 | kagent |
| **Agent Pods** | 运行 LLM 对话的独立 Pod | kagent |
| **PostgreSQL** | 存储会话和配置数据 | kagent |
| **kagent-tools** | 内置 MCP 工具服务 | kagent |
| **kagent-grafana-mcp** | Grafana MCP 工具服务 | kagent |
| **Prometheus** | 指标收集和存储 | monitoring |
| **Grafana** | 监控可视化 | monitoring |

## 🚀 快速开始

### 前置条件

- Kubernetes 集群（推荐 K3s/K8s 1.28+）
- Helm 3.x
- DeepSeek API Key（[获取地址](https://platform.deepseek.com/)）

### 1. 配置 API Key

```bash
cp .env.example .env
# 编辑 .env 填入真实的 DEEPSEEK_API_KEY
```

### 2. 部署监控栈（Prometheus + Grafana）

```bash
# 添加 Helm 仓库
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 创建命名空间
kubectl create namespace monitoring

# 部署 kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --values kagent-config/monitoring/values.yaml
```

### 3. 部署 kagent

```bash
# 创建命名空间和 Secret
kubectl create namespace kagent --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic kagent-deepseek \
  --from-literal=DEEPSEEK_API_KEY=$(grep DEEPSEEK_API_KEY .env | cut -d= -f2) \
  -n kagent --dry-run=client -o yaml | kubectl apply -f -

# 部署 CRDs
helm upgrade --install kagent-crds \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  -n kagent --create-namespace --version 0.10.1

# 部署 kagent
helm upgrade --install kagent \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  -n kagent --version 0.10.1 --values kagent-config/helm/values.yaml
```

### 4. 访问服务

> **WSL2 用户注意**：NodePort 端口无法从 Windows 直接访问，必须使用 `port-forward`。

```bash
# Grafana（监控面板）
kubectl port-forward -n monitoring svc/monitoring-grafana 31080:80
# 浏览器: http://localhost:31080
# 账号: admin / admin

# kagent UI（AI 运维助手）
kubectl port-forward -n kagent svc/kagent-ui 8080:8080
# 浏览器: http://localhost:8080
```

> 以上命令会持续占用终端。如需后台运行，可加 `&` 或使用多个终端窗口。

## 📦 项目结构

```
kagent-ops/
├── .env.example                    # API Key 模板
├── .env                            # API Key（不提交到 git）
├── .gitignore
├── README.md                       # 本文档
├── CLAUDE.md                       # AI 协作说明
├── kagent-config/
│   ├── helm/
│   │   └── values.yaml             # kagent Helm 配置
│   ├── monitoring/
│   │   ├── values.yaml             # kube-prometheus-stack Helm 配置
│   │   ├── blackbox-values.yaml    # blackbox-exporter 独立 chart 配置
│   │   ├── beyla-values.yaml       # Beyla eBPF 零插桩 RED 配置
│   │   ├── RUNBOOK.md              # 业务服务可观测性部署 Runbook
│   │   ├── probes/                 # Probe CRD（drinkzen / party-helper）
│   │   ├── prometheus-rules/       # HTTP 可用性告警规则
│   │   └── dashboards/             # Grafana Dashboard（ConfigMap 自动加载）
│   └── crds/
│       └── model-config.yaml       # ModelConfig 参考
├── docs/
│   ├── architecture.md             # 架构设计文档
│   ├── development.md              # 开发者文档
│   ├── contributions.md            # 贡献计划与社区 PR
│   └── observability/
│       ├── observability-design.md # 业务可观测性总体设计（Phase 1 指标）
│       └── slo-sli-error-budget.md # SLO/SLI/Error Budget 实践
```

## 🤖 Agent 说明

### 已启用的 Agent

| Agent | 职责 | 典型问题 |
|-------|------|----------|
| **k8s-agent** | 集群资源管理、Pod 状态查询、事件查看 | "查看 kagent 命名空间下所有 Pod 状态" |
| **promql-agent** | Prometheus 查询、指标分析、告警规则编写 | "查询过去 1 小时的 CPU 使用率" |
| **helm-agent** | Helm Chart 管理、发布/回滚操作 | "查看 kagent 的 Helm release 状态" |
| **observability-agent** | 可观测性分析、Grafana 仪表盘操作 | "查看 Grafana 中有哪些 Dashboard" |

### Agent 架构

每个 Agent 是一个独立的 K8s CRD 资源：

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-agent
  namespace: kagent
spec:
  type: Declarative
  declarative:
    runtime: go
    modelConfig: default-model-config    # 引用 LLM 配置
    systemMessage: |                      # 系统提示词
      You are KubeAssist...
    tools:                                # 绑定的 MCP 工具
      - mcpServer:
          name: kagent-tool-server
          toolNames:
            - k8s_get_resources
            - k8s_describe_resource
    a2aConfig:
      skills:                            # Agent 技能描述
        - name: Cluster Diagnostics
          description: 分析和诊断集群问题
```

### Agent 之间的关系

```
┌─────────────────────────────────────────────────────┐
│                   kagent-ui                          │
│              (用户选择哪个 Agent 对话)                │
└───────────────────────┬─────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   ┌─────────┐    ┌──────────┐    ┌──────────┐
   │ k8s-agent│    │promql-agent│   │helm-agent │
   └────┬────┘    └─────┬────┘    └─────┬────┘
        │               │               │
        └───────────────┼───────────────┘
                        ▼
              ┌──────────────────┐
              │  default-model   │
              │    -config       │  ← 共用 LLM
              └──────────────────┘
```

## ⚙️ 配置指南

### 切换 LLM 模型

编辑 `kagent-config/helm/values.yaml`：

```yaml
providers:
  default: openAI

  openAI:
    provider: OpenAI
    model: "deepseek-flash"              # 可改为 deepseek-reasoner 等
    apiKeySecretRef: kagent-deepseek
    apiKeySecretKey: DEEPSEEK_API_KEY
    config:
      baseUrl: "https://api.deepseek.com/v1"
```

支持的 Provider：
- **OpenAI**：兼容 DeepSeek、Moonshot 等
- **Anthropic**：Claude 系列
- **AzureOpenAI**：Azure OpenAI 服务
- **Ollama**：本地模型
- **Gemini**：Google Gemini

### 启用/禁用 Agent

```yaml
# 根级别配置，不是嵌套在 agents 下
k8s-agent:
  enabled: true
promql-agent:
  enabled: true
helm-agent:
  enabled: true
observability-agent:
  enabled: true

# 禁用的 Agent
istio-agent:
  enabled: false
argo-rollouts-agent:
  enabled: false
```

### 外部数据库

生产环境建议使用外部 PostgreSQL：

```yaml
database:
  postgres:
    url: "postgres://user:pass@host:5432/dbname?sslmode=disable"
    bundled:
      enabled: false
```

## 🔧 服务管理

### 临时停止

保留所有配置和数据，scale down 到 0：

```bash
kubectl scale deployment -n kagent --all --replicas=0
```

### 恢复服务

```bash
kubectl scale deployment -n kagent --all --replicas=1
kubectl get pods -n kagent
```

### 卸载

```bash
# 卸载 kagent
helm uninstall kagent -n kagent
helm uninstall kagent-crds -n kagent
kubectl delete ns kagent

# 卸载监控栈
helm uninstall monitoring -n monitoring
kubectl delete ns monitoring
```

## 📊 状态持久化

| 组件 | 存储方式 | Scale 安全性 |
|------|---------|-------------|
| PostgreSQL | PVC (local-path) | ✅ PVC 在 scale 后保留 |
| Agent CRDs | etcd (K8s 内置) | ✅ 不受 scale 影响 |
| ModelConfig | etcd + Helm | ✅ 不受 scale 影响 |
| Session 数据 | PostgreSQL | ✅ PVC 保护 |
| Prometheus 数据 | PVC (10Gi，保留 15 天) | ✅ 重启不丢失 |
| Grafana 配置 | ConfigMap | ✅ 不受 scale 影响 |

> ⚠️ 不要通过 UI 创建 Agent，否则 scale 后可能出现 "already exists" 冲突。
> 所有 Agent 应通过 `values.yaml` + `helm upgrade` 管理。

## 🔗 参考链接

- [kagent 官方文档](https://www.kagent.dev/docs)
- [Helm 配置参考](https://www.kagent.dev/docs/kagent/resources/helm)
- [DeepSeek API](https://platform.deepseek.com/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
