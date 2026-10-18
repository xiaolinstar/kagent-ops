# Kind 节点镜像加速配置

## 背景

Kind 集群创建时会在节点内自动部署一个 registry mirror（`kind-registry-mirror`），并在 containerd 中写入 `_default` 通配规则，将所有 registry 请求转发到本地代理 `registry-mirror:1273`。

该代理对 ghcr.io 的 OCI 镜像格式支持不稳定，会导致拉取失败（500 / short read / not found）。通过为 docker.io 和 ghcr.io 配置专属的国内镜像源，可以绕过本地代理直连加速。

## 架构

```
/etc/containerd/certs.d/
├── _default/hosts.toml      # kind 自动创建 — 其他 registry 走本地代理
├── docker.io/hosts.toml     # 手动创建 — 国内镜像优先
└── ghcr.io/hosts.toml       # 手动创建 — 国内镜像优先
```

containerd 匹配规则：**具体目录优先于 `_default`**。

## 配置内容

### docker.io

```toml
server = "https://registry-1.docker.io"

[host."https://docker.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
```

### ghcr.io

```toml
server = "https://ghcr.io"

[host."https://ghcr.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://ghcr.nju.edu.cn"]
  capabilities = ["pull", "resolve"]

[host."https://ghcr.io"]
  capabilities = ["pull", "resolve"]
```

## 恢复命令（kind 节点重启后执行）

节点重启后 `_default` 会被 Docker Desktop 重新注入，但 `docker.io/` 和 `ghcr.io/` 目录不会自动创建。执行以下命令恢复：

```bash
# docker.io 加速
docker exec desktop-control-plane mkdir -p /etc/containerd/certs.d/docker.io
docker exec desktop-control-plane sh -c 'cat > /etc/containerd/certs.d/docker.io/hosts.toml << EOF
server = "https://registry-1.docker.io"

[host."https://docker.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF'

# ghcr.io 加速
docker exec desktop-control-plane mkdir -p /etc/containerd/certs.d/ghcr.io
docker exec desktop-control-plane sh -c 'cat > /etc/containerd/certs.d/ghcr.io/hosts.toml << EOF
server = "https://ghcr.io"

[host."https://ghcr.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://ghcr.nju.edu.cn"]
  capabilities = ["pull", "resolve"]

[host."https://ghcr.io"]
  capabilities = ["pull", "resolve"]
EOF'
```

## 验证

```bash
# 确认配置文件存在
docker exec desktop-control-plane find /etc/containerd/certs.d -type f

# 拉取测试（docker.io）
kubectl run test-io --image=docker.io/library/alpine:3.20 --restart=Never --rm -i -- echo OK

# 拉取测试（ghcr.io）— 确认不经过本地代理
docker logs kind-registry-mirror --since 2m | grep ghcr
# 无输出 = 已绕过本地代理
```

## 镜像源可用性

国内镜像源可能随时失效，失效时替换 `hosts.toml` 中的地址即可。2026-10 实测可用：

| 用途 | 地址 | 说明 |
|------|------|------|
| Docker Hub | `docker.1ms.run` | 免费、稳定 |
| Docker Hub | `docker.m.daocloud.io` | DaoCloud 公共源 |
| ghcr.io | `ghcr.1ms.run` | GHCR 专属加速 |
| ghcr.io | `ghcr.nju.edu.cn` | 南京大学开源镜像站 |
