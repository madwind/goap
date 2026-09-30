# 验证

从仓库根目录运行，使用 Godot 4.7。CI 入口在 Windows PowerShell 中执行导入与核心回归：

```powershell
./tests/run_ci.ps1 -Godot 'C:/path/to/godot_console.exe'
```

保留的脚本覆盖规划器、世界状态 Provider、生命周期重入、预算调度、安全成本模型、诊断数据、运行监控与生存示例冒烟。单独运行时使用：

```powershell
godot --headless --path . --script tests/run_tests.gd
godot --headless --path . --fixed-fps 60 --script tests/example_smoke.gd
```

发布前可在 Windows 上另行验证 Text 和 Binary 导出。安装匹配的 Godot release template 后运行：

```powershell
./tests/run_export_tests.ps1 -Godot 'C:/path/to/godot_console.exe' -ReleaseTemplate 'C:/path/to/windows_release_x86_64.exe'
```

启用 GOAP 编辑器插件时，Binary preset 会为成本模型及其基类保留可审计源码；禁用插件时使用 Text 导出。目标平台的性能和长时间稳定性需要在实际项目中测量。
