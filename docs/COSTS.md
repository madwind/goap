# 成本模型与独立规划器

[文档首页](README.md)

基础 Action 的 `cost` 默认是 1。动作脚本可重写 `_get_cost()` 声明成本，也可在创建实例后设置 `action.cost`；每次规划请求会读取当前值。`GoapAction` 本身没有成本模型和 Context 钩子。需要自定义计算的游戏适配器可选择提供 `get_cost_model()` 和 `capture_context()`；没有提供时使用 Action 的 `cost`。模型返回的是本步完整成本；Core 不区分它代表移动、风险还是其他游戏规则。Goal Priority 与成本分工见[设计](DESIGN.md)。

```gdscript
func _get_cost() -> float:
	return 2.0
```

## 示例：局部资源选择与动态成本

未提供自定义模型时，每个动作使用自己的固定 `cost`，默认 **1**。生存示例不模拟整条路线的位置或路程。Harvest 根据资源的最大血量设置基础成本，PickUp 使用默认基础成本 1：

```gdscript
func configure(resource: Node3D) -> void:
	cost = float(resource.max_health())
```

资源观察层按资源身份保留最近的可用 Provider；同类资源都不可用时，保留最近的不可用 Provider 来发布 false 事实。地上已有物品时，即使可采集来源更近，拾取事实仍会进入规划；[agent.gd](../goap_example/agent/goap/agent.gd) 不再根据来源距离隐藏掉落物。示例的固定动作成本不包含路程：PickUp 成本为 1，Harvest 成本由资源最大血量决定。

示例成本数据为：

| 数据 | 示例入口 | 内容 |
| --- | --- | --- |
| 初始 Simulation | [agent.gd](../goap_example/agent/goap/agent.gd) 的 `_capture_cost_state()` | 是否极度饥饿、是否低血量 |
| 固定成本 | Harvest / PickUp 等动作的 `cost` | 采集工作量或默认成本 |
| 自定义模型 | [raw_meat_cost.gd](../goap_example/agent/goap/costs/raw_meat_cost.gd) | 生吃肉在紧急状态下降低成本 |

采集和拾取开始执行时，由 [agent.gd](../goap_example/agent/agent.gd) 的 `find_matching_resource()` 在符合条件的资源中重新选择最近目标，赶路途中定期复查。规划器不保存资源目标；其他 Agent 抢占资源或资源移动后，会重新观察和规划。路线总成本和步数相同时，规划器按动作 ID 序列稳定决胜，不查询目标距离。

搜索只评估它枚举出的因果链。地上已有目标物品时，“物品可拾取”要求在当前世界中已满足，反向搜索会在这里收束；空闲 Agent 因而可以直接规划 PickUp。若 Agent 正在执行动作，示例的重规划规则可能让它继续当前目标：仅新增的掉落物比当前目标更远时，不会为此立即重规划。

`EatRawMeat` 单独返回 [raw_meat_cost.gd](../goap_example/agent/goap/costs/raw_meat_cost.gd)：

```gdscript
extends GoapCostModel

static func get_cost(simulation: Dictionary, _context: Dictionary) -> float:
	return 0.2 if simulation.get(&"starving", false) or simulation.get(&"low_health", false) else 35.0
```

这让普通状态倾向熟食，极饿或低血量时倾向立即生吃；是否允许烹饪仍由动作前提中的 `starving=false` 控制。对应代码位于 `goap_example/agent/goap/costs/`。

这些快照只表示请求时的估计，不预留目标，也不传递 Node 引用。实际执行时能力重新取得或验证目标；自定义模型需要更多信息时，扩展 Context 或初始 Simulation 的纯数据字段。

| 数据或回调 | 运行位置与职责 |
| --- | --- |
| Goal Priority、可用性、`capture_context(agent)` | 主线程，可读取游戏对象 |
| Agent 的 `_capture_cost_state()` | 主线程，返回复制出来的初始模拟数值 |
| `get_cost(simulation, context)` | 默认工作线程，只读取传入数据 |
| `apply_cost_effect(simulation, context)` | 默认工作线程，更新该候选的私有模拟状态 |
| `start/perform/stop` | 运行时主线程，执行真正的游戏行为 |

每次规划请求对每个可用 Action 采集一次 Context。Context 内的普通字典和数组递归设为只读。每条候选拥有独立的可变 Simulation；生存示例只用饥饿与低血量标记计算生吃肉的成本。成本必须确定、有限且非负。

不要将 Node、Resource、Object、Callable、Signal 或 RID 放进快照。使用数值、向量、字符串、数组、字典等纯数据。成本脚本必须继承 `GoapCostModel`，避免读取场景、自动加载单例、可变全局状态或动态加载代码。同步运行同一模型时也必须遵守这些约束。

Core 会检查模型源码并验证快照。发现问题时产生 `unsafe_cost_model`、`invalid_input` 等诊断；非法成本会使候选被拒绝。这是尽力而为的检查，不是沙箱，也不能证明任意间接调用都线程安全。模型应尽量自包含，导出时保留可读取的脚本源码。工具若在进程内修改自动加载配置，可调用 `GoapPlanningSafety.clear_audit_cache()`。

启用 GOAP 编辑器插件时可选择 **Binary**（`script_export_mode=2`）：导出钩子会将继承 `GoapCostModel` 的独立脚本及中间基类保留为文本，其余脚本正常编译。Text 和 Binary PCK 均已通过隔离运行验证，危险模型仍会被拒绝。这是混合导出，成本模型源码仍随包分发；内嵌类应拆成独立模型脚本。禁用插件时选择 **Text**（`script_export_mode=0`）。不要通过删除运行时审计来支持完全无源码的成本模型。

## 成本与缓存

Core 对每条候选逐步计算并累计模型返回的完整成本，同时让模型更新该候选私有的 Simulation。它不需要把游戏成本分类为固定或动态。没有自定义模型时，使用本次请求捕获的 Action `cost`。

前置条件、效果与 Effect 索引可跨请求缓存；Action `cost`、Context 和初始 Simulation 每次请求重新采集。改变成本输入而世界事实未变化时，应显式调用 `request_replan()`。调度和缓存流程见[调度文档](SCHEDULING.md#预构建与缓存)。

## 脱离场景单独使用规划器

工具和测试可直接调用阻塞式规划器：

```gdscript
var gather := GoapAction.new()
gather.name = &"GatherWood"
gather.effects = GoapWorldState.new({&"has_wood": true})

var fire := GoapAction.new()
fire.name = &"MakeFire"
fire.preconditions = GoapWorldState.new({&"has_wood": true})
fire.effects = GoapWorldState.new({&"has_fire": true})

var planner := GoapPlanner.new([fire, gather])
var plan := planner.find_plan(
    GoapWorldState.new(),
    GoapWorldState.new({&"has_fire": true}),
)
if plan != null:
    print(plan.actions, plan.cost, plan.search_complete)
else:
    print(planner.statistics)
```

结果是 `GatherWood → MakeFire`，成本为 2。这个调用只生成计划，不执行游戏行为。接口为：

```gdscript
# Signature reference; cost_contexts is keyed by action.get_id().
find_plan(world, desired, cost_state = {}, cost_contexts = {}) -> GoapPlan
```

需要动态成本的动作仍可显式提供 Simulation 和 Context。示例的 `EatRawMeat` 只读取初始状态：

```gdscript
# Given a planner containing EatRawMeat and raw_meat_cost.gd:
var plan := planner.find_plan(world, desired, {&"starving": true})
```

没有显式 Context 时，采集回调收到的 Agent 为 `null`。使用这个入口的 Action 必须处理该情况，或要求调用方提供 Context。独立规划器使用传入的动作集合，不会替调用方执行运行时的 `is_valid(agent)` 筛选。

目标已经满足时返回空计划；不可达时返回 `null`。成本相同时优先动作更少的计划，再按动作 ID 序列的字典序决胜。动作 ID 必须稳定；参数化动作需要不同 ID。

`search_snapshot()` / `search_prepared()` 是只做结构搜索的工具入口，不做动态成本评估；编辑器预览使用这一层。常规业务若要选出计划应使用 `find_plan()` 或 Agent，不要把结构候选列表直接解释为最优执行方案。

完整调用时序见[设计](DESIGN.md)，成本回调耗时及线程预算见[调度](SCHEDULING.md)，发布方式见[验证与发布](TESTING.md)。
