# SRE Demo - 可观测性与故障演练演示平台

用于演示可观测性监控和故障场景演练的独立环境。

## 📋 组件列表

| 组件 | 命名空间 | 说明 |
| --- | --- | --- |
| ZooKeeper Cluster | sre-demo | 5 节点分布式 ZK 集群 |
| Python ZK App | sre-demo | 示例应用（待实现） |

## 🚀 快速开始

### 1. 部署 ZooKeeper 集群

使用 Kustomize 部署：

```bash
# 部署到开发环境（3 节点）
kubectl apply -k zookeeper/overlays/dev

# 或部署到生产环境（5 节点）
kubectl apply -k zookeeper/overlays/prod

# 或直接部署 base（默认5 节点）
kubectl apply -k zookeeper/base
```

### 2. 验证部署

```bash
# 查看 Pod 状态
kubectl get pods -n sre-demo -l app=zookeeper

# 查看 ZK 集群状态
kubectl exec -n sre-demo zk-0 -- bin/zkServer.sh status

# 测试 ZK 连接
kubectl exec -n sre-demo zk-0 -- bash -c "echo 'ls /' | zkCli.sh -server localhost:2181"
```

## 🔍 可观测性

### 获取 ZK 指标

ZK 提供 4LW 命令获取指标：

```bash
# 查看集群状态
kubectl exec -n sre-demo zk-0 -- bash -c "echo stat | nc localhost 2181"

# 查看详细指标
kubectl exec -n sre-demo zk-0 -- bash -c "echo mntr | nc localhost 2181"

# 查看配置
kubectl exec -n sre-demo zk-0 -- bash -c "echo conf | nc localhost 2181"
```

### 关键指标说明

| 指标 | 含义 |
|------|------|
| `zk_server_state` | 节点角色（leader/follower） |
| `zk_num_alive_connections` | 活跃连接数 |
| `zk_outstanding_requests` | 待处理请求数 |
| `zk_znode_count` | ZNode 数量 |
| `zk_synced_followers` | 已同步的 Follower 数 |
| `zk_avg_latency` | 平均延迟（ms） |

### Grafana Dashboard

已部署 Grafana Dashboard ConfigMap，可通过 Grafana UI 查看 **ZooKeeper Cluster Overview** 仪表盘。

## 💥 故障演练场景

### 场景 1：节点宕机与 Leader 选举

```bash
# 查看当前 Leader
kubectl exec -n sre-demo zk-0 -- bin/zkServer.sh status

# 删除 Leader Pod（假设 zk-0 是 Leader）
kubectl delete pod zk-0 -n sre-demo

# 观察：
# 1. Pod 自动重建
# 2. 新 Leader 选举
# 3. Grafana 指标变化
# 4. Prometheus 告警触发（如有配置）

# 恢复后检查状态
kubectl exec -n sre-demo zk-0 -- bin/zkServer.sh status
```

### 场景 2：多数派故障（Quorum Loss）

```bash
# 同时停止 3 个节点（超过半数）
kubectl delete pod zk-0 zk-1 zk-2 -n sre-demo

# 观察：
# 1. 集群不可用
# 2. 客户端连接失败
# 3. 指标显示异常

# 恢复（等待 Pod 重建）
kubectl wait --for=condition=Ready pods -l app=zookeeper -n sre-demo --timeout=300s
```

### 场景 3：资源压力

```bash
# 临时限制 ZK Pod 资源
kubectl set resources statefulset zk -n sre-demo \
  --limits=cpu=100m,memory=256Mi

# 观察延迟和吞吐量变化

# 恢复原始资源配置
kubectl rollout undo statefulset zk -n sre-demo
```

### 场景 4：网络分区模拟

```bash
# 使用 NetworkPolicy 模拟 zk-4 网络隔离
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-zk-4
  namespace: sre-demo
spec:
  podSelector:
    matchLabels:
      statefulset.kubernetes.io/pod-name: zk-4
  policyTypes:
  - Ingress
  - Egress
EOF

# 观察 zk-4 被隔离后的集群状态

# 恢复网络
kubectl delete networkpolicy isolate-zk-4 -n sre-demo
```

## 📊 监控指标说明

| 指标 | 含义 | 告警阈值建议 |
|------|------|-------------|
| `zk_num_alive_connections` | 活跃连接数 | > 1000 |
| `zk_outstanding_requests` | 待处理请求数 | > 10 |
| `zk_avg_latency` | 平均延迟（ms） | > 100 |
| `zk_followers` | Follower 数量 | < 4 |
| `zk_synced_followers` | 已同步 Follower | < 4 |

## 🔧 维护命令

```bash
# 查看 ZK 日志
kubectl logs zk-0 -n sre-demo

# 进入 ZK Shell
kubectl exec -it zk-0 -n sre-demo -- bin/zkCli.sh

# 滚动重启
kubectl rollout restart statefulset zk -n sre-demo

# 扩缩容（注意：ZK 推荐奇数节点）
kubectl scale statefulset zk -n sre-demo --replicas=7

# 删除整个集群
kubectl delete -k zookeeper/base
```

## 📁 目录结构（Kustomize 格式）

```
sre-demo/
├── README.md                          # 本文档
└── zookeeper/
    ├── base/                          # 基础配置
    │   ├── kustomization.yaml         # Kustomize 主文件
    │   ├── namespace.yaml             # 命名空间
    │   ├── configmap.yaml             # ZK 配置
    │   ├── statefulset.yaml           # StatefulSet (5 节点)
    │   ├── service.yaml               # Service 定义
    │   └── grafana-dashboard.yaml     # Grafana 仪表盘
    └── overlays/                      # 环境覆盖
        ├── dev/                       # 开发环境（3 节点）
        │   └── kustomization.yaml
        └── prod/                      # 生产环境（5 节点 + 更多资源）
            └── kustomization.yaml
```

## 🎯 Kustomize 使用说明

### 预览变更

```bash
# 预览 dev 环境配置
kubectl kustomize zookeeper/overlays/dev

# 预览 prod 环境配置
kubectl kustomize zookeeper/overlays/prod
```

### 自定义配置

创建新的 overlay：

```bash
# 创建自定义 overlay
mkdir -p zookeeper/overlays/custom
cat > zookeeper/overlays/custom/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: sre-demo

resources:
  - ../../base

patches:
  - target:
      kind: StatefulSet
      name: zk
    patch: |
      - op: replace
        path: /spec/replicas
        value: 7

images:
  - name: zookeeper
    newTag: "3.9.0"
EOF

# 部署自定义配置
kubectl apply -k zookeeper/overlays/custom
```