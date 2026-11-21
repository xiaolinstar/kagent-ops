# 项目协作说明

本仓库是 kagent 的部署和运维配置仓库，不是上游源码。概念与依赖总览见 `docs/overview.md`。

- 当前基线：kagent/CRD/CLI 1.0.0-alpha13，Substrate/PodCertificate 0.5.0-alpha2。
- 本地目标 context：kind-kagent；云端为独立 k3s context，见 `docs/cloud-deployment.md` 与 `deploy/cloud/`（仅环境附录）。
- docker-desktop 是独立集群；本地操作必须显式指定 context，不修改 current-context。
- 安装入口：`scripts/local-up.sh` / `scripts/cloud-install.sh`；权限验收：`scripts/verify-readonly.sh`。
- **共用配置：** `kagent-config/helm/values.yaml`、`kagent-install-config.yaml`、`kagent-config/crds/agents.yaml`、`kagent-config/crds/harness.yaml`（多架构 Harness）。
- default-model-config 由 Helm 生成，避免另建同名清单。
- sre-readonly 仅诊断 `kagent` 命名空间；不接入写操作或跨集群权限。
- 旧 API 清单：`kagent-config/legacy/`（禁止 apply）；旧文档已移除，需要时查 git 历史；监控目录本阶段未部署。
- Secret 不得打印、写入报告或提交；不要用强制覆盖/删除 Secret 解决 Helm 冲突。
- 更新使用完整基线 values 与 `--reset-values`（Helm 4 加 `--server-side=false`）；真实凭证仅在 `kagent-deepseek-runtime`。
- 以带日期实测与 overview 为准；控制面仅回环 port-forward；DeepSeek 出公网。
- 镜像分 containerd 与 atelet 两路；云端须处理 registries、共用 Harness 源与 atelet `GODEBUG`。
