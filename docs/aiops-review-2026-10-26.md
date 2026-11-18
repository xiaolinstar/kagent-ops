# kagent v1 AI 运维适用性审查

审查日期：2026-10-26（Asia/Shanghai）。范围：仓库配置、随仓库保存的 alpha13 Helm Chart/CRD、两个本地 Kubernetes context 的只读状态。未修改集群、未启动工作负载、未调用外部模型。

## 结论与定位

建议继续使用 kagent v1，定位为 AI 运维的 Agent 运行、诊断推理和工具调用核心。当前仓库属于安装与监控实践原型，尚未形成可运行、可复现、可控制变更的 AI 运维系统。

kagent 的具体基线为 **1.0.0-alpha13**，不是 v1 稳定版。不要把 v0.10 的 Agent 定义或最新版 1.x 文档直接作为 alpha13 的配置依据；以所选版本的 Chart、CRD 和运行时行为为准。

运维平台仍需要确定性的告警接入、事件持久化、权限和变更审批、执行幂等、恢复验证。这些能力可以围绕 kagent 建设；本次未对上游所有内建功能做穷尽审计，以下“缺失”指本仓库未配置或未实现。

## 当前状态：实测与文档区分

只读查询指定 context，未切换用户默认 context。

| 检查项 | 2026-10-26 实测 |
| --- | --- |
| kind-kagent Helm release | kagent revision 4、kagent-crds revision 2，均为 1.0.0-alpha13，状态 deployed |
| kagent 工作负载 | controller、ui、tools、grafana-mcp、kmcp、postgresql 的 Deployment 全部 0/0 |
| Agent / Harness | kagent 命名空间下未发现资源 |
| ModelConfig | default-model-config 存在，OpenAI / deepseek-flash |
| RemoteMCPServer | kagent-api、kagent-tool-server、kagent-grafana-mcp 存在，Accepted=True；这不证明当前端点可用 |
| ate-system | 6 个 Deployment 全部 0/0；atelet 1/1 Running，rustfs 初始化 Job Completed |
| monitoring | kind-kagent 未发现 Pod；docker-desktop 未发现 Pod、Deployment、StatefulSet 或 monitoring 命名空间的 Helm release |
| 实际 Substrate 配置 | Helm 用户值为 api.ate-system.svc 与 atenet-router.ate-system.svc，区别于仓库中的 localhost |
| 工具权限 | 集群中的 kagent-tools-cluster-admin-role 包含 apiGroups/resources/verbs 全部通配符 |

缩容可能是用户主动暂停，不能由此推断安装失败。但当前无法验证 Agent 对话、模型工具调用或监控告警端到端可用。INSTALL-SUMMARY.md 的“全部组件运行正常”和 10 月 11 日验收报告仅能作为历史记录。

## 发现与处理优先级

### F1 [P1] v0/v1 资源混用，运维 Agent 无法按现有指引迁移

证据：README.md 安装命令仍指定 0.10.1；kagent-config/helm/values.yaml 指定 alpha13 并让用户 apply kagent-config/crds/agents.yaml，但该文件中的 helm-agent、k8s-agent、observability-agent、promql-agent 均为 kagent.dev/v1alpha2。model-config.yaml 也使用旧 API。alpha13 包内 CRD 为 api.kagent.dev/v1alpha3，Agent 的 spec 必需 harnessRef 和 template。

影响：在纯 v1 集群中旧资源不能作为 v1 Agent 使用；即使残留旧 CRD，创建的也是另一 API group 的旧对象。只改 apiVersion 无法迁移字段结构。

建议：统一安装入口与版本清单，将四个 Agent 的模型、提示词和工具白名单迁移为 v1 template，配套 Harness；旧文件移入明确的 legacy 目录。README 与 CLAUDE.md 同步。固定 CLI、kagent、CRD、Substrate 和运行时镜像版本及摘要。

### F2 [P1] 仓库覆盖 Substrate 为 localhost，重放配置会破坏连接

证据：kagent-config/helm/values.yaml:35-37；helm template 的 controller 配置仍为 dns:///localhost:443 与 http://localhost:80。Chart 默认值及已安装 release 使用 ate-system 的服务地址；渲染出的 controller Pod 没有承载 Substrate 的 sidecar。

影响：按仓库 values 升级会使 controller 连接自身 Pod 的回环地址，无法到达独立的 Substrate 服务。这个问题存在于仓库期望配置，实际 Helm 用户值当前正确。

建议：去除错误覆盖或使用实测服务地址。安装流程需同时覆盖数据库、Substrate 与 kagent，不能只运行当前 README 的两条 Helm 安装命令。

### F3 [P1] 两份 Harness 示例均不能直接通过 alpha13 的关键约束

证据：test-harness.yaml 只有 kagent: {}，缺少 CRD 必需的 substrate、workload；harness-example.yaml:32 的镜像摘要是占位符，不满足 @sha256 后 64 位十六进制的约束。两份 Agent 示例均指向该 Harness；test-agent.yaml 的 tools 为空。

影响：当前没有一套可直接使用的 v1 运维 Agent 定义，也没有已运行的 Agent 可证明工具链可用。

建议：提供一套完整、固定镜像摘要的只读诊断 Agent + Harness + ModelConfig + RemoteMCPServer 引用；验证 WorkerPool、快照位置与运行时镜像匹配。不要把模板占位符作为可直接 apply 的生产清单。

### F4 [P1] 工具权限过大，尚未建立变更隔离

证据：本地 Chart 渲染和实际 ClusterRole 均确认 kagent-tools 为集群管理员。仓库没有覆盖 kagent-tools.rbac.readOnly；旧 Agent 白名单含 k8s_delete_resource、k8s_execute_command、k8s_apply_manifest、helm_upgrade 等。values 中 auth.mode=insecure，Grafana 使用 admin/admin 且启用匿名 Viewer。

影响：若按原有 Agent 能力恢复并开放访问，模型误判或从日志/资源文本接收恶意指令时，工具身份拥有修改全群资源的能力。Prompt 中要求谨慎或先询问不能替代实际权限限制。当前缩容状态不等于该风险正在被利用。

建议：第一阶段 tools 使用 rbac.readOnly: true、allowSecrets: false，配合工具层只读模式、命名空间限制和显式白名单。审核 read-only ClusterRole 的实际资源范围，并避免 exec 等旁路。写操作使用独立 MCP 服务与独立身份，经过外部策略与审批，再执行固定动作。鉴权、网络隔离与模型出口策略应配套实施；Substrate 沙箱不能代替 MCP 服务的 Kubernetes RBAC。

### F5 [P1] 监控工具地址未绑定实际监控拓扑

证据：仓库仅启用 kagent-tools，没有配置其 tools.prometheus.url。渲染结果为 prometheus.kagent.svc.cluster.local:9090，而文档的 Prometheus 服务为 monitoring-kube-prometheus-prometheus.monitoring。grafana-mcp 指向 monitoring-grafana.monitoring，但当前两个本地 context 均未观察到 monitoring 工作负载。

影响：即使恢复 Agent，其指标查询也不能据现有配置保证可用。跨集群的 *.svc DNS 不会自动解析为另一个集群的服务；在 kind 中运行的工具也只会使用其所在集群的身份，不能自动管理 docker-desktop 业务。

建议：明确管理集群与业务集群的归属。单集群 MVP 将监控、MCP 和业务目标放在同一集群；多集群方案在目标集群部署受限工具服务，通过鉴权入口接入，显式携带 cluster_id，绑定允许的集群与命名空间。

### F6 [P1] 告警没有进入 AI 诊断流程

证据：monitoring/values.yaml:122-123 禁用 Alertmanager；历史验收报告也明确告警送达未通过。仓库未实现告警接入服务、去重与队列、事件到 Agent 会话的映射、审批状态或执行后验证。

影响：当前能力偏向人工发起的问答，无法自动完成发现 → 诊断 → 处置建议 → 恢复验证。

建议：先落地告警到只读诊断报告的流程。Alertmanager webhook 进入接入服务，校验来源、按 fingerprint/cluster 去重、持久化事件并异步调用 kagent，输出证据与建议。设置超时、重试上限、并发限制、事件合并、resolved 事件处理与模型不可用时的传统通知兜底。不要让 LLM 决定告警是否需要送达。

### F7 [P2] 慢探测告警查询了不存在的直方图指标

证据：http-availability.yaml:34-41 对 probe_duration_seconds_bucket 执行 histogram_quantile。Blackbox Exporter 的 probe_duration_seconds 是 Gauge，并不提供对应的 bucket 序列。

影响：PromQL 可以语法正确但返回空结果，HttpProbeSlow 无法按设计触发。

建议：按探测耗时目标使用 probe_duration_seconds 的阈值或时间窗口 quantile_over_time，并正确描述为“探测样本的时间分位数”；业务请求 P95 使用 Beyla 的 http_server_request_duration_seconds_bucket。用真实指标检查序列存在，再对正常、慢响应、无数据分别做规则验证。

### F8 [P2] kagent 自监控抓取配置与 alpha13 不匹配

证据：monitoring/values.yaml:51 使用 app.kubernetes.io/name=kagent-controller 过滤，而 alpha13 渲染 controller 的该标签为 kagent；重标记 regex 只有一个捕获组却引用 ${2}。Chart 当前渲染 metrics.bindAddress 为 "0"，即指标监听关闭。

影响：现有 additionalScrapeConfigs 不能提供有效的 controller 自监控。

建议：启用 controller.metrics.enabled，使用 Chart 配套 ServiceMonitor，按 secure/auth 配置其 Prometheus 服务账号权限，并验证 up、请求错误率、Agent 工具调用失败率、运行时延迟与队列状态。

### F9 [P2] 凭证与持久化方案仍是本地实验级

证据：未跟踪的 deepseek-secret.yaml 包含非空、非明显占位的值（审查未输出其内容），且 .gitignore 未忽略该文件。postgresql-deploy.yaml 使用明文固定密码、单副本 Deployment 和 1Gi PVC，没有备份恢复流程；安装总结却称数据库为主从 2 副本。README 还声称“数据不出集群”，但模型地址为公网 DeepSeek API。

影响：凭证可能被误提交；PVC 无法替代备份；发送给模型的日志和工具输出可能离开集群。未证明凭证已泄露，也未证明数据库实际曾按该清单运行。

建议：将本地 Secret 文件纳入忽略，提交前扫描，使用外部 Secret 管理或加密清单；若发现外泄再轮换。生产数据库增加备份恢复演练、资源与健康检查，明确会话与快照保留策略。更正文档的数据边界，模型输入脱敏，限制日志长度并排除 Secret 内容。

## 推荐的目标流程

```text
Prometheus / Alertmanager
        ↓
告警接入服务：鉴权、去重、事件持久化、队列、限流
        ↓
kagent v1：AgentTemplate / Agent + Harness + Substrate
        ↓
只读 MCP：Kubernetes 状态与事件、Prometheus、日志、发布记录
        ↓
结构化诊断报告：证据、根因假设、置信度、缺失信息、建议动作
        ↓
策略检查 + 人工审批 → 独立执行服务 / GitOps → 恢复验证与事件归档
```

建议先设一个 SRE 诊断入口 Agent，再按实际收益拆分领域 Agent。MVP 不要求先建设多 Agent 委派。kagent 提供 Agent 与工具集成基础；告警事件生命周期和审批执行流程需要在项目中明确实现或配置。

诊断报告至少包含 incident_id、cluster、namespace、时间范围、目标资源 UID/resourceVersion、查询与证据、根因候选、置信度、缺失信息、建议动作及回滚和验证条件。日志与资源内容一律作为不可信证据，不允许其覆盖系统权限或触发任意命令。

审批应绑定确切目标、动作参数和有效期；执行前重新检查对象版本与前置条件。执行服务记录幂等键、操作者、审批人、工具参数、结果和验证证据。自动修复应从固定白名单动作逐步引入，并设置最大影响范围、熔断和人工接管入口。

## 分阶段交付与验收

| 顺序 | 交付 | 验收条件 |
| --- | --- | --- |
| 1：统一 v1 基线 | 单一安装入口，锁定版本，修复 F1-F3，记录环境状态 | 从干净测试集群复现安装；Agent/Harness Ready；一次模型对话和一次受限工具查询成功 |
| 2：只读运维助手 | 修复 F4-F5，接通 Kubernetes、Prometheus 与所需日志 | 查询目标集群资源与指标；业务故障诊断有可核查证据；写入、Secret 读取、越权访问均被拒绝 |
| 3：告警自动诊断 | 接入服务、事件存储、异步诊断、通知兜底 | 注入一次测试故障只生成一个事件；重复告警合并；生成报告；恢复后归档；模型失败不影响传统告警 |
| 4：审批后修复 | 独立写工具、策略、审批、验证与回滚 | 审批不可复用到其他目标；过期/版本漂移拒绝执行；重复请求不重复变更；失败可回滚并保留审计 |
| 5：有限自动化 | 针对已验证 Runbook 的受控自动动作 | 对选定故障集统计诊断准确率、工具成功率、误操作、耗时、成本；达到团队明确阈值再扩大范围 |

建议首批演练：CrashLoopBackOff、OOMKilled、Service 无 Endpoint、HTTP 探测失败。另需覆盖提示注入、重复告警、错误集群、模型超时、MCP 不可用及无数据等失败路径。不要用模型自己的“已修复”作为恢复证据，应重新查询资源状态和监控指标。

## 验证方法与边界

- 本地 alpha13 Chart 执行 helm template 成功；这只证明可渲染，不证明运行时配置正确。
- 29 个 YAML 文件完成语法解析；Secret 的内容未回显。
- 用包内 CRD 核对 API group、必需字段和 Harness 镜像摘要约束；未声称运行了完整 Kubernetes OpenAPI/CEL 校验。
- 只读查询 Helm release、工作负载、v1 CRD 对象、选定非敏感 Helm 配置及工具 ClusterRole。
- 未恢复已缩容服务，未执行模型调用、业务故障注入、写权限测试或恢复演练；上述验收仍需实施。

## 上游参考

- [alpha13 发布记录](https://github.com/kagent-dev/kagent/releases/tag/v1.0.0-alpha13)：版本基线。
- [kagent 1.x 创建 Agent](https://kagent.dev/docs/kagent/1.x/get-started/your-first-agent/)：当前 1.x 文档，具体字段仍需匹配 alpha13 包内 CRD。
- [Blackbox Exporter 指标实现](https://github.com/prometheus/blackbox_exporter/blob/master/prober/handler.go)：probe_duration_seconds 为 Gauge；未锁定本项目实际 exporter 镜像版本，恢复监控后应再次检查实际 /probe 输出。
