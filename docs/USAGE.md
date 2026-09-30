# 接入与基础使用

[文档首页](README.md)

这篇以仓库内可运行的 goap_example 为主线，说明如何接入自己的角色。内部算法见[设计](DESIGN.md)，查看计划和排错见[调试](DEBUGGING.md)。

## 安装与运行

**体验本仓库：** 在 Godot 中导入 `project.godot`，按 **F5**。场景入口见[生存示例](../goap_example/README.md)。

**接入自己的游戏：**

1. 将 `addons/goap/` 复制到项目的 `addons/` 目录，保留 `res://addons/goap/` 路径。
2. 等待 Godot 导入脚本并注册全局类。
3. 如需编辑器预览，在 **项目 → 项目设置 → 插件** 中启用 **GOAP**。插件会添加顶部 **GOAP** 工作区、底部 **Goap** 入口及调试会话页面；不会自动给游戏添加运行时单例。
4. 在角色下添加一个 `Node` 子节点，挂上继承 `GoapAgent` 的脚本。将它的 **Goap Script Folder** 设置为该角色 `actions/` 和 `goals/` 所在的上级目录。动作、目标与成本模型通过 GDScript 定义；使用 **GOAP → Definitions / Preview / Runtime** 浏览定义、预览依赖和观察实际规划。
5. 实现角色的游戏行为，同步观测事实，然后运行场景。

编辑器插件和运行时检查器分别可选。需要在编辑器 Runtime 页观察游戏时，由游戏在 **项目 → 项目设置 → 自动加载** 中显式添加 `res://addons/goap/debugger/goap_debugger_autoload.gd`，名称设为 `GoapInspector`。本仓库的示例项目已显式添加，因此按 F5 可以直接观察。发布项目若不需要检查器，应从自动加载列表移除它，并移除显式实例化的 Runtime monitor；仅禁用编辑器插件或隐藏窗口不会移除游戏里的检查器。`addons/goap/core/` 不依赖该单例。

```text
addons/goap/
  core/             规划器、事实、目标、动作与调度
  visual_editor/    编辑器预览与依赖图布局
  debugger/         运行时检查器与编辑器调试通信
  runtime/          通用监控窗口、可扩展标签页与性能统计
  ui/               共用计划浏览器与图控件
goap_example/       游戏层的生存演示
tests/              回归测试、视觉检查与基准
```

查看通用性能：启用插件、由游戏显式加载 `GoapInspector` 并按 F5 / F6，进入编辑器顶部 **GOAP → Runtime → Performance**，或底部 **Debugger → GOAP → Performance**。无需选中 Agent，也无需在游戏里创建监控 UI。这里按调试会话统计所有 Agent；Reset samples 仅清空统计。

在 Runtime 的个体观察页从 Agent 列表选择观察对象，并用 **Show marker in game** 对应列表编号与场景角色。标记与观察方式见[角色对应与选择](DEBUGGING.md#将观察对象与游戏角色对应)。

可选的独立 Runtime monitor 也位于 `addons/goap`，提供 Performance / GOAP 页面和标签拖动、拆窗、停靠。普通图形项目可使用自动加载窗口；也可以直接实例化 `addons/goap/runtime/goap_runtime_monitor.tscn`，无需启用编辑器插件。游戏页面扩展见[运行监控](DEBUGGING.md#显示方式与接入自己的-ui)。

## 快速接入：直接运行 goap_example

入门使用仓库中已有的 [world.tscn](../goap_example/world.tscn)，代码、场景和运行结果可以逐一对照。示例的源码入口见[生存示例说明](../goap_example/README.md)。

1. 用 Godot 4.7 打开根目录项目，打开 `goap_example/world.tscn`。
2. 为便于跟踪一个角色，在 World 的 Inspector 中把 **Agent Count** 设为 `1`、**Random Resources** 关闭，再按 **F6**。这会使用固定教学布局；默认的 12 人随机场景也可以直接运行。
3. 点击橙色角色，在右侧 **Agent** 页查看当前目标、完整计划步骤、动作和库存；事件时间线可在编辑器 **GOAP → Runtime** 查看。
4. 按 **H** 再次触发饥饿，按 **J** 触发极饿，比较熟食与生肉路线；等待怪物进入警戒范围，观察防御和低血量撤离。实际路线取决于当前库存、可用资源和距离。
5. 停止游戏，进入顶部 **GOAP → Preview**，选择 Agent 和 `SatisfyHunger`，在 World state 中勾选或取消事实（True / False），未提供的事实默认为 False，并查看候选结构。选中方案步骤后，也可以直接在 Details 的条件旁切换初始世界状态，无需切换页签。Reload 可重置假设；Definitions 可查定义、事实引用和新建脚本。预览中的事实不会修改实际角色；详细操作与运行时观察的区别见[调试文档](DEBUGGING.md)。

在 **GOAP → Definitions** 选择 Action，点击 Preconditions 或 Effects 下的 **Edit...**。外面只展示当前状态；弹窗用表格列出已有 World state 事实，已定义的事实会预先勾选 **Include**。未包含的事实值默认为 False，值复选框不可操作；勾选 Include 后可用第二个复选框设置 True / False。可搜索、切换 **Included only** 只看已包含的事实；确认后一次写回该 Action 的 `.gd` 文件并刷新定义。当前图形编辑只支持单行 `return GoapWorldState.new({ ... })` 或 `return GoapWorldState.new()`，键可以是字符串或脚本中的事实常量；含分支、计算或初始化后另行修改的状态请在 GDScript 中编辑。编辑器会保留其他方法，并在磁盘脚本发生变化时拒绝覆盖，提示先保存并 Reload。

没有自定义模型的 Action 可在 Definitions 中直接修改 **Action cost** 并点击 **Save cost**。编辑器会更新脚本里的字面量 `_get_cost()`；没有该方法且仍使用默认成本 1 的动作会自动补上。**Attach existing...** 可选择项目内已有的 `GoapCostModel` 脚本；**Add new** 在 Agent 的 `costs/` 目录创建并绑定同名成本脚本。有模型的动作显示 **Open cost script** 与 **Detach**，其完整成本由模型决定。Detach 只修改动作脚本，不删除可能被其他动作共用的模型文件。

Definitions 中的 **Add Action** 和 **Add Goal** 弹窗只需填写脚本文件名。生成的 Action 默认 `cost` 为 1、事实为空且暂不可用；Goal 的目标事实为空、Priority 为 0。创建后会打开脚本，按需填写前提、效果、目标和行为。

### 场景如何绑定 Agent

[agent.tscn](../goap_example/agent/agent.tscn) 已完成如下配置：

```text
World（world.gd，提供资源查找、篝火和怪物威胁判断）
└── Agent（CharacterBody3D，agent/agent.gd）
    ├── GoapAgent（Node，agent/goap/agent.gd）
    │   Goap Script Folder = res://goap_example/agent/goap
    └── Body / Caption / AlertRing / CollisionShape3D / DeathMarker
```

`GoapAgent.actor` 指向父节点 Agent。Agent 从该目录加载固定 Action 和 Goal，并根据资源的掉落配置生成 Harvest 和 PickUp 候选；角色负责移动、库存和能力执行。Harvest 只产生地面掉落物，PickUp 才把物品放进角色背包。示例角色调用父 World 的资源索引、`nearest()`、`nearest_monster()` 等接口，因此应运行 `world.tscn`；单独对 `agent.tscn` 按 F6 不具备完整的游戏环境。

### 从真实脚本读懂接入点

| 阅读顺序 | 示例文件 | 要实现的职责 |
| --- | --- | --- |
| 1 | [agent.gd](../goap_example/agent/agent.gd) | 保存饱食度和库存；公开 `cook_meat()` 等能力，并在物理帧推进执行对象 |
| 2 | [agent.gd](../goap_example/agent/goap/agent.gd)、[资源 Provider](../goap_example/resources/resource_state_provider.gd)、[角色 Provider](../goap_example/agent/goap/actor_state_provider.gd) | Agent 发现 Provider，所有运行时观测统一由 `get_world_state(agent)` 提供 |
| 3 | [goals/feed.gd](../goap_example/agent/goap/goals/feed.gd) | 将 `hungry=false` 定义为目标；普通饥饿 Priority 为 40，极饿为 200 |
| 4 | [actions/cook_meat.gd](../goap_example/agent/goap/actions/cook_meat.gd) | 声明原料、火和非极饿前提，声明熟肉效果，启动角色能力 |
| 5 | [ability_action.gd](../goap_example/agent/goap/ability_action.gd) | 把能力执行状态转换成 GOAP Status，在 `stop()` 中取消并释放执行引用 |
| 6 | [abilities/cooking.gd](../goap_example/agent/abilities/cooking.gd) | 检查真实原料与火，交互完成后才消耗生肉并产生熟肉 |

例如，下面摘自真实的 `actions/cook_meat.gd`；距离成本相关方法见源文件：

```gdscript
extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")

func start(agent: GoapAgent) -> void:
    execution = agent.actor.cook_meat()

func _get_name() -> StringName:
    return &"CookMeat"

func _get_preconditions() -> GoapWorldState:
    return GoapWorldState.new({ Facts.HAS_RAW_MEAT: true, Facts.HAS_FIRE: true, Facts.STARVING: false })

func _get_effects() -> GoapWorldState:
    return GoapWorldState.new({ Facts.HAS_COOKED_MEAT: true, Facts.HAS_RAW_MEAT: false })
```

示例把固定事实键集中在 [fact_keys.gd](../goap_example/survival/fact_keys.gd)。Provider、Action 和 Goal 引用同一常量；常量名拼错会在脚本解析时暴露。物品和资源产生的参数化事实键通过 `Facts.inventory()`、`Facts.available()`、`Facts.harvest_available()` 等函数生成，避免在多处重复拼字符串。新项目可定义自己的事实键表；`GoapWorldState` 仍接受 `StringName`，因此直接手写字符串时仍需自行检查。`_get_name()` 是动作的显示名称及默认 ID，与事实键不同；需要按 ID 引用动作时，也应把 ID 集中定义。

这些 effects 是规划及成功后的事实更新。真正扣掉生肉、产生熟肉的代码在角色能力中；Action 不直接代替能力修改库存。对应实现位于 `goap_example/agent/abilities/` 与 `goap_example/agent/goap/actions/`。

### 目录加载约定

目录加载器按文件名排序，实例化 `actions/` 和 `goals/` **直属目录**中的 `.gd` 文件，不递归加载子目录。共用适配器和成本脚本应放在这两个目录以外。构造函数不能要求必须传入参数。每个 Agent 应拥有独立的 Action 实例，因为 Action 可能保存执行状态。

Agent 首次初始化时创建空的状态容器，再加载动作和目标；运行时通过 `GoapWorldStateProvider` 取得当前事实。重新初始化规划器不会重置已有运行状态。无需维护独立的状态初值脚本。

目录名必须是 `actions` 和 `goals`，但父目录不必叫 `ai` 或 `goap`。文件名不决定动作 ID，ID 默认来自 `_get_name()` 返回的 name。Action 与 Goal 各自在 Agent 内保持 ID 唯一；参数化动作可重写 `get_id()`。

加载器通过 `ResourceLoader.list_directory()` 找到 `.gd`，再 `load(path).new()`，最后检查对象类型。它不是源代码分析器，也不是文件变化监听器。不要将抽象基类、有必填构造参数或无关脚本放入扫描目录；当前加载器不提供完善的逐文件错误恢复。

## 世界状态来源接口：Provider → Agent → 快照

`GoapWorldState` 是纯布尔数据，供前提、效果、目标和规划快照使用。[GoapWorldStateProvider](../addons/goap/core/goap_world_state_provider.gd) 是场景对象上的抽象 Node，要求实现 `get_world_state(agent)`。动物、树木属于游戏层；可狩猎、可砍伐通过带观察者参数的方法查询，可以检查存活和工具等条件。

例如，动物的 Provider 子节点：

```gdscript
extends GoapWorldStateProvider

func get_world_state(agent: GoapAgent) -> GoapWorldState:
    return GoapWorldState.new({
        &"huntable": get_parent().is_huntable(agent.actor),
    })
```

Provider 脚本必须挂在场景节点上才生效，文件目录不参与扫描。基类在进入场景树时注册到 Godot Group，离树时注销；`discover(scene_root, agent)` 从该索引取得指定场景子树中的 WORLD Provider，加上当前角色自己的 ACTOR Provider。嵌套场景、动态添加的普通节点都能被发现，无需资源类型或资源列表。

Provider 子类如果重写 `_enter_tree()` 或 `_exit_tree()`，需要调用父类方法以保留注册和注销逻辑。

Agent 决定发现范围。下面使用场景范围发现，也可改用 Area3D、视野传感器或自己的空间索引：

```gdscript
extends GoapAgent

func _observe_world_state() -> GoapWorldState:
    var providers := GoapWorldStateProvider.discover(actor.get_parent(), self)
    return GoapWorldStateProvider.collect(providers, self)
```

- Provider 在主线程只读查询游戏状态，不预订目标、不执行能力，也不把 Node 交给规划线程。
- WORLD Provider 的同名事实取 **OR**，表示“至少一个已发现对象满足条件”。ACTOR Provider 挂在角色下，设置 `scope = Scope.ACTOR`，也通过 `get_world_state(agent)` 提供自身饥饿、库存等状态；仅自己的 Agent 能读取，其事实覆盖同名世界事实，包括 false。多个自身 Provider 应各自负责不同的事实键；重复键按返回顺序后者覆盖。Agent 不再拼接游戏事实。
- `_observe_world_state()` 返回**完整当前认知**。Core 每个物理帧先处理动作完成，再调用 `refresh_world_state()` 原子替换事实；消失的键视为 false，布尔值变化才触发重规划。游戏事件也可主动刷新。
- 返回空 `GoapWorldState` 会清空观测；默认返回 `null` 保留手动更新方式。暂停时不自动观测，显式刷新仍可使用。编辑器独立预览不调用观测接口。
- 传感器只返回当前发现的 Provider。缓存中已销毁、离树或等待删除的对象会被跳过。如果需要记住离开视野的对象，由 Agent 自己维护记忆并纳入完整状态。
- 动作选目标和执行验证应遵守同一发现范围。示例的 `find_observed_resource()` 和能力候选过滤器共用发现结果，能力每次执行仍检查目标是否可用。

生存示例按对象归属放置状态适配器：树、动物和掉落物挂载 [资源 Provider](../goap_example/resources/resource_state_provider.gd)，调用 `can_harvest(actor)`，分派到 `is_huntable(actor)`、`is_choppable(actor)`；角色挂载 [角色 Provider](../goap_example/agent/goap/actor_state_provider.gd)，提供自身状态，库存直接读取角色数据，不依赖是否已发现对应的拾取动作。Agent 用通用 Group 索引发现全场景 Provider，统一调用 `get_world_state(agent)` 汇总成快照；资源类型判断仅用于生成采集动作，不限制其他类型的状态来源。首次规划前先收集 Provider，编辑器预览则从角色脚本默认属性和资源场景配置建立假设。动作前提、预测效果和目标仍是规划数据，不需要伪装成场景观测。

迁移旧版初值时，按事实的拥有者移动查询：`hungry`、背包等角色属性放入 ACTOR Provider；动物可狩猎、地面物品可拾取等场景能力放入 WORLD Provider。Provider 返回当前布尔值，Agent 会在首次规划前自动观测一次。Action 的前提和效果、Goal 的目标继续保留，它们描述规划关系，不是状态初值。编辑器预览可从场景默认配置建立假设，运行时以 Provider 的观测为准。

## 不扫描目录：通过代码注册

将 `goap_script_folder` 留空，在进入树之前填充数组。下面的脚本可直接挂到角色的 Node 子节点，展示注册时机；这些基础 Action 仅改变事实，不执行真实采集行为：

```gdscript
extends GoapAgent

func _enter_tree() -> void:
    actions.clear()
    goals.clear()

    var gather := GoapAction.new()
    gather.name = &"GatherWood"
    gather.effects = GoapWorldState.new({&"has_wood": true})
    actions.append(gather)

    var goal := GoapGoal.new()
    goal.name = "StockWood"
    goal.goal_state = GoapWorldState.new({&"has_wood": true})
    goals.append(goal)

    super._enter_tree()
```

也可以从自有配置工厂实例化继承类后加入数组。非空目录配置会在 `init_goap()` 中清空并重新加载这两个数组，因此不要同时依赖目录和提前填入的定义。运行中调整定义后需显式 `request_replan()`；如果当前动作也受影响，游戏控制器还应先处理正在执行的能力与计划生命周期。

代码注册的 Agent 可以被运行时检查器发现；当前编辑器结构预览要求目录配置，且不会执行这段 `_enter_tree()` 注册流程。没有目录时会提示设置 `goap_script_folder`。

## 配置与扩展入口

| 属性 / 方法 | 默认值或用途 |
| --- | --- |
| `goap_script_folder` | 空；非空时加载直属动作与目标目录 |
| `asynchronous_planning` | true；搜索与成本评估使用 worker |
| `max_planning_nodes` | 10000；每目标搜索展开上限 |
| `debug` | false；是否记录搜索 trace，影响内存与耗时 |
| `_observe_world_state()` | 主线程返回完整观测；默认 null，保留手动更新模式 |
| `refresh_world_state()` | 立即采集并原子发布观测；正常物理处理后自动调用 |
| `_capture_cost_state()` | 主线程采集成本模拟初始状态 |
| `request_replan()` / `is_planning()` | 显式通知输入变化 / 查询是否仍有请求 |
| `suspend()` / `resume()` / `is_suspended` | 停止动作并取消请求 / 恢复并重规划 / 只读暂停状态 |
| `cancel_planning()` | 仅取消待处理计算，保留当前执行 |
| `current_plan` / `planning_trace` | 只读访问当前计划引用 / 最近规划 trace |
| `actor` | Agent 父节点；不是全局角色注册表 |

重写 `_enter_tree()`、`_ready()`、`_physics_process()` 或 `_exit_tree()` 时要保留所需的父类调用，避免跳过初始化、初始规划、观测或清理。Core 在处理动作完成之后采集观测；紧急死亡、取消攻击等规则仍需在游戏能力中即时验证。

以 `_` 开头的请求、调度和计划字段是内部实现。游戏暂停和恢复使用上述公共方法，无需修改 generation 或取消 worker。`advance_planning()` 是调度器的推进接口，通常无需游戏代码直接调用；请同时阅读[调度说明](SCHEDULING.md)。

需要可取消的能力执行对象时，可参考[角色能力](../goap_example/agent/abilities/)及其 [GOAP 适配器](../goap_example/agent/goap/ability_action.gd)。

## 世界状态、目标与动作生命周期

**世界事实只保存布尔值，不是任意类型的黑板。** 坐标、数量和计时保存在游戏状态中，将有关条件映射成 `has_food`、`starving` 等事实；用于成本计算的数值放进规划快照。

```gdscript
var facts := GoapWorldState.new({&"has_food": false})
facts.set_state(&"has_food", true)
facts.merge(GoapWorldState.new({&"hungry": true, &"starving": false}))
print(facts.satisfies(GoapWorldState.new({&"has_food": true}))) # true
```

未提供的世界事实默认为 `false`，可以直接满足值为 `false` 的前提或目标。`get_state(key)` 始终返回布尔值；`set_state()` 仅在布尔值变化时发出 `state_changed`，`merge()` 在任一输入事实变化时统一发出一次。给缺失事实写入 `false` 不会触发重新规划。`to_dictionary()` 和 `duplicate()` 返回副本。

动作和目标定义只约束显式写出的键：省略前提表示没有该要求，省略效果表示不修改该事实。`has_state(key)` 可查询是否显式定义了该键；结构键 `get_key()` 保留显式的 `false`，用于区分“没有约束”和“要求为 false”。

**Goal：** 重写 `_get_name()`、`_get_goal_state()`、`get_priority(state)`，必要时重写 `is_valid(state)`。目标 ID 在 Agent 内必须稳定且唯一。有效、尚未满足且 Priority 为正的本地目标按 Priority 降序尝试，同分按 ID 排序。当前目标的搜索和成本评估无法得到可执行计划时，才尝试下一目标。

目标状态字段为 `goal_state`，当前事实为 `world_state`。从旧版脚本迁移时，将 `_get_desired_state()` 改为 `_get_goal_state()`、`desired_state` 改为 `goal_state`、`get_utility()` 改为 `get_priority()`。这些旧名称不再作为别名保留。

紧急行为的优先级和有效性由游戏定义。生存示例在极饿时将进食 Priority 提升到 200；怪物进入任一 Agent 的警戒范围后，世界广播共享怪物目标，各 Agent 将 Priority 100 的防御目标与进食、饮水和恢复目标比较。极饿进食 200、脱水饮水 210、低血量恢复 250 均优先于防御。攻击能力也立即检查紧急状态，避免等待重新规划期间继续攻击。

**Action：**

| 接口 | 契约 |
| --- | --- |
| `_get_preconditions()` | 前置布尔事实，允许由前面的动作建立 |
| `_get_effects()` | 仅在 `SUCCESS` 后由 Core 应用的事实 |
| `is_valid(agent)` | 运行时可用性，准备规划和执行时都会检查 |
| `start(agent)` | 开始一次执行 |
| `perform(agent, delta)` | 返回 `RUNNING`、`SUCCESS` 或 `FAILURE` |
| `stop(agent)` | 每次 start 后的清理，包括成功、失败和中断 |

不要在 `is_valid()` 中因为当前缺少可由计划建立的前提而排除动作。例如 `Cook` 的原料要求应放进 preconditions，前面的 `Hunt` 可以提供原料。执行过程中仍应检查实际目标和资源是否有效，并在 `stop()` 中取消移动和执行状态。

如果动作已完成，却先同步了“原料已消耗”的观测，GOAP 可能误以为动作前提失效。goap_example 先让动作报告完成，再同步事实。死亡和低血量时停止攻击等即时规则也要在能力或控制器中检查，不能只依赖有调度延迟的重新规划。

`stop()` 应取消未完成的执行。同步切换计划时，Core 会检查计划所有权并阻止旧动作继续提交效果；复杂的用户回调仍应保持职责清晰。

下一步：[动态成本](COSTS.md) · [运行调试](DEBUGGING.md)。
