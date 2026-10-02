# kagent-ops - K8s AI 运维助手配置与实践

## 项目概述

本仓库是 [kagent](https://github.com/kagent-dev/kagent) 的**配置与运维实践仓库**（非上游源码）。

- **kagent**：开源 Kubernetes AI 运维助手项目
- **kagent-ops**：本项目，包含 Helm values、监控配置、部署文档和 SRE 实践指南

## 项目结构

```
kagent-ops/
├── .env.example                    # API Key 模板
├── .env                            # API Key（不提交到 git）
├── .gitignore
├── README.md                       # 项目主文档
├── CLAUDE.md                       # 本文件
├── kagent-config/
│   ├── helm/
│   │   └── values.yaml             # kagent Helm 配置
│   ├── monitoring/
│   │   ├── values.yaml             # 监控栈 Helm 配置（kube-prometheus-stack + blackbox）
│   │   ├── RUNBOOK.md              # 业务服务可观测性部署 Runbook
│   │   ├── blackbox-config.yaml    # Blackbox 探测模块 ConfigMap
│   │   ├── probes/                 # Probe CRD（drinkzen / party-helper）
│   │   └── prometheus-rules/       # HTTP 可用性告警规则
│   └── crds/
│       └── model-config.yaml       # ModelConfig 参考配置
├── docs/
│   ├── architecture.md             # 架构设计文档
│   ├── development.md              # 开发者文档
│   ├── contributions.md            # 社区贡献计划
│   └── observability/
│       └── slo-sli-error-budget.md # SLO/SLI/Error Budget 实践
```

## 常用命令

### 部署操作

```bash
# 配置 API Key
cp .env.example .env
# 编辑 .env 填入真实的 DEEPSEEK_API_KEY

# 部署监控栈
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl create namespace monitoring
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --values kagent-config/monitoring/values.yaml

# 部署 kagent
kubectl create namespace kagent --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic kagent-deepseek \
  --from-literal=DEEPSEEK_API_KEY=$(grep DEEPSEEK_API_KEY .env | cut -d= -f2) \
  -n kagent --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kagent-crds \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  -n kagent --create-namespace --version 0.10.1

helm upgrade --install kagent \
  oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  -n kagent --version 0.10.1 --values kagent-config/helm/values.yaml
```

### 服务管理

```bash
# 临时停止（保留数据）
kubectl scale deployment -n kagent --all --replicas=0

# 恢复服务
kubectl scale deployment -n kagent --all --replicas=1

# 查看状态
kubectl get pods -n kagent
kubectl get agents -n kagent
```

### 访问服务

```bash
# kagent UI
kubectl port-forward -n kagent svc/kagent-ui 8080:8080

# Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 31080:80
```

## 配置说明

### LLM Provider 配置

编辑 `kagent-config/helm/values.yaml`：

```yaml
providers:
  default: openAI
  openAI:
    provider: OpenAI
    model: "deepseek-flash"
    apiKeySecretRef: kagent-deepseek
    apiKeySecretKey: DEEPSEEK_API_KEY
    config:
      baseUrl: "https://api.deepseek.com/v1"
```

支持的 Provider：OpenAI（兼容 DeepSeek）、Anthropic、AzureOpenAI、Ollama、Gemini

### Agent 启用/禁用

```yaml
# 根级别配置（不是嵌套在 agents 下）
k8s-agent:
  enabled: true
promql-agent:
  enabled: true
helm-agent:
  enabled: true
observability-agent:
  enabled: true
```

## 注意事项

1. **不要通过 UI 创建 Agent**：否则 scale 后可能出现 "already exists" 冲突
2. **WSL2 环境**：NodePort 端口无法从 Windows 直接访问，必须使用 `port-forward`
3. **数据持久化**：PostgreSQL 和 Prometheus 均使用 PVC（Prometheus 保留 15 天），重启不丢数据

## 参考链接

- [kagent 官方文档](https://www.kagent.dev/docs)
- [kagent GitHub](https://github.com/kagent-dev/kagent)
- [Helm 配置参考](https://www.kagent.dev/docs/kagent/resources/helm)
- [DeepSeek API](https://platform.deepseek.com/)