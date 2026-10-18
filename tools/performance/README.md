# 可选性能统计与复现

吸收社区 PR #1 的分阶段测量思路，沿用当前异步文件基础设施。
默认关闭；不会为普通玩家创建报告线程、逐帧监听或性能文件。
现有战斗诊断日志的开关保持独立。

## 在游戏中开启

PowerShell 示例（启动方式仍使用本机 Godot 路径）：

```powershell
$env:STARHOME_PERFORMANCE = '1'
$env:STARHOME_PERFORMANCE_SCENARIO = 'manual-moving-fire'
& 'C:/path/to/Godot.exe' --path .
Remove-Item Env:STARHOME_PERFORMANCE
Remove-Item Env:STARHOME_PERFORMANCE_SCENARIO
```

可用 `STARHOME_PERFORMANCE_OUTPUT` 指定报告文件，默认保存到
`user://diagnostics/performance_<时间>_<进程>.json`。每30秒提交最新报告，正常退出排空队列；
强杀可能丢失最后一段统计。报告只包含数值及启动元数据，不记录账号、背包、提示词或密钥。

每项耗时保留最近2048个样本，分别计算P50/P95/P99；次数、均值和最大值覆盖本轮全部样本。
耗时、计数和瞬时值各限制128个固定名称。分位排序、JSON编码及原子写盘均在低优先级线程完成。
报告中的时间单位是微秒。不同指标可能嵌套，不能将其直接相加。

主要指标：`server_frame`、`map_simulation`、`monster_pathfinding`、`snapshot_build`、
`snapshot_publish`、`player_command`、`player_projection`、`player_to_domain`、`player_to_record`、
`mining_settlement`、`equipment_settlement`、`skill_settlement`、`save_capture`、
`save_snapshot_encode`、`file_json_encode`、`background_file_write`、`resource_texture_load`。
启用图形客户端时另记录实际绘制和物理帧间隔。

## 隔离基准

```powershell
python tools/performance/run_baseline.py --godot 'C:/path/to/Godot.exe' --output 'C:/benchmark-results'
```

启动器按顺序运行站立、移动、开火、采矿、补怪五个场景，每个进程都有独立的
APPDATA/LOCALAPPDATA/XDG目录与存档。驱动拒绝直接在未隔离的日常环境启动。
输出包含日志、报告、Git版本和运行结果；任何脚本错误、动作未发生或报告缺失都算失败。
可用 `--scenarios moving mining` 选择子集。报告和隔离存档留在输出目录供排查，不提交到仓库。

统一条件是D04、单角色、当前目录完整种群（当前208只）、新兵装备、20Hz模拟，
预热100步再采样400步。采矿场景通过正式事务安装采掘臂；补怪场景移除120只普通怪，
触发一次正式配额补充。基准夹具每步恢复玩家血量，开火场景补能并提高目标血量，
以免早死或断能使后半段变成空载。所有改动只存在于该基准进程。

这是权威逻辑CPU基准，不含GPU渲染和真实网络，不代表客户端FPS。
对比应使用同一机器、引擎、地图目录、装备和驱动，连续运行多次；同时查看动作数量、移动距离、
实际采出数量和怪物数量。种群或平衡配置不同的结果不能直接宣称是性能提升。

回归入口：`tests/core/performance_telemetry_test.gd` 验证关闭、容量、线程、百分位、提前返回计时和落盘；
现有异步存档/文件线程测试继续覆盖保存语义。
