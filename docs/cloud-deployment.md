# 云端环境附录（火山 ECS + k3s）

业务配置与本地**共用**（见 [overview.md](overview.md)）：`kagent-install-config.yaml`、`kagent-config/helm/values.yaml`、`kagent-config/crds/agents.yaml`、`kagent-config/crds/harness.yaml`。本文只补 **k3s / amd64 / 国内网络** 差异。

首期基线：kagent 1.0.0-alpha13，Substrate / PodCertificate 0.5.0-alpha2，Kubernetes **1.37.x**。本地 kind 验收不能代替云端首装验收。试点磁盘约 40GB 可先试，装机记 `df -h`。

## 0. 现场核对

```bash
uname -m; nproc; free -h; df -h
kubectl version; kubectl get nodes -o wide
kubectl get storageclass; kubectl get runtimeclass
```

需要：`x86_64` 或 `aarch64`、server **1.37.x**、默认 StorageClass、**RuntimeClass `gvisor`**、DeepSeek 出网。工具：kubectl、Helm 3/4、Ruby、已校验的 Linux CLI（[cli.sha256](../deploy/cloud/cli.sha256)）。

## 1. 镜像加速（环境层）

```bash
sudo cp deploy/cloud/registries.yaml.example /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
```

这只覆盖 **containerd（路径 A）**。Harness 已指向南大源；装起 Substrate 后务必：

```bash
kubectl -n ate-system set env daemonset/atelet GODEBUG=http2client=0
kubectl -n ate-system rollout status daemonset/atelet --timeout=180s
# 日志 label：app=atelet
```

`cr.agentgateway.dev` 等无镜像时用 `ctr` 预热。Helm 优先 `./kagent-1.0.0-alpha13.tgz`。

## 2. Secret

```bash
export KAGENT_CONTEXT=你的k3s-context   # 勿用 kind-kagent / docker-desktop
export KAGENT_CLI=/绝对路径/kagent-linux-amd64

kubectl --context "$KAGENT_CONTEXT" create namespace kagent --dry-run=client -o yaml \
  | kubectl --context "$KAGENT_CONTEXT" apply -f -
kubectl --context "$KAGENT_CONTEXT" -n kagent create secret generic kagent-deepseek-runtime \
  --from-literal=DEEPSEEK_API_KEY='你的Key'
```

## 3. 安装

推荐脚本（Linux）：

```bash
./scripts/cloud-install.sh "$KAGENT_CONTEXT"
```

手装要点：共用 `kagent-install-config.yaml`；若 CLI `install` 与手建 Secret 冲突，**勿删 Secret**，改用：

```bash
helm upgrade --install kagent ./kagent-1.0.0-alpha13.tgz -n kagent \
  --reset-values -f kagent-config/helm/values.yaml --wait --timeout 15m
# Helm 4 再加：--server-side=false

kubectl apply -f kagent-config/crds/harness.yaml -f kagent-config/crds/agents.yaml
kubectl -n ate-system set env daemonset/atelet GODEBUG=http2client=0
kubectl -n kagent wait --for=condition=Ready agent/sre-readonly --timeout=600s
```

盯 atelet：`Image cache miss/hit` 针对 golang-adk。勿短时间反复改 Harness。

## 4. 访问

```bash
kubectl -n kagent port-forward svc/kagent-ui 8080:8080 --address 127.0.0.1
kubectl -n kagent port-forward svc/kagent-controller 18083:8083 --address 127.0.0.1
```

SSH 隧道后本机打开；**勿公网暴露**（insecure）。

## 5. 命名空间

| NS | 作用 |
| --- | --- |
| `kagent` | 控制面、Agent、PG |
| `ate-system` | Substrate / atelet / rustfs |
| `podcertificate-controller-system` | 证书 |
| `kube-system` | k3s 系统组件 |
