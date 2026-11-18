# 项目协作说明

本仓库是 kagent 的部署和运维配置仓库，不是上游源码。

- 当前基线：kagent/CRD/CLI 1.0.0-alpha13，Substrate/PodCertificate 0.5.0-alpha2。
- 目标 context：kind-kagent（专用 kind 集群，集群名 kagent）。
- docker-desktop 是独立的 Docker Desktop Kubernetes；本地操作必须显式指定 context，不修改 current-context。
- 安装/恢复入口：scripts/local-up.sh；权限验收：scripts/verify-readonly.sh。
- Helm 配置：kagent-config/helm/values.yaml；安装器配置：kagent-install-config.yaml。
- v1 Agent/Harness：kagent-config/crds/，api.kagent.dev/v1alpha3。
- default-model-config 由 Helm 生成，避免另建同名清单。
- 当前 sre-readonly Agent 仅允许诊断 kagent 命名空间；不接入写操作或跨集群权限。
- 旧 API 文件位于 kagent-config/legacy/v0.10.1/，禁止应用到 v1 基线。
- Secret 内容不得打印、写入报告或提交。不要使用强制覆盖或删除 Secret 的方式解决 Helm 字段冲突。
- 更新使用完整的基线 values 与 --reset-values --server-side=false，避免复用安装器历史中的占位 Key。真实凭证仅放在独立的 kagent-deepseek-runtime Secret，不传入 Helm。变更后验证最终 RBAC，不仅检查新 Role 是否创建。
- 历史安装总结和监控验收报告不是当前集群状态，以带日期的实测记录为准。
- 当前控制面只通过回环地址 port-forward 使用；DeepSeek 是公网模型服务，不能宣称数据不出集群。
