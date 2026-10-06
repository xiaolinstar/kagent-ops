# 业务服务可观测性部署 Runbook

> 适用范围：标准 Kubernetes 集群（>= 1.25，内核 >= 5.8 以支持 eBPF）
> 监控目标：`drinkzen`、`party-helper` 两个命名空间
> 本文档与集群发行版无关；发行版差异见文末「环境注意事项」

## 监控能力总览

| 能力 | 组件 | 业务侧改动 |
| --- | --- | --- |
| 可用性探测（HTTP 探活） | Blackbox Exporter + Probe | 无 |
| RED 指标（QPS/延迟/错误率） | Beyla（eBPF 零插桩） | 无 |
| Pod/节点基础指标 | kube-prometheus-stack 自带 | 无 |
| 告警 | PrometheusRule → Alertmanager | 无 |
| 可视化 | Grafana Dashboard（ConfigMap 自动加载） | 无 |

## 📦 交付物清单

| 文件 | 资源类型 | 说明 |
| --- | --- | --- |
| `monitoring/values.yaml` | Helm Values | kube-prometheus-stack 配置 |
| `monitoring/blackbox-values.yaml` | Helm Values | blackbox-exporter **独立 chart** 配置（含探测模块） |
| `monitoring/beyla-values.yaml` | Helm Values | Beyla eBPF 配置 |
| `monitoring/probes/*.yaml` | Probe CRD ×6 | drinkzen/party-helper 的 API 探测、各自 Admin 存活探测 + 部署完整性探测 |
| `monitoring/prometheus-rules/http-availability.yaml` | PrometheusRule | 探测失败/慢响应/证书告警 |
| `monitoring/dashboards/business-overview.yaml` | ConfigMap | Grafana 业务总览面板（sidecar 自动加载） |

## 前置条件

- `kubectl` 已配置目标集群上下文
- Helm 3.x
- 集群存在默认 StorageClass（Prometheus 持久化用，10Gi）
- 业务 Service 带有标准 label（`app.kubernetes.io/name` 等）——drinkzen/party-helper 现状已满足

## 🚀 部署步骤

### 1. 添加 Helm 仓库

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 2. 部署 kube-prometheus-stack

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --version 51.2.0 \
  --values kagent-config/monitoring/values.yaml
```

> 注意：kube-prometheus-stack 51.x 已移除内置 blackbox 子 chart，blackbox-exporter 必须独立安装（下一步）。

### 3. 部署 blackbox-exporter（独立 release）

```bash
helm upgrade --install blackbox-exporter \
  prometheus-community/prometheus-blackbox-exporter \
  -n monitoring --values kagent-config/monitoring/blackbox-values.yaml
```

探测模块（`http_2xx_healthz` / `http_2xx_root`）由该 chart 自动生成 ConfigMap，无需单独 apply。

### 4. 应用 Probe 与告警规则

```bash
kubectl apply -f kagent-config/monitoring/probes/
kubectl apply -f kagent-config/monitoring/prometheus-rules/
```

### 5. 部署 Beyla（eBPF RED 指标）

```bash
helm upgrade --install beyla grafana/beyla \
  -n monitoring --version 1.16.11 \
  --values kagent-config/monitoring/beyla-values.yaml
```

### 6. 加载 Grafana Dashboard

```bash
kubectl apply -f kagent-config/monitoring/dashboards/
```

Grafana sidecar 会自动加载带 `grafana_dashboard: "1"` 标签的 ConfigMap，约 30 秒内出现在 Business 目录。

## ✅ 验证

```bash
# 1. 全部 Pod Running
kubectl get pods -n monitoring

# 2. Probe 已注册
kubectl get probes -n monitoring

# 3. 探测指标：4 个目标应全部 probe_success = 1
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# 查询：probe_success{namespace=~"drinkzen|party-helper"}

# 4. RED 指标已产生（Beyla）
# 查询：sum by (k8s_deployment_name) (rate(http_server_request_duration_seconds_count{k8s_namespace_name=~"drinkzen|party-helper"}[2m]))

# 5. 告警规则已加载
# 查询：ALERTS 或访问 /alerts 页面

# 6. Grafana Dashboard
kubectl port-forward -n monitoring svc/monitoring-grafana 31080:80
# http://localhost:31080（admin/admin）→ Business 目录 → Business Services Overview
```

## 🔍 常用 PromQL

```promql
# 各服务 24h 可用率
avg_over_time(probe_success{namespace=~"drinkzen|party-helper"}[24h])

# 当前未通过探测
probe_success{namespace=~"drinkzen|party-helper"} == 0

# QPS（Beyla RED，按部署）
sum by (k8s_deployment_name) (
  rate(http_server_request_duration_seconds_count{k8s_namespace_name=~"drinkzen|party-helper"}[2m])
)

# P95 延迟（按部署）
histogram_quantile(0.95,
  sum by (le, k8s_deployment_name) (
    rate(http_server_request_duration_seconds_bucket{k8s_namespace_name=~"drinkzen|party-helper"}[5m])
  )
)

# 5xx 错误率
sum by (k8s_deployment_name) (
  rate(http_server_request_duration_seconds_count{k8s_namespace_name=~"drinkzen|party-helper",http_response_status_code=~"5.."}[5m])
)
```

## 🚨 告警列表

| 告警名 | 触发条件 | 持续时间 | 严重度 |
| --- | --- | --- | --- |
| HttpProbeFailed | `probe_success == 0` | 2 分钟 | warning |
| HttpProbeSlow | P95 探测延迟 > 1s | 5 分钟 | warning |
| TlsCertExpiringSoon | 证书 < 7 天过期 | 1 小时 | warning |

告警当前仅在 Prometheus/Grafana 页面展示，未外发通知（Alertmanager 通知渠道待配置）。

## 🧪 故障演练（验证告警闭环）

```bash
# 制造故障
kubectl scale deploy party-helper-api -n party-helper --replicas=0

# 预期：约 40s 后告警 pending，2m40s 左右 HttpProbeFailed 进入 firing
# 恢复
kubectl scale deploy party-helper-api -n party-helper --replicas=1
# 预期：约 80s 内 probe_success 恢复 1，告警自动 resolved
```

## 🔧 配置要点（踩坑记录）

1. **外部 ServiceMonitor 必须带 `release: monitoring` 标签**：kube-prometheus-stack 安装的 Prometheus 默认只发现带本标签的 ServiceMonitor/Probe。beyla-values.yaml 与 blackbox-values.yaml 中已固化（`additionalLabels` / `labels`）。
2. **`probeSelectorNilUsesHelmValues: false`**：values.yaml 中必须显式设置，否则 Probe CRD 不会被 Prometheus 加载。
3. **Probe 目标使用完整 URL**：`http://service:port/path` 显式指定路径。API 探 `/healthz`，Admin 探 `/`。不能只写 `service:port`（默认探 `/`，API 根路径是 404）。
4. **blackbox chart 的自监控开关是 `serviceMonitor.selfMonitor.enabled`**，不是 `serviceMonitor.enabled`。

## ⚠️ 已知限制与待办

1. **party-helper-api 端口**：已统一为 ClusterIP `8021 → targetPort 8021`（原 8022→8021 已修正）。
2. **Admin SPA 两层探测**：SPA 前端对错误路由返回 200 + index.html（客户端渲染 404 页），属正常业务行为，不可由 HTTP 探测发现。因此两个 Admin 均分两层：
   - 第一层（进程存活）：nginx 精确匹配 `location = /healthz` 返回 JSON（非 SPA 兜底），Probe 用 `http_2xx_healthz`。**drinkzen-admin 与 party-helper-admin 均已上线**。
   - 第二层（部署完整性）：Probe `*-admin-index` 用 `http_2xx_index` 探 `/`，校验响应体含 SPA 挂载点 `<div id="app">`，可发现「进程活着但 index.html 损坏/白屏」。新增前端接入时注意 body 正则要与该项目 index.html 挂载点一致。
   - 局限：hash 命名的 JS chunk 路径每次构建变化且被 SPA 兜底，Blackbox 无法探测其运行时加载失败；这类问题需前端 RUM（后续阶段考虑）。
3. **drinkzen-api 容器内 wget/curl 异常**：容器内网络工具探测不到自身 `/healthz`（K8s 探针与外部 Blackbox 探测均正常）。属镜像环境问题，不影响监控。
4. **Phase 2 待办**：postgres-exporter（业务库指标）由业务项目部署；FastAPI 埋点 `/metrics` 视 Beyla 数据够用程度再定。

## 🌍 环境注意事项（发行版差异）

- **docker-desktop / 本地单节点集群**：kubeAPIServer、kubelet、kubeProxy 证书为自签，抓取会持续报 TLS 错误——values.yaml 中已禁用这些组件的 ServiceMonitor。节点指标由 node-exporter DaemonSet 提供，不受影响。
- **WSL2**：NodePort 无法从 Windows 直接访问，一律使用 `kubectl port-forward`。
- **Beyla 内核要求**：节点内核 >= 5.8 且支持 BTF（主流容器运行时默认满足）。

## 📚 参考

- [Prometheus Operator Probe CRD](https://prometheus-operator.io/docs/api-reference/#probe)
- [Blackbox Exporter 配置](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md)
- [prometheus-blackbox-exporter chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-blackbox-exporter)
- [Grafana Beyla](https://grafana.com/docs/beyla/latest/)
- [总体设计文档](../../docs/observability/observability-design.md)
