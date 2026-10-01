# 贡献计划 - kagent 社区贡献

本文档记录在使用 [kagent](https://kagent.dev) 过程中发现的问题、改进想法和潜在贡献点，未来可作为社区 PR 或 Issue 的参考。

## 🐛 Bug / 已知问题

### 1. Web UI 引导状态未持久化到服务端

**现象**：通过 YAML (Helm values) 配置好 Agent 和 ModelConfig 后，重启 Pod 再打开 UI 仍会显示首次引导页面。

**根因**：kagent UI 将"引导完成"状态存储在浏览器 `localStorage` 中，不检查后端是否已有 Agent/ModelConfig。

**影响**：
- 换浏览器或清缓存后需重新走引导流程
- 通过 Helm 配置的用户每次都要跳过/重新走引导

**建议修复方向**：
- UI 启动时调用后端 API 检查是否已有 Agent 和 ModelConfig
- 若已存在，自动跳过引导页

**相关文件**：待确认（UI 源码中的 onboarding 逻辑）

---

### 2. Grafana MCP RemoteMCPServer 连接报 Forbidden ✅ 已修复

**现象**：kagent-controller 日志持续报错：

```
failed to upsert tool server for remote mcp server
remoteMCPServer: kagent/kagent-grafana-mcp
error: calling "initialize": sending "initialize": Forbidden
```

**根因**：`mcp-grafana` 镜像默认 `-allowed-hosts` 仅允许 `localhost`，RemoteMCPServer 通过 `kagent-grafana-mcp.kagent:8000` 连接时被主机名校验拒绝。

**修复方式**：v0.10.1 chart 不支持 `allowedHosts` 字段（main 分支已添加），通过 `args` 直接传递 `-allowed-hosts` 参数：

```yaml
grafana-mcp:
  args:
    - "-allowed-hosts"
    - "kagent-grafana-mcp.kagent:8000,kagent-grafana-mcp.kagent,localhost:8000"
```

**建议贡献**：向 kagent 上游提交 PR，在 v0.10.x 的 grafana-mcp chart 中支持 `allowedHosts` 配置项。

---

### 3. k3s kubernetes Endpoint 残留异常 IP

**现象**：`kubectl get endpoints kubernetes -n default` 显示 3 个 IP：

```
172.20.10.4:6443    ← 当前节点 IP ✅
192.168.1.62:6443   ← 旧网络接口残留 ❌
198.18.0.1:6443     ← 旧网络接口残留 ❌
```

**根因**：k3s 未配置 `advertise-address`，kube-apiserver 自动检测所有网络接口并注册。当网络接口变化（如 WSL2 切换 VPN、重启等），旧 IP 不会被自动清除，残留在 `kubernetes` Endpoint 和 EndpointSlice 中。

**影响**：
- Prometheus 监控可能报警 unhealthy endpoint
- 不影响集群正常功能（kubectl、Pod 访问 API Server 正常）

**修复方式**：在 k3s 配置中固定 advertise-address：

```yaml
# /etc/rancher/k3s/config.yaml
advertise-address: 172.20.10.4
```

然后重启 k3s：`sudo systemctl restart k3s`

**注意**：不能直接 `kubectl edit endpoints kubernetes`，这是由 apiserver 自动管理的，手动修改会被覆盖。

**状态**：暂不修复，记录备用

---

## ✨ Feature 建议

### 1. 后端 Setup 状态检查 API

**描述**：新增 API 端点 `GET /api/setup/status`，返回当前集群是否已完成初始化配置（Agent、ModelConfig 是否存在）。

**好处**：
- UI 可根据后端状态决定是否显示引导页
- 支持 Helm 预配置的用户自动跳过引导
- 解决浏览器 localStorage 丢失导致的重复引导问题

**参考实现思路**：

```go
// 伪代码
func (s *Server) GetSetupStatus(w http.ResponseWriter, r *http.Request) {
    agents, _ := s.kubeClient.ListAgents()
    modelConfigs, _ := s.kubeClient.ListModelConfigs()
    
    status := SetupStatus{
        HasAgents:      len(agents) > 0,
        HasModelConfig: len(modelConfigs) > 0,
        IsComplete:     len(agents) > 0 && len(modelConfigs) > 0,
    }
    json.NewEncoder(w).Encode(status)
}
```

---

### 2. NodePort 在 WSL2 环境下的文档说明

**描述**：kagent 官方文档未说明 WSL2 环境下 NodePort 无法从 Windows 直接访问。

**现状**：
- WSL2 的虚拟网络隔离导致 `localhost:NodePort` 不通
- 必须使用 `kubectl port-forward` 访问

**建议**：
- 在官方文档的安装指南中添加 WSL2 注意事项
- 或在 Helm values 中默认使用 ClusterIP + 推荐 port-forward

---

### 3. Helm values 中 Agent 配置结构文档

**描述**：kagent Helm Chart 的 Agent 开关配置为**根级别 key**（非嵌套在 `agents:` 下），但文档示例可能有误导。

**正确格式**：

```yaml
# ✅ 正确 — 根级别
k8s-agent:
  enabled: true

# ❌ 错误 — 不是嵌套在 agents 下
agents:
  k8s-agent:
    enabled: true
```

**建议**：在官方 Helm 文档中明确说明配置层级。

---

## 📋 待贡献 PR 清单

| # | 类型 | 描述 | 优先级 | 状态 |
|---|------|------|--------|------|
| 1 | Bug Fix | UI 引导状态改为后端检查 | 高 | 待实现 |
| 2 | Docs | WSL2 环境访问说明 | 中 | 待提 Issue |
| 3 | Docs | Agent 配置结构说明 | 中 | 待提 Issue |
| 4 | Bug Fix | Grafana MCP Forbidden 错误 | 中 | ✅ 已修复（本地） |
| 5 | Docs | monitoring values.yaml 示例 | 低 | 待提 Issue |
| 6 | Config | k3s advertise-address 配置说明 | 低 | 暂不修复 |

---

## 🔗 参考

- [kagent GitHub](https://github.com/kagent-dev/kagent)
- [kagent 官方文档](https://www.kagent.dev/docs)
- [kagent Helm Chart](https://github.com/kagent-dev/kagent/tree/main/helm)
