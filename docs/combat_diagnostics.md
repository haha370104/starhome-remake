# 战斗命中差异诊断

## 目的

客户端允许预测弹体飞行及提前播放爆炸，但命中、伤害和掉落始终由权威服务器决定。因此，
“客户端爆炸但服务端没有扣血”本身不能靠单侧截图定位：必须比较客户端当帧使用的怪物快照
几何，以及服务端收到同一开火意图时使用的权威几何。

调试构建默认把这条链路写成逐行 JSON（JSONL）。发布构建默认关闭，可设置环境变量
`STARHOME_COMBAT_TRACE=1` 临时开启；设置为 `0`、`false` 或 `off` 可显式关闭。

## 文件位置

每次启动、每个进程创建一份独立文件：

```text
user://diagnostics/combat_trace_<启动时间>_<进程ID>.jsonl
```

Windows 编辑器运行通常对应：

```text
C:\Users\<用户名>\AppData\Roaming\Godot\app_userdata\starhome_remake\diagnostics\
```

首次写入时，终端会打印“战斗诊断日志：<绝对路径>”。单机调试模式的客户端和进程内权威
服务器在同一文件中，以 `side` 区分；独立专用服务器与客户端各自产生一份文件。单文件达到
64 MiB 后停止追加，避免异常测试无限占用磁盘。

## 关联一发子弹

每条记录都有时间、进程、`side`、`stage` 和 `fields`。同一发攻击按以下标识串联：

1. `visual_shot_id`：客户端每个视觉弹体的本地唯一标识；
2. `input_sequence`：能力意图的客户端单调序号，跨客户端与服务器稳定；
3. `shot_id`：服务器接受意图后创建的权威弹体标识。

`ability_intent_submitted` 同时记录前两者；`authoritative_projectile_scheduled` 与服务器事件同时
记录后两者。因此即使客户端预测结果与服务端结果相反，也能完整拼回同一发子弹。

关键阶段：

| stage | 含义 |
|---|---|
| `visual_projectile_spawned` | 客户端创建弹体时的角色位置、炮口、方向、射程和速度 |
| `ability_intent_submitted` | 视觉弹体与实际网络意图的关联，以及客户端选中的怪物 |
| `weapon_intent_received` | 服务端收到意图时的权威角色位置和瞄准点 |
| `ability_command_result` | 服务端接受或因冷却、能量、地图、序号等原因拒绝 |
| `authoritative_projectile_scheduled` | 服务端弹道、定靶结果及距离弹道最近的八个怪物碰撞圆 |
| `visual_projectile_collision` | 客户端逐帧扫掠提前碰撞时的线段和怪物快照碰撞圆 |
| `authoritative_projectile_event_recorded` | 服务端最终命中或无伤害失效，以及稳定的失效原因 |
| `authoritative_projectile_event_observed` | 客户端实际收到最终权威事件的时刻 |

## 复现要求

在同一次游戏启动中连续复现数次最有价值。每次看到“炮弹在怪物身上爆炸但未扣血”时，记下
大致时间、地图坐标和怪物名称；无需暂停游戏。测试结束后退出游戏，保留该次启动生成的完整
JSONL 文件。若使用独立服务器，同时保留相同时间段的客户端和服务器文件。

不要手工节选单条碰撞记录：判定差异可能来自更早的命令拒绝、角色位置差、目标在飞行期间
死亡，或客户端使用了比服务端更新/更旧的怪物坐标，分析需要完整关联链。
