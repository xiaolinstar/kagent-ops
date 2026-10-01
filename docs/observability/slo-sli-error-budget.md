# SLO/SLI/Error Budget 实践指南

> 基于 Google SRE 方法论，将"健康生命线"理念落地为可执行的监控策略。
>
> 核心思想：**告警与业务影响对齐，而非与系统症状对齐。**

---

## 目录

1. [核心概念](#核心概念)
2. [SLI 方法论](#sli-方法论)
3. [SLO 设定策略](#slo-设定策略)
4. [Error Budget 与 Burn Rate](#error-budget-与-burn-rate)
5. [Prometheus 实现](#prometheus-实现)
6. [Grafana Dashboard](#grafana-dashboard)
7. [实践路线图](#实践路线图)
8. [常见问题与思考](#常见问题与思考)

---

## 核心概念

### 可观测性三支柱与 SLO 的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                    可观测性三支柱                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Metrics（指标）    Logs（日志）      Traces（链路）            │
│        │                  │                  │                  │
│        └──────────────────┼──────────────────┘                  │
│                           ▼                                     │
│                    ┌─────────────┐                              │
│                    │   SLI       │  ← 从三支柱中提取的关键指标   │
│                    │  服务级别   │                              │
│                    │   指标      │                              │
│                    └──────┬──────┘                              │
│                           ▼                                     │
│                    ┌─────────────┐                              │
│                    │   SLO       │  ← SLI 必须达到的目标        │
│                    │  服务级别   │                              │
│                    │   目标      │                              │
│                    └──────┬──────┘                              │
│                           ▼                                     │
│                    ┌─────────────┐                              │
│                    │   Error     │  ← SLO 允许的"故障额度"     │
│                    │   Budget    │  = 你的"健康生命线"          │
│                    │  错误预算   │                              │
│                    └──────┬──────┘                              │
│                           ▼                                     │
│                    ┌─────────────┐                              │
│                    │  Burn Rate  │  ← 消耗速度                  │
│                    │  燃烧速率   │  = 当前错误率 / 允许错误率   │
│                    └─────────────┘                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 传统告警 vs SLO 告警

| 维度 | 传统告警 | SLO 告警 |
|------|----------|----------|
| **告警对象** | 系统症状（CPU、内存、错误率） | 业务影响（用户可感知的问题） |
| **阈值设定** | 任意设定（如 CPU > 80%） | 基于 SLO 目标计算 |
| **误报率** | 高（短暂毛刺触发告警） | 低（Burn Rate 过滤噪声） |
| **漏报率** | 中（缓慢泄漏不易发现） | 低（多窗口捕获各类故障） |
| **告警语义** | "CPU 高了"（不一定有影响） | "预算在消耗"（一定有影响） |
| **响应优先级** | 不明确（所有告警看起来一样） | 明确（Burn Rate 决定优先级） |

### 核心理念映射

```
你的理念                          SRE 实现
─────────────────────────────────────────────────────────
"健康生命线"                    → Error Budget（错误预算）
"累计值超过阈值则告警"          → Burn Rate > 阈值
"否则就是健康的"                → Burn Rate ≤ 1x
"观测指标用于诊断"              → SLI（详细指标）
"业务指标是底层指标的派生"      → SLI 聚合了底层信号
```

---

## SLI 方法论

### 什么是 SLI？

**SLI（Service Level Indicator）** 是你实际测量的、用户可感知的服务质量指标。

**关键原则**：SLI 必须是**用户可感知**的，而不是系统内部状态。

### SLI 分类

```
┌─────────────────────────────────────────────────────────────────┐
│                    SLI 分类                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 可用性 SLI（Availability）                                 │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  公式：成功请求数 / 总请求数                          │  │
│      │  示例：非 5xx 响应 / 所有响应                         │  │
│      │  目标：99.9%（每月 43 分钟故障额度）                  │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   2. 延迟 SLI（Latency）                                        │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  公式：满足延迟阈值的请求数 / 总请求数                │  │
│      │  示例：P95 < 500ms 的请求比例                        │  │
│      │  目标：95% 的请求 < 500ms                            │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   3. 吞吐量 SLI（Throughput）                                   │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  公式：单位时间内处理的请求数                         │  │
│      │  示例：每秒处理 1000 个请求                          │  │
│      │  目标：支持 1000 QPS                                 │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   4. 正确性 SLI（Correctness）                                  │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  公式：返回正确结果的请求数 / 总请求数                │  │
│      │  示例：搜索结果相关性 > 90%                          │  │
│      │  目标：99% 的结果正确                                │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   5. 新鲜度 SLI（Freshness）                                    │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  公式：在时效内更新的数据比例                         │  │
│      │  示例：数据延迟 < 5 分钟                             │  │
│      │  目标：99.5% 的数据新鲜                              │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### SLI 设定方法论

#### 方法 1：用户旅程分析法

**核心思想**：从用户视角出发，分析用户的关键旅程，每个旅程定义一个 SLI。

```
┌─────────────────────────────────────────────────────────────────┐
│                    用户旅程分析                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   用户旅程：查询 kagent 知识库                                  │
│                                                                 │
│   1. 用户发送查询请求                                           │
│   2. kagent 处理查询                                            │
│   3. 返回结果给用户                                             │
│                                                                 │
│   SLI 定义：                                                    │
│   • 可用性：查询成功率（非 5xx）                                │
│   • 延迟：P95 查询延迟 < 2s                                     │
│   • 正确性：结果相关性评分 > 0.8                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 方法 2：黄金信号法（Google SRE）

**核心思想**：关注四个黄金信号，它们覆盖了大多数用户可感知的问题。

```
┌─────────────────────────────────────────────────────────────────┐
│                    四个黄金信号                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 延迟（Latency）                                           │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  定义：处理请求所需的时间                              │  │
│      │  SLI：P95/P99 延迟                                     │  │
│      │  注意：区分成功请求和失败请求的延迟                    │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   2. 流量（Traffic）                                            │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  定义：系统面临的请求量                                │  │
│      │  SLI：每秒请求数（QPS）                               │  │
│      │  用途：了解系统负载，预测容量                          │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   3. 错误（Errors）                                             │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  定义：请求失败的比例                                  │  │
│      │  SLI：错误率（5xx / 总请求）                          │  │
│      │  注意：包括显式错误和隐式错误（如超时）                │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
│   4. 饱和度（Saturation）                                       │
│      ┌───────────────────────────────────────────────────────┐  │
│      │  定义：资源使用率接近上限的程度                        │  │
│      │  SLI：CPU/内存/磁盘/网络使用率                        │  │
│      │  注意：饱和度是领先指标，但不是 SLI 首选               │  │
│      └───────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 方法 3：USE 方法（Brendan Gregg）

**核心思想**：对每个资源（Resource）关注三个维度。

```
┌─────────────────────────────────────────────────────────────────┐
│                    USE 方法                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   资源类型          Utilization    Saturation    Errors         │
│   ────────────────────────────────────────────────────────────│
│   CPU               使用率 %       运行队列长度  错误中断数     │
│   内存              使用率 %       OOM 次数      内存错误       │
│   磁盘 I/O          使用率 %       等待队列长度  I/O 错误       │
│   网络              带宽使用率     丢包率        网络错误       │
│                                                                 │
│   SLI 示例：                                                    │
│   • CPU 饱和度：运行队列长度 > CPU 核心数的时长比例            │
│   • 内存饱和度：OOM 事件发生频率                               │
│   • 磁盘饱和度：I/O 等待队列长度 > 阈值的时长比例             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 方法 4：请求驱动法（Request-Driven）

**核心思想**：从请求的角度，关注请求的完整生命周期。

```
┌─────────────────────────────────────────────────────────────────┐
│                    请求驱动法                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   请求生命周期：                                                │
│                                                                 │
│   客户端 → 负载均衡 → 应用 → 数据库 → 应用 → 客户端           │
│     │         │         │        │        │         │          │
│     └─────────┴─────────┴────────┴────────┴─────────┘          │
│                    完整请求链路                                  │
│                                                                 │
│   SLI 定义点：                                                  │
│   1. 客户端侧：端到端延迟、成功率                             │
│   2. 负载均衡侧：5xx 比例、延迟分布                           │
│   3. 应用侧：处理时间、业务错误率                             │
│   4. 数据库侧：查询延迟、连接池饱和度                         │
│                                                                 │
│   推荐：在客户端侧或负载均衡侧定义 SLI（最接近用户感知）      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### SLI 设定的最佳实践

#### 1. 选择比率，而非绝对值

```promql
# ❌ 不好：绝对值
http_requests_total{status="5xx"}

# ✅ 好：比率
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

**原因**：比率是自归一化的，不受流量变化影响。

#### 2. 区分成功和失败

```promql
# ❌ 不好：只看 5xx
sum(rate(http_requests_total{status=~"5.."}[5m]))

# ✅ 好：排除客户端错误（4xx）
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total{status!~"4.."}[5m]))
```

**原因**：4xx 是客户端问题，不是服务端故障。

#### 3. 使用合适的时间窗口

```promql
# 短窗口（5m）：响应快，但噪声大
sli:error_ratio_rate5m

# 长窗口（1h）：稳定，但响应慢
sli:error_ratio_rate1h

# 多窗口：结合两者优势
sli:error_ratio_rate1h > threshold
and
sli:error_ratio_rate5m > threshold
```

#### 4. 聚合到合适的粒度

```promql
# ❌ 太细：每个实例单独告警
sum by (instance) (rate(http_requests_total{status=~"5.."}[5m]))

# ❌ 太粗：所有服务混在一起
sum(rate(http_requests_total{status=~"5.."}[5m]))

# ✅ 合适：按服务聚合
sum by (service) (rate(http_requests_total{status=~"5.."}[5m]))
```

### 关于"丢失告警信号"的思考

你提出的问题非常深刻：

> "高可用的 5 个 ZK 节点的集群，某个节点宕机但实际上业务上无影响无感知。这些代表指标是否会导致丢失部分告警信号？"

这是 SLI 方法论的核心权衡点。

#### 分层告警策略

```
┌─────────────────────────────────────────────────────────────────┐
│                    分层告警策略                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   层级 1：SLO 告警（业务层）                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  关注：用户可感知的影响                                  │  │
│   │  SLI：可用性、延迟、错误率                              │  │
│   │  特点：噪声低，响应优先级高                             │  │
│   │  例子：API 错误率 > 0.1%                                │  │
│   └─────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│   层级 2：容量告警（资源层）                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  关注：资源使用率接近上限                                │  │
│   │  指标：CPU、内存、磁盘、连接数                          │  │
│   │  特点：领先指标，预防性告警                             │  │
│   │  例子：CPU > 80% 持续 10 分钟                           │  │
│   └─────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│   层级 3：组件健康告警（基础设施层）                            │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  关注：组件状态变化                                      │  │
│   │  指标：Pod 状态、节点状态、ZK 节点状态                  │  │
│   │  特点：噪声高，但有助于诊断                             │  │
│   │  例子：ZK 节点宕机、Pod CrashLoopBackOff               │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 你的 ZK 节点例子分析

```
┌─────────────────────────────────────────────────────────────────┐
│                    ZK 节点宕机场景分析                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   场景：5 节点 ZK 集群，1 节点宕机                              │
│                                                                 │
│   问题：业务无影响，是否需要告警？                              │
│                                                                 │
│   分析：                                                        │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  系统指标视角：                                          │  │
│   │  • ZK 节点数：5 → 4（下降 20%）                        │  │
│   │  • 集群健康度：降级                                      │  │
│   │  • 冗余度：降低                                          │  │
│   │                                                          │  │
│   │  业务指标视角：                                          │  │
│   │  • 可用性：99.9%（无变化）                              │  │
│   │  • 延迟：无变化                                          │  │
│   │  • 错误率：无变化                                        │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   结论：                                                        │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  1. SLO 告警：不触发（业务无影响）✅                    │  │
│   │  2. 容量告警：触发（冗余度降低）⚠️                      │  │
│   │  3. 组件告警：触发（节点宕机）⚠️                        │  │
│   │                                                          │  │
│   │  正确做法：                                              │  │
│   │  • SLO 告警：保持安静（不要误报）                       │  │
│   │  • 容量告警：通知运维（需要修复，但不紧急）             │  │
│   │  • 组件告警：记录日志（用于诊断）                       │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 业务指标与系统指标的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                    指标层级关系                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   系统指标（底层）                                              │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  • ZK 节点数                                            │  │
│   │  • CPU 使用率                                           │  │
│   │  • 内存使用率                                           │  │
│   │  • 磁盘 I/O                                             │  │
│   │  • 网络连接数                                           │  │
│   └─────────────────────────────────────────────────────────┘  │
│         │                                                       │
│         │ 聚合、派生                                            │
│         ▼                                                       │
│   业务指标（上层）                                              │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  • API 可用性（成功请求数 / 总请求数）                  │  │
│   │  • API 延迟（P95/P99）                                  │  │
│   │  • 查询成功率                                           │  │
│   │  • 数据新鲜度                                           │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   关系：                                                        │
│   • 业务指标异常 → 一定意味着某些系统指标异常（充分条件）      │
│   • 系统指标异常 → 不一定导致业务指标异常（非必要条件）        │
│                                                                 │
│   示例：                                                        │
│   • ZK 节点宕机（系统异常）→ 业务可能无影响（有冗余）         │
│   • API 错误率升高（业务异常）→ 一定有系统原因（需诊断）       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 如何避免"丢失信号"？

```
┌─────────────────────────────────────────────────────────────────┐
│                    避免丢失信号的策略                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   策略 1：分层告警（推荐）                                      │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  • SLO 告警：关注业务影响（低噪声）                     │  │
│   │  • 容量告警：关注资源使用（中噪声）                     │  │
│   │  • 组件告警：关注组件状态（高噪声，用于诊断）           │  │
│   │                                                          │  │
│   │  优点：既有业务保障，又不丢失基础设施信号               │  │
│   │  缺点：需要管理多个告警层级                             │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   策略 2：Error Budget 驱动的系统告警                           │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  逻辑：                                                  │  │
│   │  • 如果 Error Budget 充足：系统告警降级为 ticket        │  │
│   │  • 如果 Error Budget 紧张：系统告警升级为 page          │  │
│   │                                                          │  │
│   │  示例：                                                  │  │
│   │  • ZK 节点宕机 + Budget 充足 → 创建 ticket，本周修复   │  │
│   │  • ZK 节点宕机 + Budget 紧张 → 立即通知，尽快修复      │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   策略 3：复合健康评分（Composite Health Score）                │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  将多个系统指标聚合为一个健康评分                        │  │
│   │                                                          │  │
│   │  health_score = (                                         │  │
│   │    0.4 * availability_score +                            │  │
│   │    0.3 * capacity_score +                                │  │
│   │    0.2 * component_score +                               │  │
│   │    0.1 * performance_score                               │  │
│   │  )                                                        │  │
│   │                                                          │  │
│   │  告警条件：health_score < threshold                      │  │
│   │                                                          │  │
│   │  优点：综合考虑多个维度                                 │  │
│   │  缺点：权重设定需要调优，诊断不够直观                   │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### SLI 设定检查清单

```markdown
## SLI 设定检查清单

### 基本要求
- [ ] SLI 是否用户可感知？
- [ ] SLI 是否使用比率而非绝对值？
- [ ] SLI 是否区分成功和失败？
- [ ] SLI 是否使用合适的时间窗口？

### 覆盖度
- [ ] 是否覆盖了所有关键用户旅程？
- [ ] 是否覆盖了四个黄金信号（延迟、流量、错误、饱和度）？
- [ ] 是否有业务 SLI + 系统 SLI 的分层？

### 可操作性
- [ ] SLI 异常时，是否有明确的诊断路径？
- [ ] SLI 阈值是否基于历史数据设定？
- [ ] SLI 是否有对应的 Dashboard？

### 避免陷阱
- [ ] 是否避免了"只看系统指标"的陷阱？
- [ ] 是否避免了"阈值过于敏感"的陷阱？
- [ ] 是否避免了"只关注单点故障"的陷阱？
```

---

## SLO 设定策略

### SLO 是什么？

**SLO（Service Level Objective）** 是 SLI 必须达到的目标值。

**关键原则**：SLO 是**可靠性目标**，不是**性能目标**。它定义了"足够好"的标准，而不是"最好"的标准。

### SLO 设定方法

#### 方法 1：基于历史数据

```yaml
# 步骤 1：收集历史 SLI 数据
# 步骤 2：计算当前可靠性水平
# 步骤 3：设定略高于当前水平的目标

# 示例：
# 过去 30 天的可用性 SLI：99.95%
# 设定 SLO：99.9%（留有余量）
```

#### 方法 2：基于业务需求

```yaml
# 步骤 1：与业务团队沟通
# 步骤 2：确定用户可接受的可靠性水平
# 步骤 3：设定 SLO

# 示例：
# 业务需求：用户可接受每月最多 1 小时故障
# SLO 设定：99.8%（每月 1.4 小时故障额度）
```

#### 方法 3：基于成本收益

```yaml
# 步骤 1：估算提升可靠性的成本
# 步骤 2：估算故障带来的损失
# 步骤 3：找到成本收益平衡点

# 示例：
# 从 99.9% 提升到 99.99% 的成本：100 万/年
# 每次故障的损失：10 万
# 99.9% 的故障次数：3.6 次/年（43 分钟/月）
# 99.99% 的故障次数：0.36 次/年（4.3 分钟/月）
# 收益：减少 3.24 次故障，节省 32.4 万/年
# 结论：提升到 99.99% 不划算
```

### SLO 设定的最佳实践

#### 1. 不要追求 100%

```
┌─────────────────────────────────────────────────────────────────┐
│                    为什么不要 100%？                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 成本无限大                                                 │
│      • 100% 可靠性需要无限冗余                                  │
│      • 成本与可靠性呈指数关系                                   │
│                                                                 │
│   2. 技术不可行                                                 │
│      • 硬件故障是随机的                                         │
│      • 网络分区是不可避免的                                     │
│      • 软件 bug 是必然存在的                                   │
│                                                                 │
│   3. 业务不需要                                                 │
│      • 用户感知不到 99.99% 和 100% 的区别                      │
│      • 99.99% = 每月 4.3 分钟故障，用户可接受                  │
│                                                                 │
│   推荐：设定"用户感知不到的最低可靠性"                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 2. 设定多个 SLO

```yaml
# 为每个服务设定多个 SLO
service: kagent-api
slos:
  - name: availability
    target: 99.9%
    window: 30d
    
  - name: latency_p95
    target: 95%  # 95% 的请求 < 500ms
    window: 30d
    
  - name: latency_p99
    target: 99%  # 99% 的请求 < 1s
    window: 30d
```

#### 3. 使用滚动窗口

```yaml
# ❌ 不好：固定日历窗口
window: "2024-01-01 to 2024-01-31"

# ✅ 好：滚动窗口
window: 30d  # 过去 30 天
```

**原因**：滚动窗口更平滑，不会在月初出现"重置"。

### SLO 设定检查清单

```markdown
## SLO 设定检查清单

### 基本要求
- [ ] SLO 是否基于 SLI？
- [ ] SLO 是否使用滚动窗口？
- [ ] SLO 是否有明确的目标值？

### 合理性
- [ ] SLO 是否基于历史数据或业务需求？
- [ ] SLO 是否低于 100%？
- [ ] SLO 是否有足够的 Error Budget？

### 可执行性
- [ ] SLO 是否有对应的告警规则？
- [ ] SLO 是否有对应的 Dashboard？
- [ ] SLO 是否有 Error Budget 政策？
```

---

## Error Budget 与 Burn Rate

### Error Budget 计算

```
┌─────────────────────────────────────────────────────────────────┐
│                    Error Budget 计算                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   公式：                                                        │
│   Error Budget = 1 - SLO Target                                │
│                                                                 │
│   示例：                                                        │
│   SLO = 99.9%                                                  │
│   Error Budget = 1 - 0.999 = 0.001 = 0.1%                     │
│                                                                 │
│   时间换算（30 天窗口）：                                       │
│   30 天 = 43,200 分钟                                          │
│   Error Budget = 43,200 × 0.1% = 43.2 分钟/月                 │
│                                                                 │
│   含义：                                                        │
│   • 你每月有 43.2 分钟的"故障额度"                             │
│   • 额度充足 → 可以大胆发布新功能                              │
│   • 额度耗尽 → 停止发布，专注修复可靠性                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Burn Rate 计算

```
┌─────────────────────────────────────────────────────────────────┐
│                    Burn Rate 计算                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   公式：                                                        │
│   Burn Rate = 当前错误率 / SLO 允许的错误率                    │
│             = 当前错误率 / (1 - SLO Target)                    │
│                                                                 │
│   示例：                                                        │
│   SLO = 99.9%（允许 0.1% 错误）                                │
│   当前错误率 = 0.5%                                             │
│   Burn Rate = 0.5% / 0.1% = 5x                                 │
│                                                                 │
│   解读：                                                        │
│   • 1x  = 正常消耗，30 天刚好用完                              │
│   • 2x  = 15 天用完                                            │
│   • 5x  = 6 天用完                                             │
│   • 10x = 3 天用完                                             │
│   • 14.4x = ~2 天用完（需要立即响应）                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 四层 Burn Rate 告警策略

```
┌─────────────────────────────────────────────────────────────────┐
│                    四层 Burn Rate 告警（Google SRE 推荐）        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   层级 1：Critical（立即叫醒）                                  │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  Burn Rate ≥ 14.4x                                      │  │
│   │  长窗口：1h，短窗口：5m                                  │  │
│   │  含义：2 天内预算耗尽                                    │  │
│   │  动作：立即叫醒 on-call                                  │  │
│   │  持续时间：2 分钟                                        │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   层级 2：High（尽快响应）                                      │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  Burn Rate ≥ 6x                                         │  │
│   │  长窗口：6h，短窗口：30m                                 │  │
│   │  含义：5 天内预算耗尽                                    │  │
│   │  动作：通知 on-call，非紧急                              │  │
│   │  持续时间：5 分钟                                        │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   层级 3：Medium（本周修复）                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  Burn Rate ≥ 3x                                         │  │
│   │  长窗口：1d，短窗口：2h                                  │  │
│   │  含义：10 天内预算耗尽                                   │  │
│   │  动作：创建 ticket，本周修复                             │  │
│   │  持续时间：1 小时                                        │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   层级 4：Low（持续关注）                                       │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  Burn Rate ≥ 1x                                         │  │
│   │  长窗口：3d，短窗口：6h                                  │  │
│   │  含义：月底预算耗尽                                      │  │
│   │  动作：周会讨论，持续监控                                │  │
│   │  持续时间：2 小时                                        │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   为什么用双窗口？                                              │
│   • 长窗口：稳定信号，过滤短暂毛刺                             │
│   • 短窗口：确保问题仍在持续，快速恢复                         │
│   • 两者结合：既不误报，又不漏报                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Error Budget 政策

```yaml
# Error Budget 政策示例
error_budget_policy:
  # 预算充足时（> 50%）
  when_healthy:
    - 可以大胆发布新功能
    - 可以进行风险性变更
    - 可以尝试新技术
    
  # 预算紧张时（20-50%）
  when_warning:
    - 谨慎发布新功能
    - 增加代码审查力度
    - 增加测试覆盖
    
  # 预算危险时（< 20%）
  when_critical:
    - 停止非必要发布
    - 专注可靠性修复
    - 增加监控频率
    
  # 预算耗尽时（≤ 0%）
  when_exhausted:
    - 冻结所有发布
    - 全力修复可靠性
    - 复盘事故原因
```

---

## Prometheus 实现

### 方案 1：手动实现

#### Recording Rules（预计算 SLI 和 Burn Rate）

```yaml
# prometheus/rules/sli_recording_rules.yml
groups:
  - name: sli_recording
    interval: 30s
    rules:
      # ── SLI 计算 ──────────────────────────────────────────────
      # 5 分钟窗口的错误率
      - record: sli:http_requests:error_ratio_rate5m
        expr: |
          sum by (service) (rate(http_requests_total{status=~"5.."}[5m]))
          /
          sum by (service) (rate(http_requests_total[5m]))
        labels:
          sli_type: availability
      
      # 5 分钟窗口的成功率
      - record: sli:http_requests:success_ratio_rate5m
        expr: 1 - sli:http_requests:error_ratio_rate5m
      
      # 延迟 SLI：P95 < 500ms 的请求比例
      - record: sli:http_requests:latency_ratio_rate5m
        expr: |
          sum by (service) (rate(http_request_duration_seconds_bucket{le="0.5"}[5m]))
          /
          sum by (service) (rate(http_request_duration_seconds_count[5m]))
        labels:
          sli_type: latency
      
      # ── 多窗口 SLI（用于 Burn Rate 计算）─────────────────────
      - record: sli:http_requests:error_ratio_rate30m
        expr: |
          sum by (service) (rate(http_requests_total{status=~"5.."}[30m]))
          /
          sum by (service) (rate(http_requests_total[30m]))
      
      - record: sli:http_requests:error_ratio_rate1h
        expr: |
          sum by (service) (rate(http_requests_total{status=~"5.."}[1h]))
          /
          sum by (service) (rate(http_requests_total[1h]))
      
      - record: sli:http_requests:error_ratio_rate6h
        expr: |
          sum by (service) (rate(http_requests_total{status=~"5.."}[6h]))
          /
          sum by (service) (rate(http_requests_total[6h]))
      
      - record: sli:http_requests:error_ratio_rate1d
        expr: |
          sum by (service) (rate(http_requests_total{status=~"5.."}[1d]))
          /
          sum by (service) (rate(http_requests_total[1d]))
      
      - record: sli:http_requests:error_ratio_rate3d
        expr: |
          sum by (service) (rate(http_requests_total{status=~"5.."}[3d]))
          /
          sum by (service) (rate(http_requests_total[3d]))
```

#### Burn Rate 计算规则

```yaml
# prometheus/rules/burn_rate_rules.yml
groups:
  - name: burn_rate_calculation
    rules:
      # ── Burn Rate 计算 ────────────────────────────────────────
      # SLO = 99.9%，错误预算 = 0.001
      
      # 5 分钟 Burn Rate
      - record: slo:burn_rate:rate5m
        expr: |
          sli:http_requests:error_ratio_rate5m / 0.001
        labels:
          slo: availability
      
      # 30 分钟 Burn Rate
      - record: slo:burn_rate:rate30m
        expr: |
          sli:http_requests:error_ratio_rate30m / 0.001
      
      # 1 小时 Burn Rate
      - record: slo:burn_rate:rate1h
        expr: |
          sli:http_requests:error_ratio_rate1h / 0.001
      
      # 6 小时 Burn Rate
      - record: slo:burn_rate:rate6h
        expr: |
          sli:http_requests:error_ratio_rate6h / 0.001
      
      # 1 天 Burn Rate
      - record: slo:burn_rate:rate1d
        expr: |
          sli:http_requests:error_ratio_rate1d / 0.001
      
      # 3 天 Burn Rate
      - record: slo:burn_rate:rate3d
        expr: |
          sli:http_requests:error_ratio_rate3d / 0.001
```

#### Alert Rules（四层告警）

```yaml
# prometheus/rules/slo_alerts.yml
groups:
  - name: slo_alerts
    rules:
      # ── 层级 1：Critical（立即叫醒）──────────────────────────
      - alert: SLOBurnRateCritical
        expr: |
          slo:burn_rate:rate1h > 14.4
          and
          slo:burn_rate:rate5m > 14.4
        for: 2m
        labels:
          severity: critical
          slo: availability
          response: page
        annotations:
          summary: "Critical: Error budget burning at {{ $value }}x rate"
          description: |
            1-hour burn rate is {{ $value }}x. 
            At this rate, 30-day error budget will be exhausted in ~2 days.
            Immediate investigation required.
          runbook: "https://wiki.internal/runbooks/slo-critical-burn"
      
      # ── 层级 2：High（尽快响应）──────────────────────────────
      - alert: SLOBurnRateHigh
        expr: |
          slo:burn_rate:rate6h > 6
          and
          slo:burn_rate:rate30m > 6
        for: 5m
        labels:
          severity: warning
          slo: availability
          response: page
        annotations:
          summary: "High: Error budget burning at {{ $value }}x rate"
          description: |
            6-hour burn rate is {{ $value }}x.
            At this rate, 30-day error budget will be exhausted in ~5 days.
          runbook: "https://wiki.internal/runbooks/slo-high-burn"
      
      # ── 层级 3：Medium（本周修复）────────────────────────────
      - alert: SLOBurnRateMedium
        expr: |
          slo:burn_rate:rate1d > 3
          and
          slo:burn_rate:rate2h > 3
        for: 1h
        labels:
          severity: warning
          slo: availability
          response: ticket
        annotations:
          summary: "Medium: Error budget burning at {{ $value }}x rate"
          description: |
            1-day burn rate is {{ $value }}x.
            At this rate, 30-day error budget will be exhausted in ~10 days.
            Create reliability ticket and fix this week.
          runbook: "https://wiki.internal/runbooks/slo-medium-burn"
      
      # ── 层级 4：Low（持续关注）──────────────────────────────
      - alert: SLOBurnRateLow
        expr: |
          slo:burn_rate:rate3d > 1
          and
          slo:burn_rate:rate6h > 1
        for: 2h
        labels:
          severity: info
          slo: availability
          response: watch
        annotations:
          summary: "Low: Error budget trend concerning"
          description: |
            3-day burn rate is {{ $value }}x.
            Error budget trending towards exhaustion by month end.
            Discuss in weekly reliability review.
```

#### Error Budget 剩余量

```yaml
# prometheus/rules/error_budget_rules.yml
groups:
  - name: error_budget
    rules:
      # ── Error Budget 剩余量 ──────────────────────────────────
      # 30 天窗口的错误预算剩余百分比
      
      - record: slo:error_budget:remaining_pct
        expr: |
          1 - (
            sum by (service) (increase(http_requests_total{status=~"5.."}[30d]))
            /
            sum by (service) (increase(http_requests_total[30d]))
          ) / 0.001
        labels:
          slo: availability
```

### 方案 2：使用 Sloth 自动生成（推荐）

#### 安装 Sloth

```bash
# 使用 Helm 安装
helm repo add sloth https://sloth-dev.github.io/sloth
helm install sloth sloth/sloth -n monitoring

# 或者使用 Docker
docker run --rm -v $(pwd):/slok/sloth slok/sloth generate -i /slok/sloth/slo.yaml
```

#### SLO 定义文件

```yaml
# slo/kagent-api.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: kagent-api
  namespace: monitoring
spec:
  service: "kagent-api"
  labels:
    team: "kagent"
  
  slos:
    # ── 可用性 SLO ─────────────────────────────────────────────
    - name: "availability"
      objective: 99.9
      description: "99.9% of API requests must succeed"
      
      sli:
        events:
          error_query: |
            sum(rate(http_requests_total{service="kagent-api", status=~"5.."}[{{.window}}]))
          total_query: |
            sum(rate(http_requests_total{service="kagent-api"}[{{.window}}]))
      
      alerting:
        name: "KagentAPIAvailability"
        labels:
          category: "availability"
        annotations:
          summary: "Kagent API availability SLO burning fast"
        
        page_alert:
          labels:
            severity: critical
        
        ticket_alert:
          labels:
            severity: warning
    
    # ── 延迟 SLO ─────────────────────────────────────────────
    - name: "latency"
      objective: 95
      description: "95% of requests must complete under 500ms"
      
      sli:
        events:
          error_query: |
            sum(rate(http_request_duration_seconds_bucket{service="kagent-api", le="0.5"}[{{.window}}]))
          total_query: |
            sum(rate(http_request_duration_seconds_count{service="kagent-api"}[{{.window}}]))
      
      alerting:
        name: "KagentAPILatency"
        labels:
          category: "latency"
```

#### 生成 Prometheus 规则

```bash
# 生成所有规则
sloth generate -i slo/kagent-api.yaml -o prometheus/rules/kagent-api-slo.yaml

# 输出包含：
# - Recording rules（SLI 计算）
# - Burn rate rules（燃烧速率）
# - Alert rules（四层告警）
```

---

## Grafana Dashboard

### SLO Dashboard 设计

```json
{
  "title": "SLO Dashboard - kagent-api",
  "panels": [
    {
      "title": "Error Budget Remaining",
      "type": "gauge",
      "targets": [{
        "expr": "slo:error_budget:remaining_pct{service=\"kagent-api\"}"
      }],
      "thresholds": {
        "steps": [
          {"color": "red", "value": 0},
          {"color": "yellow", "value": 20},
          {"color": "green", "value": 50}
        ]
      }
    },
    {
      "title": "SLI: Availability (30d rolling)",
      "type": "stat",
      "targets": [{
        "expr": "1 - slo:sli_error:ratio_rate5m{sloth_slo=\"availability\", service=\"kagent-api\"}"
      }],
      "fieldConfig": {
        "unit": "percentunit",
        "thresholds": {
          "steps": [
            {"color": "red", "value": 0.999},
            {"color": "green", "value": 0.9995}
          ]
        }
      }
    },
    {
      "title": "Burn Rate (1h window)",
      "type": "timeseries",
      "targets": [{
        "expr": "slo:burn_rate:rate1h{service=\"kagent-api\"}"
      }],
      "thresholds": {
        "steps": [
          {"color": "green", "value": 1},
          {"color": "yellow", "value": 6},
          {"color": "red", "value": 14.4}
        ]
      }
    },
    {
      "title": "Error Budget Consumption Over Time",
      "type": "timeseries",
      "targets": [{
        "expr": "slo:error_budget:consumed_pct{service=\"kagent-api\"}"
      }]
    }
  ]
}
```

---

## 实践路线图

### 阶段 1：基础 SLI（1-2 周）

```markdown
## 目标
- 识别关键用户旅程
- 定义基本 SLI
- 验证 SLI 数据收集

## 步骤
1. 列出所有 API 端点
2. 识别关键用户旅程（如：查询、创建、更新）
3. 为每个旅程定义 SLI（可用性、延迟）
4. 验证 Prometheus 能采集到数据
5. 创建基础 Grafana Dashboard

## 产出
- SLI 定义文档
- Prometheus 配置
- 基础 Dashboard
```

### 阶段 2：SLO 设定（1 周）

```markdown
## 目标
- 设定合理的 SLO 目标
- 计算 Error Budget
- 设定 Error Budget 政策

## 步骤
1. 分析历史 SLI 数据
2. 与业务团队沟通，确定 SLO 目标
3. 计算 Error Budget
4. 制定 Error Budget 政策
5. 更新 Dashboard，显示 SLO 目标线

## 产出
- SLO 定义文档
- Error Budget 政策
- 更新后的 Dashboard
```

### 阶段 3：Burn Rate 告警（1-2 周）

```markdown
## 目标
- 实现 Burn Rate 计算
- 配置四层告警规则
- 验证告警准确性

## 步骤
1. 安装 Sloth 或手动创建 Recording Rules
2. 配置 Burn Rate 计算规则
3. 配置四层告警规则
4. 测试告警（模拟故障）
5. 调优阈值和窗口

## 产出
- Prometheus 告警规则
- Alertmanager 配置
- 告警测试报告
```

### 阶段 4：持续优化（持续）

```markdown
## 目标
- 优化 SLO 目标
- 完善告警策略
- 建立可靠性文化

## 步骤
1. 每月复盘 Error Budget 使用情况
2. 根据业务变化调整 SLO 目标
3. 优化告警阈值，减少误报
4. 培训团队，建立可靠性文化
5. 探索高级功能（如复合健康评分）

## 产出
- 月度可靠性报告
- 优化后的 SLO 配置
- 团队培训材料
```

---

## 常见问题与思考

### Q1：SLI 会导致丢失告警信号吗？

**A**：会，但这是**有意为之**的设计。

```
┌─────────────────────────────────────────────────────────────────┐
│                    SLI 的"丢失信号"是特性，不是 bug             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   场景：ZK 节点宕机，但业务无影响                               │
│                                                                 │
│   传统告警：                                                    │
│   • ZK 节点宕机 → 告警                                         │
│   • 问题：噪声高，工程师疲劳                                   │
│                                                                 │
│   SLI 告警：                                                    │
│   • ZK 节点宕机 → 不告警（业务无影响）                         │
│   • 优点：噪声低，工程师信任告警                               │
│   • 缺点：可能错过"潜在风险"                                   │
│                                                                 │
│   解决方案：分层告警                                            │
│   • SLI 告警：关注业务影响（低噪声）                           │
│   • 容量告警：关注资源使用（中噪声）                           │
│   • 组件告警：关注组件状态（高噪声，用于诊断）                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Q2：业务指标和系统指标的关系是什么？

**A**：业务指标是系统指标的**聚合和派生**。

```
┌─────────────────────────────────────────────────────────────────┐
│                    指标层级关系                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   系统指标（底层）                                              │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  • ZK 节点数                                            │  │
│   │  • CPU 使用率                                           │  │
│   │  • 内存使用率                                           │  │
│   │  • 磁盘 I/O                                             │  │
│   │  • 网络连接数                                           │  │
│   └─────────────────────────────────────────────────────────┘  │
│         │                                                       │
│         │ 聚合、派生                                            │
│         ▼                                                       │
│   业务指标（上层）                                              │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  • API 可用性（成功请求数 / 总请求数）                  │  │
│   │  • API 延迟（P95/P99）                                  │  │
│   │  • 查询成功率                                           │  │
│   │  • 数据新鲜度                                           │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   关系：                                                        │
│   • 业务指标异常 → 一定意味着某些系统指标异常（充分条件）      │
│   • 系统指标异常 → 不一定导致业务指标异常（非必要条件）        │
│                                                                 │
│   示例：                                                        │
│   • ZK 节点宕机（系统异常）→ 业务可能无影响（有冗余）         │
│   • API 错误率升高（业务异常）→ 一定有系统原因（需诊断）       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Q3：如何平衡"低噪声"和"不丢失信号"？

**A**：使用**分层告警策略**。

```
┌─────────────────────────────────────────────────────────────────┐
│                    分层告警策略                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   层级 1：SLO 告警（业务层）                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  关注：用户可感知的影响                                  │  │
│   │  SLI：可用性、延迟、错误率                              │  │
│   │  特点：噪声低，响应优先级高                             │  │
│   │  例子：API 错误率 > 0.1%                                │  │
│   └─────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│   层级 2：容量告警（资源层）                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  关注：资源使用率接近上限                                │  │
│   │  指标：CPU、内存、磁盘、连接数                          │  │
│   │  特点：领先指标，预防性告警                             │  │
│   │  例子：CPU > 80% 持续 10 分钟                           │  │
│   └─────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│   层级 3：组件健康告警（基础设施层）                            │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  关注：组件状态变化                                      │  │
│   │  指标：Pod 状态、节点状态、ZK 节点状态                  │  │
│   │  特点：噪声高，但有助于诊断                             │  │
│   │  例子：ZK 节点宕机、Pod CrashLoopBackOff               │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   关键原则：                                                    │
│   • SLO 告警用于"叫人"（必须响应）                            │
│   • 容量告警用于"预防"（提前处理）                            │
│   • 组件告警用于"诊断"（事后分析）                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Q4：Error Budget 耗尽时应该怎么办？

**A**：停止发布，专注修复可靠性。

```
┌─────────────────────────────────────────────────────────────────┐
│                    Error Budget 耗尽时的响应                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   立即行动：                                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  1. 冻结所有非必要发布                                   │  │
│   │  2. 召集紧急会议，分析事故原因                          │  │
│   │  3. 制定修复计划                                         │  │
│   │  4. 增加监控频率                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   修复优先级：                                                  │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  1. 修复导致事故的 bug                                   │  │
│   │  2. 增加冗余和容错能力                                   │  │
│   │  3. 改进监控和告警                                       │  │
│   │  4. 优化发布流程                                         │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│   恢复发布：                                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  • Error Budget 恢复到 > 20%                            │  │
│   │  • 修复计划已完成                                        │  │
│   │  • 增加的监控已验证                                      │  │
│   │  • 团队对修复有信心                                      │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Q5：如何说服团队采用 SLO 方法？

**A**：从**解决实际问题**开始，而不是从**理论**开始。

```
┌─────────────────────────────────────────────────────────────────┐
│                    说服团队的策略                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 识别痛点                                                   │
│      • "告警太多，不知道哪些重要"                              │
│      • "CPU 告警了，但用户没感知"                               │
│      • "故障了才发现，没有预警"                                 │
│                                                                 │
│   2. 展示价值                                                   │
│      • "SLO 告警只在用户受影响时触发"                          │
│      • "Burn Rate 告警过滤了 90% 的噪声"                      │
│      • "Error Budget 让发布决策有据可依"                       │
│                                                                 │
│   3. 小范围试点                                                 │
│      • 选择一个关键服务                                        │
│      • 设定一个 SLO                                            │
│      • 配置 Burn Rate 告警                                     │
│      • 对比传统告警的噪声                                      │
│                                                                 │
│   4. 逐步推广                                                   │
│      • 分享试点成果                                            │
│      • 培训团队                                                │
│      • 建立可靠性文化                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 参考资源

### 书籍
- [Google SRE Book](https://sre.google/sre-book/table-of-contents/)
- [Google SRE Workbook](https://sre.google/workbook/table-of-contents/)

### 工具
- [Sloth](https://github.com/slok/sloth) - SLO 规则生成器
- [Pyrra](https://github.com/pyrra-dev/pyrra) - SLO 管理平台
- [OpenSLO](https://openslo.com/) - SLO 标准规范

### 文档
- [Prometheus Recording Rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Grafana SLO Dashboard](https://grafana.com/docs/grafana/latest/dashboards/)

---

## 附录：术语表

| 术语 | 英文 | 定义 |
|------|------|------|
| SLI | Service Level Indicator | 服务级别指标，用户可感知的服务质量指标 |
| SLO | Service Level Objective | 服务级别目标，SLI 必须达到的目标值 |
| SLA | Service Level Agreement | 服务级别协议，与客户的外部合同 |
| Error Budget | 错误预算 | SLO 允许的"故障额度" |
| Burn Rate | 燃烧速率 | Error Budget 的消耗速度 |
| MWMBR | Multi-Window Multi-Burn-Rate | 多窗口多燃烧速率告警策略 |

---

> **最后的话**：
>
> SLO/SLI/Error Budget 不是一个技术方案，而是一种**思维方式**。
>
> 它的核心是：**从用户视角定义可靠性，用数据驱动决策，用预算管理风险。**
>
> 技术只是实现手段，思维方式才是关键。