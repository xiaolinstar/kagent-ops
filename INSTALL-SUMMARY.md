# kagent v1.0.0-alpha13 安装总结

## 安装概览

**安装时间：** 2026-10-19  
**版本：** kagent v1.0.0-alpha13 + Agent Substrate v0.6.0-alpha3  
**Kubernetes：** kind v1.37.0 (kind-kagent cluster)  
**状态：** ✅ 全部组件运行正常

## 架构组件

### kagent 核心 (namespace: kagent)
- **kagent-controller** — 控制面，管理 CRD 资源
- **kagent-default** — Agent 引擎（运行时）
- **kagent-ui** — Web 界面（端口 8080）
- **kagent-postgresql** — 数据库（主从 2 副本）
- **kagent-tools** — 内置工具服务
- **kagent-grafana-mcp** — Grafana MCP 集成
- **kagent-kmcp-controller-manager** — MCP Server 管理器

### Agent Substrate (namespace: ate-system)
- **ate-api-server** — Substrate API（2 副本）
- **ate-controller** — Substrate 控制器
- **atelet** — 节点代理（每个节点一个）
- **atenet-router/egress** — 网络策略组件
- **k8s-credential-provider** — K8s 凭证提供者
- **rustfs** — 对象存储

## 关键要点

### 1. kagent install CLI 是完整安装器
```bash
# 正确方式：使用 kagent CLI 一键安装
./kagent-darwin-arm64 install --namespace kagent

# 不要单独用 Helm chart 安装，会缺少 Agent Substrate
```

### 2. 网络问题处理
- `raw.githubusercontent.com` 在国内经常无法访问
- GitHub Releases 下载速度慢（~13KB/s）
- **解决方案：** 用浏览器下载文件到本地

### 3. PostgreSQL 冲突
- `kagent install` 会自动部署 PostgreSQL
- 如果之前手动部署过，需要先删除：
  ```bash
  kubectl delete -f postgresql-deploy.yaml --context kind-kagent
  ```

### 4. LLM Provider 配置
- 安装时需要设置 `OPENAI_API_KEY` 环境变量（可以是占位符）
- 安装后通过 Helm upgrade 配置实际 Provider
- Secret 需要 Helm 标签才能被管理：
  ```bash
  kubectl label secret kagent-deepseek app.kubernetes.io/managed-by=Helm
  kubectl annotate secret kagent-deepseek \
    meta.helm.sh/release-name=kagent \
    meta.helm.sh/release-namespace=kagent
  ```

### 5. Kubernetes Context 管理
- 默认 context: `docker-desktop`（日常使用）
- kagent context: `kind-kagent`（显式指定）
- 切换命令：
  ```bash
  kubectl config use-context kind-kagent  # 切换
  kubectl get pods --context kind-kagent  # 单次指定
  ```

## 当前配置

### DeepSeek Provider
- **Model:** deepseek-flash
- **Base URL:** https://api.deepseek.com/v1
- **Secret:** kagent-deepseek (namespace: kagent)
- **配置文件:** 
  - `deepseek-secret.yaml` — API Key
  - `deepseek-values.yaml` — Provider 配置

### 访问方式
```bash
# UI 访问
kubectl port-forward -n kagent svc/kagent-ui 8080:8080 --context kind-kagent
open http://localhost:8080

# Controller API
kubectl port-forward -n kagent svc/kagent-controller 8083:8083 --context kind-kagent
```

## 文件清单

```
/Users/xlxing/AgentProjects/kagent-ops/
├── kagent-darwin-arm64                    # kagent CLI (94MB)
├── kagent-1.0.0-alpha13.tgz              # kagent Helm chart
├── kagent-crds-1.0.0-alpha13.tgz         # CRDs Helm chart
├── kagent-install-config.yaml            # CLI 安装配置
├── kagent-install-values.yaml            # Helm values (最小配置)
├── deepseek-secret.yaml                  # DeepSeek API Key Secret
├── deepseek-values.yaml                  # DeepSeek Provider 配置
└── INSTALL-SUMMARY.md                    # 本文档
```

## 常用命令

### 查看状态
```bash
# kagent 组件
kubectl get pods -n kagent --context kind-kagent

# Agent Substrate
kubectl get pods -n ate-system --context kind-kagent

# CRD 资源
kubectl get agents,agenttemplates,harnesses,modelconfigs -n kagent --context kind-kagent
```

### 日志查看
```bash
# Controller 日志
kubectl logs -n kagent deployment/kagent-controller --context kind-kagent -f

# Engine 日志
kubectl logs -n kagent deployment/kagent-default --context kind-kagent -f

# Substrate API
kubectl logs -n ate-system deployment/ate-api-server --context kind-kagent -f
```

### 升级配置
```bash
# 更新 Provider 配置
helm upgrade kagent ./kagent-1.0.0-alpha13.tgz \
  --kube-context kind-kagent \
  --namespace kagent \
  --values deepseek-values.yaml \
  --reuse-values
```

## 故障排查

### Controller CrashLoopBackOff
**原因：** 缺少 PostgreSQL 或 Substrate API  
**解决：**
```bash
# 检查 PostgreSQL
kubectl get pods -n kagent | grep postgresql

# 检查 Substrate
kubectl get pods -n ate-system
```

### Secret 冲突
**错误：** `conflict with "kubectl-client-side-apply"`  
**解决：** 删除 Secret 让 Helm 重建：
```bash
kubectl delete secret kagent-deepseek -n kagent --context kind-kagent
helm upgrade kagent ... --reuse-values
kubectl apply -f deepseek-secret.yaml --context kind-kagent
```

### 镜像拉取超时
**解决：** 使用代理或手动下载镜像：
```bash
export https_proxy=http://127.0.0.1:端口
# 或手动 docker load
```

## 下一步

1. **创建 Agent CRD** (v1alpha3 格式)
   ```bash
   kubectl apply -f agents.yaml --context kind-kagent
   ```

2. **测试 Agent 对话**
   - 访问 UI: http://localhost:8080
   - 创建对话，选择 Agent
   - 验证 DeepSeek API 调用

3. **配置 MCP Server**
   - 添加自定义 MCP 工具
   - 集成外部服务

4. **监控与日志**
   - 配置 Prometheus 监控
   - 设置日志收集

## 参考文档

- [kagent 官方文档](https://www.kagent.dev/docs/kagent)
- [Agent Substrate](https://github.com/kagent-dev/substrate)
- [Helm Values 配置](https://www.kagent.dev/docs/kagent/resources/helm)

---

**备注：** 
- kind 集群可随时删除重建：`kind delete cluster --name kagent`
- 配置文件已保存在项目目录，可重复使用
- DeepSeek API Key 已配置，可随时测试
