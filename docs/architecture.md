# 架构设计文档

## 系统架构概览

kagent 是一个基于大语言模型的 Kubernetes 智能运维助手系统，采用多 Agent 架构设计，通过 MCP（Model Context Protocol）协议集成各类运维工具。

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

## 核心组件

### 1. kagent-ui（Web 交互界面）

- **作用**：提供用户与 AI 运维助手交互的 Web 界面
- **命名空间**：kagent
- **访问方式**：`kubectl port-forward -n kagent svc/kagent-ui 8080:8080`
- **功能**：
  - 选择不同 Agent 进行对话
  - 查看对话历史
  - 展示工具执行结果

### 2. kagent-controller（控制器）

- **作用**：系统核心控制器，负责 API 服务、Agent 编排和会话管理
- **命名空间**：kagent
- **功能**：
  - 接收用户请求并路由到对应 Agent
  - 管理 Agent 生命周期
  - 维护会话状态
  - 调度 MCP 工具执行

### 3. Agent Pods（智能体）

- **作用**：运行 LLM 对话的独立 Pod，每个 Agent 专注特定领域
- **命名空间**：kagent
- **特点**：
  - 每个 Agent 是独立的 K8s CRD 资源
  - 共享同一个 LLM Provider 配置
  - 通过 MCP 协议调用工具

### 4. PostgreSQL（数据库）

- **作用**：存储会话数据和配置信息
- **命名空间**：kagent
- **存储**：PVC（local-path），500Mi
- **持久化**：Scale 后 PVC 保留，数据安全

### 5. MCP Tools（工具服务）

- **kagent-tools**：内置 MCP 工具服务，提供 kubectl 等 K8s 操作能力
- **grafana-mcp**：Grafana MCP 工具服务，提供监控数据查询和仪表盘操作

### 6. 监控栈（Prometheus + Grafana）

- **命名空间**：monitoring
- **Prometheus**：指标收集和存储，15 天留存
- **Grafana**：监控可视化，NodePort 31080
- **kube-state-metrics**：K8s 对象指标

## Agent 架构

### 已启用的 Agent

| Agent | 职责 | 典型场景 |
|-------|------|----------|
| **k8s-agent** | 集群资源管理 | Pod 状态查询、事件查看、资源描述 |
| **promql-agent** | Prometheus 查询 | 指标分析、告警规则编写 |
| **helm-agent** | Helm Chart 管理 | Release 查看、升级、回滚 |
| **observability-agent** | 可观测性分析 | Grafana 仪表盘操作、监控数据分析 |

### 可选 Agent（默认禁用）

- `istio-agent`：Istio 服务网格管理
- `argo-rollouts-agent`：Argo Rollouts 渐进式发布
- `cilium-debug-agent`：Cilium 网络调试
- `cilium-manager-agent`：Cilium 管理
- `cilium-policy-agent`：Cilium 网络策略
- `kgateway-agent`：Kubernetes Gateway API

### Agent CRD 结构

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

### Agent 交互流程

```
用户 → kagent-ui → kagent-controller → Agent Pod → LLM Provider
                                              ↓
                                         MCP Tools → K8s/Prometheus/Grafana
                                              ↓
                                         返回结果 → 用户
```

## 数据流

### 1. 用户请求流

1. 用户在 kagent-ui 输入自然语言请求
2. kagent-controller 接收请求，选择对应 Agent
3. Agent Pod 调用 LLM 生成工具调用指令
4. MCP Tools 执行实际操作（kubectl、PromQL 等）
5. 结果返回给 LLM 生成自然语言回复
6. 回复展示给用户

### 2. 数据持久化

| 数据类型 | 存储位置 | 持久性 |
|---------|---------|--------|
| 会话数据 | PostgreSQL | 高（PVC 保护） |
| Agent 配置 | etcd（K8s CRD） | 高（K8s 内置） |
| ModelConfig | etcd + Helm | 高（Helm 管理） |
| Prometheus 指标 | emptyDir | 低（重启丢失） |
| Grafana 配置 | ConfigMap | 高（K8s 内置） |

## 网络架构

### 服务发现

- 所有服务通过 K8s Service 进行服务发现
- Agent 通过 MCP 协议与 Tools 通信
- 控制器通过 K8s API 管理 Agent CRD

### 端口映射

| 服务 | 内部端口 | 外部访问方式 |
|------|---------|-------------|
| kagent-ui | 8080 | port-forward |
| Grafana | 80 | NodePort 31080 |
| Prometheus | 9090 | port-forward |

## 安全设计

### Secret 管理

- API Key 通过 K8s Secret 存储
- 使用 `.env` 文件本地管理，不提交到 Git
- 通过 `kubectl create secret` 命令创建

### 访问控制

- Grafana 默认匿名查看权限
- 生产环境建议配置认证和 RBAC

## 扩展性

### 添加新 Agent

1. 在 `values.yaml` 中添加 Agent 配置
2. 定义 systemMessage 和 tools
3. 执行 `helm upgrade` 部署

### 切换 LLM Provider

支持多种 Provider：
- **OpenAI**：兼容 DeepSeek、Moonshot 等
- **Anthropic**：Claude 系列
- **AzureOpenAI**：Azure OpenAI 服务
- **Ollama**：本地模型
- **Gemini**：Google Gemini

### 集成外部工具

通过 MCP 协议可集成任意工具服务，只需：
1. 部署 MCP Server
2. 在 Agent 配置中引用