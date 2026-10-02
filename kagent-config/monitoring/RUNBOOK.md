# 业务服务可观测性部署 Runbook

> 适用范围：本地 docker-desktop / 自有 K8s 集群
> 监控目标：`drinkzen`、`party-helper` 两个命名空间

## 📦 交付物清单

| 文件 | 资源类型 | 说明 |
| --- | --- | --- |
| `kagent-config/monitoring/values.yaml` | Helm Values | 启用 blackbox-exporter（已更新） |
| `kagent-config/monitoring/blackbox-config.yaml` | ConfigMap | Blackbox 探测模块（http_2xx_healthz、http_2xx_root） |
| `kagent-config/monitoring/probes/drinkzen-api.yaml` | Probe | drinkzen API 探测 |
| `kagent-config/monitoring/probes/drinkzen-admin.yaml` | Probe | drinkzen Admin 探测 |
| `kagent-config/monitoring/probes/party-helper-api.yaml` | Probe | party-helper API 探测 |
| `kagent-config/monitoring/probes/party-helper-admin.yaml` | Probe | party-helper Admin 探测 |
| `kagent-config/monitoring/prometheus-rules/http-availability.yaml` | PrometheusRule | 探测失败/慢响应告警 |

## 🚀 部署步骤

### 1. 添加 Helm 仓库（如果未添加）

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 2. 部署 kube-prometheus-stack

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 安装 Prometheus Operator 全家桶（含 blackbox-exporter）
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --values kagent-config/monitoring/values.yaml
```

### 3. 应用 Blackbox 模块配置

```bash
kubectl apply -f kagent-config/monitoring/blackbox-config.yaml
```

> ⚠️ 该 ConfigMap 名称必须与 `values.yaml` 中 `blackboxExporter.config.existingConfigMap` 字段一致

### 4. 应用 Probe（探测任务）

```bash
kubectl apply -f kagent-config/monitoring/probes/
```

### 5. 应用告警规则

```bash
kubectl apply -f kagent-config/monitoring/prometheus-rules/
```

## ✅ 验证

```bash
# 1. blackbox-exporter pod 应已起来
kubectl -n monitoring get pods -l app.kubernetes.io/name=blackbox-exporter

# 2. Probe 应处于 Running
kubectl -n monitoring get probes

# 3. Prometheus 应已加载规则
kubectl -n monitoring
exec prometheus-monitoring-kube-prometheus-prometheus-0 -- \
  promtool check rules /etc/prometheus/rules/prometheus-monitoring-kube-prometheus-prometheus-rulefiles-0/*.yaml

# 4. 查询探针指标
kubectl -n monitoring
port-forward svc/prometheus-operated 9090:9090
# 浏览器：http://localhost:9090
# 查询：probe_success{namespace=~"drinkzen|party-helper"}
```

## 🔍 常用 PromQL

```promql
# 各服务 24h 可用率
avg_over_time(
  probe_success{namespace=~"drinkzen|party-helper"}[24h]
)

# 各服务 P95 响应时间
histogram_quantile(
  0.95,
  sum by (namespace, service, le) (
    rate(probe_duration_seconds_bucket{namespace=~"drinkzen|party-helper"}[5m])
  )
)

# 当前所有未通过探测
probe_success{namespace=~"drinkzen|party-helper"} == 0
```

## 🚨 告警列表

| 告警名 | 触发条件 | 持续时间 | 严重度 |
| --- | --- | --- | --- |
| HttpProbeFailed | `probe_success == 0` | 2 分钟 | warning |
| HttpProbeSlow | P95 响应时间 > 1s | 5 分钟 | warning |
| TlsCertExpiringSoon | 证书 < 7 天过期 | 1 小时 | warning |

## 🧪 模拟故障（验证告警）

```bash
# 制造一次 API 不可达
kubectl -n drinkzen scale deploy drinkzen-api-local --replicas=0

# 2 分钟后应触发 HttpProbeFailed
# 恢复：
kubectl -n drinkzen scale deploy drinkzen-api-local --replicas=1
```

## 📈 Grafana Dashboard 建议

在 Grafana 中导入或自定义以下面板：

| 面板 | 查询 |
| --- | --- |
| 服务可用率 | `avg by (namespace, service) (probe_success)` |
| 响应时间热力图 | `probe_duration_seconds` 散点 |
| 24h 告警趋势 | `ALERTS{alertstate="firing", namespace=~"drinkzen|party-helper"}` |

## 🔄 升级路径

| 当前 | Phase 2 | Phase 3 |
| --- | --- | --- |
| Blackbox 主动探测 | + 应用 `/metrics` + RED 指标 | + kagent AI 助手查询 |
| 知道 pod 是否活着 | 知道 QPS/延迟/错误率 | 知道"为什么慢"的根因 |
| 30 分钟部署 | 需改 app + 重新部署 | 已有 kagent 基础即可接入 |

---

## ⚠️ 已知限制

1. **party-helper API 端口**：Deployment 监听 `8021`，但 Service spec 写的 `8022`。Probe 已按 `8021` 配置（与 liveness 一致）。
2. **drinkzen-admin / party-helper-admin**：未配置 healthz，只能探测 `/` 根路径，404 会被算作成功（accept 200/301/302/3xx）。
3. **drinkzen API 容器内 `wget`/`curl` 失败**：探测不到 `/healthz` 但 Pod 探针成功。可能与容器镜像的 network namespace 配置有关——但这不影响 Blackbox 探测（从 monitoring 命名空间发起的集群内访问）。
4. **本地 docker-desktop 单节点**：kubeAPIServer/kubelet 等组件的证书是自签，会持续报错——已在 `values.yaml` 中禁用对应抓取。

## 📚 参考

- [Prometheus Operator Probe CRD](https://prometheus-operator.io/docs/api-reference/#probe)
- [Blackbox Exporter 配置](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md)
- [kube-prometheus-stack Blackbox](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#blackboxexporter)