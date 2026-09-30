# Godot GOAP

[English](README.md) | 简体中文 | [完整文档](docs/README.md)

基于布尔事实的 GOAP（目标导向行动规划）框架，使用强类型 GDScript 编写。游戏定义目标、动作和成本，框架负责目标选择、计划搜索、分片调度与动作生命周期。

Core 与示例统一面向 **Godot 4.7**，当前验证使用 **4.7.2**。不维护 Godot 4.4–4.6 或旧 API 的兼容层，无需原生扩展。

## 快速开始

体验示例：导入本仓库 `project.godot`，启用 GOAP 插件，按 **F5**。默认 6 个 Agent 自动采集、烹饪、进食和防御。编辑器顶部 **GOAP** 提供定义搜索、动作与成本脚本跳转、可交互的假设预览，以及 **Runtime** 中的目标决策、成本比较、事件时间线和通用性能指标。底部 **Goap** 保留工作区入口；示例游戏左侧显示地图，右侧固定显示 Agent、Workload 标签页。Agent 页显示当前 Goal 和计划的所有步骤。

接入游戏：复制 `addons/goap/`，在角色下添加继承 `GoapAgent` 的 Node，将 `goap_script_folder` 指向包含 `actions/` 和 `goals/` 的目录。编辑器插件不会自动添加运行时单例；需要远程观察时，由游戏在项目自动加载中显式添加 `GoapInspector`。本仓库示例已选择加载。完整可运行代码见[接入指南](docs/USAGE.md)。角色能力、感知、寻路和资源使用规则由游戏实现。

查看性能：启用插件，按 **F5 / F6** 运行，进入编辑器 **GOAP → Runtime → Performance**，也可从底部 **Debugger → GOAP** 打开。这里显示全会话调度和规划统计，支持 **Reset samples**；不需要游戏 HUD，也不需要选中 Agent。

## 文档

| 想了解什么 | 文档 |
| --- | --- |
| 如何安装、编写角色和注册动作 | [接入与基础使用](docs/USAGE.md) |
| 框架如何设计、选择目标、搜索和执行 | [设计与执行流程](docs/DESIGN.md) |
| 如何计算距离等动态成本 | [成本模型与独立规划器](docs/COSTS.md) |
| 后台线程、预算、重规划与性能指标 | [调度与性能](docs/SCHEDULING.md) |
| 如何发现 Agent、预览和调试真实运行 | [发现机制与运行调试](docs/DEBUGGING.md) |
| 演示操作与代码入口 | [生存示例](goap_example/README.md) |
| 如何验证与导出 | [验证与发布](docs/TESTING.md) |

启用 GOAP 编辑器插件时，二进制导出会为成本模型及其基类保留源码，其余脚本遵循 preset；禁用插件时使用 Text 脚本导出。保留的回归与导出检查见[验证指南](docs/TESTING.md)。

实现位于 `addons/goap/core/`；编辑器与运行时 UI 位于插件其他子目录；`goap_example/` 为独立游戏层；`tests/` 为回归与基准。许可证见 [LICENSE](LICENSE)。
