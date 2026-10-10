# 阶段 0 性能基线工具

本目录只负责阶段 0 的观测和基线编排，不修改玩法规则。运行时遥测默认关闭；只有设置
`STARHOME_PERFORMANCE=1` 时才采样，并把结果写入 `.godot/performance/`。

## 生成清单

```bash
python3 tools/performance/collect_inventory.py
```

这会生成当前测试清单和运行资源/`.godot` 缓存大小清单。清单区分默认门禁条目、未注册条目、
静态失效引用候选、重复文件名和阶段 0 场景缺口；它不把历史日志或未执行的门禁称为通过。

## 场景矩阵

```bash
python3 tools/performance/run_baseline.py --scenario standing --mode inprocess
python3 tools/performance/run_baseline.py --scenario standing --mode dedicated --headless \
  --scene scenes/server/dedicated_server.tscn
python3 tools/performance/run_baseline.py --scenario standing --mode inprocess --headless \
  --script tools/performance/d04_server_baseline_driver.gd
```

`--scenario` 支持 `standing`、`moving`、`firing`、`mining`、`spawning`、`replacement`、`offscreen`
和 `autosave_due`，
默认预热 10 秒、采样 40 秒。`--extra-arg` 用于传给场景的现有命令行参数。工具只负责统一
计时窗口、环境元数据、日志路径和结果文件名；在没有真正把 D04、200 怪物和 4 个角色装配到
场景的情况下，结果不能宣称满足该固定配置。客户端表现驱动
`d04_client_presentation_driver.gd` 使用真实 D04 权威服务器快照、4 个战车表现和真实怪物资源；
`replacement` 每个快照替换 10 个表现实体，`offscreen` 将本地摄像机移出怪物区域，`spawning`
周期性替换 10 个刷怪实体。它仍然是独立测量夹具，不改变正式游戏运行逻辑。
前台 `foreground_combat_hitch_driver.gd` 的 `moving` 场景会让战车在两个可达点间往返，并以
`FOREGROUND_MOVE` 日志及 `foreground_vehicle_max_displacement` 指标确认实际发生位移。

## 记录内容

运行时遥测记录渲染帧间隔、物理帧间隔、服务端 tick、世界模拟、领域结算、快照构建/冻结/发布、
网络快照派发、客户端世界/战斗快照应用、资源上传、自动存档捕获/转换和 JSON 编码。
每个指标输出 P50、P95、P99、最大值、均值和样本数；只保留预热后的采样窗口。
