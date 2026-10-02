# 开发者文档

## 开发环境准备

### 前置条件

- Kubernetes 集群（K3s 或 K8s 1.28+）
- Helm 3.x
- kubectl 命令行工具
- DeepSeek API Key（[获取地址](https://platform.deepseek.com/)）

### 本地开发集群推荐

**使用 K3s（轻量级）：**
```bash
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**使用 kind（Docker 内运行）：**
```bash
kind create cluster --name kagent-dev
```

## 项目结构

```
kagent-ops/
├── .env.example                    # API Key 模板
├── .env                            # API Key（不提交到 git）
├── .gitignore
├── README.md                       # 项目主文档
├── CLAUDE.md                       # AI 协作说明
├── kagent-config/
│   ├── helm/
│   │   └── values.yaml             # kagent Helm 配置
│   ├── monitoring/
│   │   └── values.yaml             # 监控栈 Helm 配置
│   ├── crds/
│   │   └── model-config.yaml       # ModelConfig 参考配置
│   └── secrets/
│       └── api-keys.yaml           # Secret 模板（仅供参考，本地）
├── docs/
│   ├── architecture.md             # 架构设计文档
│   ├── development.md              # 本文档
│   ├── contributions.md            # 贡献计划与社区 PR
│   └── observability/
│       └── slo-sli-error-budget.md # SLO/SLI/Error Budget 实践
```

## 配置文件详解

### kagent-config/helm/values.yaml

主要配置文件，包含：

```yaml
# LLM Provider 配置
providers:
  default: openAI
  openAI:
    provider: OpenAI
    model: "deepseek-chat"
    apiKeySecretRef: kagent-deepseek
    apiKeySecretKey: DEEPSEEK_API_KEY
    config:
      baseUrl: "https://api.deepseek.com/v1"

# Agent 启用/禁用配置
k8s-agent:
  enabled: true
promql-agent:
  enabled: true
helm-agent:
  enabled: true
observability-agent:
  enabled: true

# 数据库配置
database:
  postgres:
    bundled:
      enabled: true
      persistence:
        enabled: true
        size: 500Mi
```

### kagent-config/monitoring/values.yaml

Prometheus + Grafana 配置：

```yaml
# Grafana 配置
grafana:
  service:
    type: NodePort
    nodePort: 31080
  adminUser: admin
  adminPassword: admin
  anonymous:
    enabled: true

# Prometheus 配置
prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        memory: 400Mi
```

## 常用操作

### 部署操作

**首次部署：**
```bash
# 1. 配置 API Key
cp .env.example .env
# 编辑 .env 填入真实的 DEEPSEEK_API_KEY

# 2. 部署监控栈
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl create namespace monitoring
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --values kagent-config/monitoring/values.yaml

# 3. 部署 kagent
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

### 更新配置

**修改 Agent 配置后：**
```bash
# 编辑 kagent-config/helm/values.yaml
# 然后执行
helm upgrade kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  -n kagent --version 0.10.1 --values kagent-config/helm/values.yaml
```

**修改监控配置后：**
```bash
# 编辑 kagent-config/monitoring/values.yaml
# 然后执行
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --values kagent-config/monitoring/values.yaml
```

### 服务管理

**临时停止（保留数据）：**
```bash
kubectl scale deployment -n kagent --all --replicas=0
```

**恢复服务：**
```bash
kubectl scale deployment -n kagent --all --replicas=1
kubectl get pods -n kagent
```

**完全卸载：**
```bash
# 卸载 kagent
helm uninstall kagent -n kagent
helm uninstall kagent-crds -n kagent
kubectl delete ns kagent

# 卸载监控栈
helm uninstall monitoring -n monitoring
kubectl delete ns monitoring
```

## 调试指南

### 查看 Pod 状态

```bash
# kagent 命名空间
kubectl get pods -n kagent
kubectl describe pod <pod-name> -n kagent

# monitoring 命名空间
kubectl get pods -n monitoring
```

### 查看日志

```bash
# kagent-controller 日志
kubectl logs -f deployment/kagent-controller -n kagent

# Agent Pod 日志
kubectl logs -f <agent-pod-name> -n kagent

# Grafana 日志
kubectl logs -f deployment/monitoring-grafana -n monitoring
```

### 查看 Agent CRD 状态

```bash
# 列出所有 Agent
kubectl get agents -n kagent

# 查看特定 Agent 详情
kubectl describe agent k8s-agent -n kagent

# 查看 ModelConfig
kubectl get modelconfigs -n kagent
```

### 端口转发调试

```bash
# kagent UI
kubectl port-forward -n kagent svc/kagent-ui 8080:8080

# Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 31080:80

# Prometheus
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```

## 常见问题

### Q: Agent Pod 启动失败

检查：
1. API Key Secret 是否正确创建
2. LLM Provider 配置是否正确
3. 网络是否能访问 LLM API

```bash
kubectl describe pod <pod-name> -n kagent
kubectl logs <pod-name> -n kagent
```

### Q: Scale 后出现 "already exists" 错误

原因：通过 UI 创建了 Agent，与 Helm 管理的 Agent 冲突

解决：
```bash
# 删除通过 UI 创建的 Agent
kubectl delete agent <agent-name> -n kagent
# 然后重新 scale
kubectl scale deployment -n kagent --all --replicas=1
```

### Q: Prometheus 数据重启后丢失

原因：默认使用 emptyDir 存储

解决：修改 `kagent-config/monitoring/values.yaml`，启用 PVC：
```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
```

### Q: 如何切换到其他 LLM Provider

编辑 `kagent-config/helm/values.yaml`：

**Anthropic Claude：**
```yaml
providers:
  default: anthropic
  anthropic:
    provider: Anthropic
    model: "claude-3-sonnet-20240229"
    apiKeySecretRef: kagent-anthropic
    apiKeySecretKey: ANTHROPIC_API_KEY
```

**本地 Ollama：**
```yaml
providers:
  default: ollama
  ollama:
    provider: Ollama
    model: "llama3"
    config:
      baseUrl: "http://ollama.ollama.svc.cluster.local:11434"
```

## 开发工作流

### 1. 修改配置

```bash
# 编辑配置文件
vim kagent-config/helm/values.yaml
```

### 2. 验证配置

```bash
# 模板渲染验证
helm template kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  -n kagent --values kagent-config/helm/values.yaml
```

### 3. 应用变更

```bash
helm upgrade kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  -n kagent --version 0.10.1 --values kagent-config/helm/values.yaml
```

### 4. 验证部署

```bash
kubectl get pods -n kagent
kubectl get agents -n kagent
```

## 参考资源

- [kagent 官方文档](https://www.kagent.dev/docs)
- [Helm 配置参考](https://www.kagent.dev/docs/kagent/resources/helm)
- [kagent GitHub](https://github.com/kagent-dev/kagent)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [DeepSeek API](https://platform.deepseek.com/)