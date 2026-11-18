# 火山引擎 ECS 上的 kagent 首期部署

本阶段在独立运维 ECS 上部署 kagent、Substrate、PostgreSQL 和一个只读诊断 Agent。首期基线：kagent 1.0.0-alpha13、Substrate / PodCertificate 0.5.0-alpha2、Kubernetes **1.37.x**（现场为 **k3s**）。本地已验证环境是单节点 ARM64 kind；云端为 **amd64 + k3s**，首次安装仍需现场验收，不能用本地恢复结果代替。

试点规格假设：约 8 vCPU / 16GB 内存 / **40GB 系统盘**（装完 k3s 后约有 32GB 可用即可开装）。不强制先加数据盘；装机过程记录 `df -h`，可用空间偏低或出现 `DiskPressure` 再扩容。对象存储留给后续备份，不替代本机镜像与 `local-path` PVC。

## 0. 现场一次性核对（在 ECS 上）

```bash
uname -m          # 期望 x86_64
nproc; free -h; df -h; lsblk
kubectl version
kubectl get nodes -o wide
kubectl get storageclass
kubectl get runtimeclass
```

通过标准：

- 架构 `x86_64`；server 版本 **1.37.x**
- 存在默认 StorageClass（k3s 通常为 `local-path`）
- 存在可用的 `gvisor` RuntimeClass（或确认安装器/文档要求的 sandbox 已就绪）
- DeepSeek API 可出网；GHCR 能直连，或准备改用 `ghcr.nju.edu.cn`

磁盘采样点（每次记下 `df -h` 可用量）：① 本步完成后；② 镜像拉齐 / Pod Ready；③ `smoke-agent` 之后。

工具：kubectl、Helm 4、Ruby。从 [alpha13 Release](https://github.com/kagent-dev/kagent/releases/tag/v1.0.0-alpha13) 下载 **`kagent-linux-amd64`**，用 [cli.sha256](../deploy/cloud/cli.sha256) 校验并 `chmod +x`。

## 1. 把仓库与 kubeconfig 准备好

在 ECS 上克隆/同步本仓库（确保含 `scripts/`、`deploy/cloud/`、`kagent-config/`）。为 k3s 建专用 context 名称（示例 `kagent-ecs`），**不要**用 `kind-kagent` / `docker-desktop`。

```bash
export KAGENT_CONTEXT=kagent-ecs   # 换成你的 context 名
export KAGENT_CLI=/absolute/path/to/kagent-linux-amd64
```

## 2. 预置命名空间与 DeepSeek Secret

```bash
kubectl --context "$KAGENT_CONTEXT" create namespace kagent --dry-run=client -o yaml | kubectl --context "$KAGENT_CONTEXT" apply -f -
```

按 `llm-secret-example.yaml` 在目标集群创建 `kagent-deepseek-runtime`（键名 `DEEPSEEK_API_KEY`）。真实 Key 不进 Helm、不提交 Git。可用：

```bash
kubectl --context "$KAGENT_CONTEXT" -n kagent create secret generic kagent-deepseek-runtime \
  --from-literal=DEEPSEEK_API_KEY='你的Key'
```

## 3. 镜像策略（按需）

- 默认：`deploy/cloud/harness.yaml` 与 Helm values 使用官方 `ghcr.io` 多架构摘要（适合 amd64）。
- 直连失败：把相关镜像主机名改为 `ghcr.nju.edu.cn`，**保留 amd64/多架构正确 digest**；禁止套用本地 ARM64 平台摘要（`kagent-config/crds/harness.yaml` 里那条）。
- 走南大源若遇 HTTP/2 问题：Harness 增加 `GODEBUG=http2client=0`（与本地经验一致）。
- Helm Chart 的 `oci://ghcr.io/...` 与容器镜像不是同一条路径；Chart 拉不下时改用仓库内已有 `kagent-*-1.0.0-alpha13.tgz` 或临时代理（需改安装命令时再动脚本）。

## 4. 安装

在仓库根目录：

```bash
./scripts/cloud-install.sh "$KAGENT_CONTEXT"
```

脚本会：校验 Linux CLI 摘要与 K8s 1.37.x、确认 Secret 存在、调用安装器初始化依赖、按基线 values 升级 Helm、跑只读权限检查、只 apply 云端 Harness + `sre-readonly` Agent，并等待 Agent Ready。

## 5. 验收

1. 查默认 StorageClass、PG/RustFS PVC Bound、`kagent` / `ate-system` Pod Ready；记录 `df -h`。
2. `KAGENT_CONTEXT="$KAGENT_CONTEXT" ./scripts/verify-readonly.sh`
3. 在 ECS 上：

```bash
kubectl --context "$KAGENT_CONTEXT" -n kagent port-forward svc/kagent-controller 18083:8083 --address 127.0.0.1
```

另开终端：`KAGENT_CLI="$KAGENT_CLI" ./scripts/smoke-agent.sh`（核验模型回复与受限 MCP 调用）。UI 同理只做回环转发；**不要**把 8080/8083 对公网暴露（当前 `auth.mode: insecure`）。

4. 正常重启节点后再查会话、PVC、Agent Ready，并记录 CPU/内存/磁盘峰值。

`kagent-config/crds/agents/` 下其它 Agent 本阶段不部署，须单独验收后再纳入。
