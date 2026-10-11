# 可观测性 Phase 1 验收报告

> 验收时间：2026-10-11（本地集群，monitoring 命名空间）
> 验收依据：`docs/observability/observability-design.md` §2.2 交付物与验收标准

## 一、验收结果总览

| # | 验收项 | 标准 | 结果 | 说明 |
|---|--------|------|------|------|
| 1 | 组件运行 | monitoring 全部 Pod Running | ✅ 通过 | 7 个 Pod 全部 Running，无重启 |
| 2 | Probe 注册 | 6 个 Probe CRD 就绪 | ✅ 通过 | 4 服务入口 × 两层探测全部注册 |
| 3 | 可用性指标 | probe_success 全部 = 1 | ✅ 通过 | 6/6 目标全部通过（含 deploy-integrity 层） |
| 4 | RED 指标 | Beyla 有 QPS/延迟/错误率数据 | ✅ 通过 | 6 个部署均有实时流量数据 |
| 5 | 告警触发 | scale to 0 → 告警 firing | ✅ 通过 | HttpProbeFailed 正常 firing，详见演练记录 |
| 6 | 告警恢复 | 恢复后告警自动 resolved | ✅ 通过 | 46s 探测恢复，77s 告警解除（优于 80s 预期） |
| 7 | 告警送达 | 通知渠道可触达 | ❌ **不达标** | Alertmanager 未部署（values 中 enabled: false），待启用 |
| 8 | 可视化 | Dashboard 开箱可用 | ✅ 通过 | Business Services Overview 已被 sidecar 自动加载 |
| 9 | Pod 健康告警 | 规则加载且评估健康 | ✅ 通过 | PodRestartBurst / PodOOMKilled health: ok |

**结论：9 项中 8 项通过，唯一不达标项为告警外发（Alertmanager 未启用），Phase 1 核心能力可用。**

## 二、故障演练记录

| 阶段 | 时间 | 现象 |
|------|------|------|
| 注入故障 | T+0 | `kubectl scale deploy party-helper-api -n party-helper --replicas=0` |
| 告警触发 | ~T+2m40s | HttpProbeFailed 进入 **firing**（探测间隔 30s + for: 2m，符合设计） |
| 恢复服务 | T+0' | `--replicas=1` |
| 探测恢复 | T+46s | probe_success 回到 1 |
| 告警解除 | T+77s | ALERTS 中 HttpProbeFailed 消失（自动 resolved，优于 RUNBOOK 预期的 80s） |

同时验证了 Dashboard 两层探测展示：基础层（healthz）与 deploy-integrity 层序列独立、标签正确。

## 三、验收新发现（3 个问题）

| # | 问题 | 影响 | 建议 |
|---|------|------|------|
| 1 | **探测覆盖缺口**：Beyla 发现 `party-helper-realtime`、`party-helper-web` 两个部署有真实流量，但 Blackbox 未探测它们 | 这两个服务挂了不会触发 HttpProbeFailed | 补 2 个 Probe（需确认服务入口端口与路径） |
| 2 | **node-exporter 禁用但文档声称可用**：values 中 `nodeExporter.enabled: false`，而 RUNBOOK 写"节点指标由 node-exporter 提供，不受影响" | 节点级 CPU/内存/磁盘指标缺失，文档与配置矛盾 | 本地单节点环境可保持禁用，但需修正 RUNBOOK 表述；生产环境需启用 |
| 3 | **环境描述漂移**：节点为 `desktop-control-plane`（docker-desktop），文档多处写 K3s/WSL2 | 新人按文档排查环境问题时被误导 | 随文档同步任务一并修正 |

> **处理记录（2026-10-11）**：问题 1 已闭环——新增 `ObservabilityCoverageGap` 治理告警（Beyla 自动发现 vs 探测清单对比），并补充 party-helper-realtime / party-helper-web 两个 Probe，实测告警自动点名 → 补探测 → 告警消除完整闭环；问题 2/3 已随文档去发行版化清理修正（删除 K3s/WSL2/docker-desktop 绑定描述，node-exporter 状态如实说明）。

## 四、已实现的可观测性能力（现状盘点）

| 层级 | 能力 | 实现 | 状态 |
|------|------|------|------|
| L0 可用性 | HTTP 黑盒探测（进程存活 + 部署完整性两层） | Blackbox Exporter + 6 Probe | ✅ |
| L1 RED 指标 | QPS / P95-P99 延迟 / 5xx 错误率（零插桩） | Beyla eBPF DaemonSet | ✅ |
| L1 Pod 健康 | 重启风暴 / OOMKilled 告警 | kube-state-metrics + pod-health 规则 | ✅ |
| L1 HTTP 告警 | 探测失败 / 慢响应 / TLS 证书 | http-availability 规则 | ✅ |
| L2 可视化 | 业务总览 Dashboard（git 管理，sidecar 自动加载） | Grafana ConfigMap | ✅ |
| — 告警外发 | Alertmanager → Webhook | 未部署 | ❌ |
| L1 数据库 | PostgreSQL 连接数/事务/慢查询 | postgres-exporter 未部署 | ❌ |
| L2 日志 | stdout 日志采集与查询 | Loki + Alloy 未部署 | ❌ |
| L2 SLO 告警 | 多窗口 Burn Rate | 方法论已有，规则未落地 | ❌ |
| L3 链路 | 分布式追踪 | OTel + Tempo 未部署 | ❌ |
| L3 埋点 | 按路由 RED、业务语义指标 | 未实施 | ❌ |
| L3 前端 | RUM（JS chunk 加载失败等） | 未实施（RUNBOOK 已标注局限） | ❌ |

## 五、剩余设计路线图（按优先级）

### P0 — Phase 1 收口（无需新设计，配置即可）
1. **Alertmanager + Webhook**：启用 `alertmanager.enabled`，配置飞书/企微机器人 receiver。需提供 Webhook 地址。
2. **文档同步**：development.md 结构、README 部署步骤、PG 口径、本次发现的 3 处漂移。

### P0.5 — Phase 1.5 探测补盲（小改动）
3. **补 party-helper-realtime / party-helper-web 探测**：需确认两服务的入口端口与健康路径。
4. **PG exporter 模板 + 告警**：设计文档已给出（PgExporterDown / PgTooManyConnections），本仓库出 ServiceMonitor + Secret 模板，业务侧部署。

### P1 — SLO 告警落地（需设计：规则文件）
5. **多窗口多燃烧率 SLO 告警**：`slo-sli-error-budget.md` 已有完整方法论，待转化为 recording rules + 告警规则。建议首批 2 条 SLI：
   - 可用率（probe_success 30d 窗口，目标 99%）
   - 延迟（Beyla P95 < 500ms，目标 99%）

### P2 — Phase 2 日志（需完整设计文档）
6. **Loki + Alloy**：待设计项——部署形态（单体 vs 微服务模式）、保留期与存储、日志标签策略（namespace/pod 索引）、Grafana 日志面板、与告警联动（可选）。

### P3 — Phase 3 链路（需完整设计文档）
7. **OTel Operator + Tempo**：待设计项——FastAPI 自动注入、采样策略、Tempo 存储后端（本地 PVC 起步）、Grafana Trace 视图与指标/日志关联（exemplars）。

### 按需 — L3
8. FastAPI prometheus 埋点（按路由 RED）、前端 RUM、业务语义指标。

**建议下一步**：先做 P0 的 1+2（Phase 1 正式收口），再补 P0.5 探测盲区端口信息，SLO 设计可与 P0 并行。
