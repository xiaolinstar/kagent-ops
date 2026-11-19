# 火山引擎 ECS 上的 kagent 首期部署

本阶段在独立运维 ECS 上部署 kagent、Substrate、PostgreSQL 和一个只读诊断 Agent。首期基线：kagent 1.0.0-alpha13、Substrate / PodCertificate 0.5.0-alpha2、Kubernetes **1.37.x**（现场为 **k3s**）。本地已验证环境是单节点 ARM64 kind；云端为 **amd64 + k3s**，首次安装仍需现场验收，不能用本地恢复结果代替。

试点规格假设：约 8 vCPU / 16GB 内存 / **40GB 系统盘**（装完 k3s 后约有 32GB 可用即可开装）。不强制先加数据盘；装机过程记录 `df -h`，可用空间偏低或出现 `DiskPressure` 再扩容。对象存储留给后续备份，不替代本机镜像与 `local-path` PVC。

## 迁移差异（为何云端会卡）

| 维度 | 本地 kind（已验收） | 云端 k3s（本试点） |
| --- | --- | --- |
| 架构 | ARM64 | amd64 |
| 发行版 | kind | k3s 1.37.x |
| 沙箱 | 节点已具备 gVisor 路径 | **须自装 runsc + RuntimeClass `gvisor`** |
| 镜像拉取 | 节点 mirror + 南大源；Harness 钉 ARM64 digest | Docker Hub / GHCR / `cr.agentgateway.dev` 易超时 |
| 两套拉镜像路径 | containerd **与** atelet Image cache | **containerd 配 registries 不够**；atelet 按 Harness 的 image ref 自己拉 ADK |
| HTTP/2 | atelet / Harness 需 `GODEBUG=http2client=0` | **同样必须**（见下） |
| Helm | 可用 OCI | 建议用仓库内 `kagent-*.tgz`；`--server-side` 仅 Helm 4 |
| Secret | 独立 `kagent-deepseek-runtime` | CLI `install` 若带 placeholder 会与手建 Secret 冲突 → 用 `helm upgrade --install` + `apiKey: null` |

现场曾卡在：`ActorTemplatePending` / 曾出现 `GoldenActorCrashed`；atelet 日志典型为对  
`golang-adk:...@sha256:ae01c3a6...` 的 `Image cache miss` 后长时间无 hit。controller 侧可能反复  
`another operation is in progress for this ActorTemplate`（旧 revision 占用中）。**勿短时间反复改 Harness**。

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
- 默认 StorageClass（k3s：`local-path`）
- RuntimeClass **`gvisor`**（handler `runsc`）已冒烟
- DeepSeek API 可出网

磁盘采样：① 本步后；② 控制面 Pod Ready；③ Agent Ready / smoke 后。

工具：kubectl、Helm 3/4、Ruby、`kagent-linux-amd64`（摘要见 [cli.sha256](../deploy/cloud/cli.sha256)）。

## 1. 镜像源（装 kagent 之前做完）

### 1.1 k3s containerd（Pod 镜像）

将 [registries.yaml.example](../deploy/cloud/registries.yaml.example) 安装为 `/etc/rancher/k3s/registries.yaml` 后重启 k3s：

```bash
sudo cp deploy/cloud/registries.yaml.example /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
kubectl get nodes
```

覆盖：`docker.io`（postgres / rustfs / pause 等）、`registry.k8s.io`、`ghcr.io`。  
`cr.agentgateway.dev`（atenet）往往仍须直连或预热，无稳定国内源时用 `ctr` 预拉。

预热示例（containerd，解决 Pod `ContainerCreating`）：

```bash
sudo ctr -n k8s.io images pull docker.m.daocloud.io/library/postgres:18-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15
sudo ctr -n k8s.io images tag \
  docker.m.daocloud.io/library/postgres:18-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15 \
  postgres:18-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15
```

### 1.2 atelet（Agent golden snapshot 用的 ADK）

与 containerd **不是同一缓存**。必须：

1. Harness 使用可达 registry（仓库默认 [deploy/cloud/harness.yaml](../deploy/cloud/harness.yaml) 已用 `ghcr.nju.edu.cn` + **多架构** digest `ae01c3a6...`）。
2. DaemonSet atelet 设置 `GODEBUG=http2client=0`：

```bash
kubectl -n ate-system set env daemonset/atelet GODEBUG=http2client=0
kubectl -n ate-system rollout status daemonset/atelet --timeout=180s
```

看日志请用正确 label：`kubectl -n ate-system logs -l app=atelet`（不是 `app.kubernetes.io/name=atelet`）。

### 1.3 Helm Chart

优先：`helm upgrade --install kagent ./kagent-1.0.0-alpha13.tgz ...`  
避免 `oci://ghcr.io/...` 在国内超时。Helm 3 不要加 `--server-side`。

## 2. 命名空间与 Secret

```bash
export KAGENT_CONTEXT=default   # 或专用名；不要用 kind-kagent
export KAGENT_CLI=/absolute/path/to/kagent-linux-amd64

kubectl --context "$KAGENT_CONTEXT" create namespace kagent --dry-run=client -o yaml \
  | kubectl --context "$KAGENT_CONTEXT" apply -f -
kubectl --context "$KAGENT_CONTEXT" -n kagent create secret generic kagent-deepseek-runtime \
  --from-literal=DEEPSEEK_API_KEY='你的Key'
```

## 3. 安装顺序（手装摘要）

1. gVisor RuntimeClass 冒烟通过。  
2. registries +（安装器跑起来后）atelet `GODEBUG`。  
3. `OPENAI_API_KEY=bootstrap-placeholder "$KAGENT_CLI" --config deploy/cloud/install-config.yaml install`  
   - `valuesFiles` 相对 `deploy/cloud/` 解析（已用 `../../kagent-config/helm/values.yaml`）。  
   - 若报 Secret 与 Helm 所有权冲突：**不要删 Secret**；改用  
     `helm upgrade --install kagent ./kagent-1.0.0-alpha13.tgz -n kagent --reset-values -f kagent-config/helm/values.yaml --wait`  
4. `kubectl apply -f deploy/cloud/harness.yaml -f kagent-config/crds/agents.yaml`  
5. 等 Agent Ready（首次 golden 依赖 atelet 拉齐 ADK，可能很长）。日志出现 `Image cache hit` 对 golang-adk 后再期望 Ready。

也可使用 `./scripts/cloud-install.sh`（需 Linux + 已校验 CLI）；Helm 4 的 `--server-side=false` 在 Helm 3 上请手装时省略。

## 4. 访问（insecure，仅回环）

```bash
kubectl -n kagent port-forward svc/kagent-ui 8080:8080 --address 127.0.0.1
kubectl -n kagent port-forward svc/kagent-controller 18083:8083 --address 127.0.0.1
```

本机经 SSH：`ssh -L 8080:127.0.0.1:8080 -L 18083:127.0.0.1:18083 user@ECS`。  
浏览器 `http://127.0.0.1:8080`，选 `sre-readonly`。**不要公网暴露。**

## 5. 命名空间一览

| 命名空间 | 作用 |
| --- | --- |
| `kagent` | controller / UI / tools / PG / Agent / Harness / WorkerPool |
| `ate-system` | Substrate API、atelet、router/egress、rustfs |
| `podcertificate-controller-system` | 证书 |
| `kube-system` | k3s 系统组件 |

## 6. 验收与未完成项

- `verify-readonly`、port-forward 后 `smoke-agent`。  
- **当前现场未完成项：** Agent 仍可能 `ActorTemplatePending`（atelet 拉 ADK / 旧 template 占用）。续作时：确认 Harness 为南大多架构 digest、atelet `GODEBUG`、只观察 `app=atelet` 的 Image cache 日志；避免频繁改 Harness；必要时在确认无会话后 `delete agent` 再 apply 一次以甩掉卡死的 revision。

`kagent-config/crds/agents/` 下其它 Agent 本阶段不部署。
