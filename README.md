# GOAP for Godot

English | [简体中文](README_cn.md) | [Documentation index](docs/README.md)

A Boolean-fact GOAP framework written in typed GDScript. Your game defines goals, actions, and costs; the framework selects goals, searches plans, schedules planning work, and manages action lifecycles.

The core and example target **Godot 4.7**, validated with **4.7.2**. Godot 4.4–4.6 and legacy APIs are unsupported. No native extensions are required.

## Quick start

Import `project.godot`, enable the GOAP plugin, and press **F5**. Six agents demonstrate gathering, cooking, feeding, and defense. The editor's top **GOAP** workspace provides searchable definitions, GDScript and cost-model navigation, interactive what-if previews, and a **Runtime** inspector with actual goal decisions, cost comparisons, and an event timeline. The bottom **Goap** panel links to this workspace. The example splits the game between the map on the left and Agent and Workload tabs on the right; the Agent tab shows the current goal and every plan step.

To integrate, copy `addons/goap/`, add a Node extending `GoapAgent` below your actor, and set `goap_script_folder` to the directory containing `actions/` and `goals/`. The editor plugin does not add a runtime autoload; opt in to `GoapInspector` in Project Settings → Autoload only when your game needs remote inspection. This repository's example opts in explicitly. See the [complete integration example](docs/USAGE.md). Movement, sensing, abilities, and resource allocation belong to your game.

For performance, enable the plugin, run with **F5 / F6**, then open the editor's **GOAP → Runtime → Performance** (also available under **Debugger → GOAP**). It shows session-wide scheduler and planning metrics with **Reset samples**, without a game HUD or an observed Agent.

## Documentation

The maintained detailed guides are in Chinese under `docs/`; API identifiers and runnable code retain their original names.

| Topic | Guide |
| --- | --- |
| Installation, minimal actor, directory and code registration | [Usage](docs/USAGE.md) |
| Architecture, ownership, search, evaluation, execution | [Design](docs/DESIGN.md) |
| Snapshot costs and standalone planning | [Cost models](docs/COSTS.md) |
| Workers, shared budgets, cancellation, metrics | [Scheduling](docs/SCHEDULING.md) |
| Agent discovery, preview, live inspection, debugger transport | [Debugging](docs/DEBUGGING.md) |
| Survival example and controls | [Example](goap_example/README.md) |
| Regression tests, visual checks, exports | [Testing and release](docs/TESTING.md) |

With the GOAP editor plugin enabled, binary export preserves readable source for cost-model scripts and their base classes; other scripts follow the preset. With the plugin disabled, use Text script export. See [verification](docs/TESTING.md) for the maintained checks.

Core lives in `addons/goap/core/`; other addon directories provide optional editor/runtime UI. `goap_example/` contains game-specific behavior, and `tests/` contains regressions and benchmarks. See [LICENSE](LICENSE).
