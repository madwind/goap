# 调度、重规划与性能

[文档首页](README.md)

## 请求与共享预算

Agent 自动请求初始计划。事实变化、动作失败、目标完成或失效，以及显式 `request_replan()` 都会触发后续规划。不要在没有相关变化时每帧请求规划；新请求会使之前的 generation 失效。

替换一个有效的本地计划时，所有有效目标直接按 Priority 降序、同值按稳定 ID 排序；排名更高且可达的目标可以替换当前计划。成本、可用性、Priority 输入或动作/目标定义发生变化，但没有事实变化时，应显式调用 `request_replan()`。

所有运行时 Agent 共用一个按 SceneTree 自动创建的 `GoapPlanningScheduler`。默认 `asynchronous_planning = true`，搜索和成本评估在工作线程执行。设为 `false` 时仍使用共享帧预算，只是计算改在主线程完成。应在请求开始前配置此选项。

| 项目设置 | 默认值 | 含义 |
| --- | ---: | --- |
| `goap/planning/frame_budget_ms` | 2.0 | 每渲染帧共享主线程预算；0 暂停新工作 |
| `goap/planning/slice_budget_ms` | 0.25 | 每个 Agent 的主线程时间片 |
| `goap/planning/worker_slice_ms` | 2.0 | 每次后台派发的工作时间片 |
| `goap/planning/max_worker_tasks` | 2 | 最多派发的工作线程任务数，最少为 1 |

项目设置中没有这些字段时也会使用默认值。运行时可通过 `GoapPlanningScheduler.for_tree(get_tree())` 获取调度器并修改同名属性。预算是所有 Agent 共享，不是每个 Agent 各自拥有一份。

等待期间 `is_planning()` 为真，当前仍有效的动作可以继续执行。预算耗尽不代表目标失败，也不会因此改选低优先级目标。结果在搜索/评估结束或节点上限得到处理后安装，不会从仍在执行的候选中临时挑选结果。过期 generation 被丢弃；移除 Agent 会取消注册，并安全回收工作线程片段。

预算是软限制：单个回调、排序、复制或搜索扩展无法执行到一半就抢占。后台规划可以降低主线程开销，也可能增加响应延迟。`find_plan()` 是阻塞式工具接口，不受运行时帧预算限制。

单纯关闭物理处理不等于取消规划。游戏死亡或禁用时调用 `agent.suspend()`：使请求失效、停止当前动作，并拒绝新的规划。`agent.resume()` 恢复并请求新计划；游戏可在恢复前同步事实。`agent.cancel_planning()` 只取消待处理计算，保留当前计划。`is_suspended` 是只读状态，重复暂停或恢复不会重复清理。

## 预构建与缓存

动作配置完成后，可以在加载阶段主动构建不可变事实快照与 Effect 索引：

```gdscript
agent.init_goap()
if not agent.prewarm_planning():
	push_error("GOAP action IDs must be nonempty and unique")

# 独立规划器也支持预热，同一个实例的后续 find_plan() 会复用缓存。
var planner := GoapPlanner.new(actions)
planner.prewarm()
```

预热是同步操作，应安排在加载阶段；它不执行动作可用性、成本或目标回调。没有预热时，正常请求会在共享预算下逐步构建并保存缓存。每个 Agent / 独立 Planner 只保留最近一个有序动作集合的索引；运行时筛选出的可用集合与预热集合不同时，会重新构建索引。

前置条件和效果的事实快照按内容变化失效。通过 `set_state()`、`merge()`（包括 `emit_change=false`）修改事实，替换状态对象，或改变动作 ID、顺序、集合，都会在后续请求中检测并更新。不要直接修改 `GoapWorldState._state`。`snapshot()` 返回只读快照，需要可写副本时使用 `to_dictionary()`。动作定义变化本身不自动请求重规划，仍应调用 `request_replan()`。

缓存数据只读，旧 worker 保留原快照，新请求发布新索引。世界状态、目标 Priority、动作可用性、成本上下文和成本评估仍按请求更新。缓存不保存最终计划或候选路径，主要减少重复准备开销，不能消除分支组合增长。

当前实现的顺序是：

1. 加载并配置 Action；可选调用 `prewarm_planning()` / `prewarm()`，校验 ID、生成只读前置条件和效果快照、构建并缓存 Effect 索引。此时不计算成本。
2. 运行时请求先复制世界事实、筛选并排序目标；没有待规划目标则结束。
3. 在主线程采集初始成本模拟状态，逐个检查动作可用性、取得动作定义快照、检查成本模型并采集只读 Context。
4. 按动作 ID 排序，将本次有序定义与缓存比较；命中则复用索引，否则分片构建新索引并发布缓存。当前实现仍会进行每次请求的筛选和排序。
5. 按目标优先级搜索候选，再逐条正向评估成本；异步模式下这两步在 worker 执行。Action 的固定 `cost`（默认 1）也仍使用此流程。
6. 主线程回收结果，确认 generation 有效后安装计划。

Action 的 `cost` 与模型 Context 每次请求重新采集；预热只准备动作事实定义和 Effect 索引，不提前计算动作成本或最终计划。详情见[成本与缓存](COSTS.md#成本与缓存)。

## 请求状态与线程交接

`GoapPlanningRequest` 在主线程依次处理 setup、目标排序、成本初始快照、动作筛选/采集、Effect 索引和逐目标规划。对外 phase 使用 `preparing`、`searching`、`evaluating`、`completed`；实际执行由可恢复的游标保存进度。

内部准备步骤和工作阶段使用枚举。`request_finished` 表示请求结束，`search_complete` 表示搜索完整性；待处理报告中的后者为 null。两者独立，节点上限和输入错误都可以产生已结束的请求。

Agent 每次请求增加 generation。调度器不会让旧请求结果覆盖新请求；正在运行的旧 worker 不会被强杀，而是让本次片段完成后回收，不再派发它。调度器限制的是所有请求的并发任务总量，不是每个角色独占两个线程。

worker 处理隔离的事实和动作记录、成本数据、经过检查的静态模型脚本。片段运行时主线程不能读取或修改 worker_data；调用 `wait_for_task_completion()` 后才重新接管数据。游戏 Action 对象和 Node 不送入 worker，获胜序列回到主线程后再映射为真实 Action。

主线程准备和结果安装也占预算。排序、深复制、单次扩展和自定义回调不能从中间中断，因此 2 ms 是调度目标，不是绝对上限。`frame_budget_ms=0` 停止推进新规划工作，但已运行片段可以结束并被回收，当前动作仍由物理帧执行。

## 如何读取指标

| 指标 | 范围与含义 |
| --- | --- |
| `agent.planning_statistics` | 最近报告；顶层搜索统计对应最后尝试的目标 |
| `request_finished` / `search_complete` | 请求是否结束 / 最后尝试目标的搜索是否完整 |
| `planning_statistics.request` | 同次请求累计所有已尝试目标的计数与耗时 |
| `request.planning_time_ms` | preparation + search + evaluation 的累计计算时间 |
| `request.latency_ms` | 从该请求记录的起点到报告时刻，包含排队和跨帧等待 |
| `request.searched_goals` / `candidate_count` | 已完成目标的累计搜索量；不能用动作定义数替代候选数 |
| `request.max_main_step_ms` | 最大不可分割主线程步骤 |
| `request.max_cost_callback_ms` | 最大单次成本回调耗时 |
| `scheduler.statistics.frame_time_ms` | 该渲染帧调度主线程耗时，不包含其他游戏工作或 worker CPU 时间 |
| `overrun_ms` / `max_slice_ms` | 相对共享预算的超额 / 最大实际 Agent 时间片 |
| `queued_agents` / `active_workers` | 当前待处理 Agent 数 / 尚未回收的任务数 |
| `plan.search_complete` | 选中目标搜索是否完整，不能解释为任意动态领域全局最优 |

等待 worker 且没有新进展时报告不一定逐帧刷新；中间进度是采样值。调度时间与计算阶段时间有重叠，不能直接相加当成整帧开销。示例的 Workload 页单独统计合成请求。

## 性能调优顺序

1. 先观察实际候选数、展开节点和 `search_complete`，确认是否因替代动作组合而产生大量路径。链长和分支数往往比 Agent 个数更重要。
2. preparation 较高时检查动作数量、快照大小和采集回调；缓存游戏查询或缩小上下文，不要把整个游戏状态复制进去。
3. evaluation 较高时缩短成本回调。后台执行不消除计算，也不能使不返回的回调自动超时。
4. compute 较低但 latency 较高时检查队列、帧率、worker 并发和片段大小。增加吞吐可能增加主线程峰值或 CPU 竞争，需要在目标机器测量。
5. 反复取消时检查事实抖动和无条件 `request_replan()`。纯数值变化是否真的需要重新规划由游戏决定。

目前没有请求截止时间或最大响应时间保证，也不会在某个目标尚未结束时直接跳到低 Priority 目标。10000 节点上限限制展开数，不是内存或耗时的严格上限；调试 trace 还会记录剪枝节点。保留的回归命令见[验证](TESTING.md)。
