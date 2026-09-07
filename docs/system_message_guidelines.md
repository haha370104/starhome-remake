# 系统提示交互规范

## 主提示通道

屏幕中央的“停留—上浮—淡出”系统消息是游戏的**主要提示方式**。技能升级、装备规则拒绝、
移动条件不足、地图准入失败以及其他需要玩家立即注意的业务结果，都必须进入
`HallHud.show_system_message()` 的串行队列：

- 初始位置位于当前视口正中央，窗口缩放后仍重新居中；
- 原位停留 1.5 秒；
- 随后在 1 秒内向上移动 56 像素并逐渐透明；
- 多条消息依次播放，不互相覆盖。

左上角状态文字只保留为路线目标、连接状态和开发诊断的辅助信息，不能作为业务错误的唯一反馈。
客户端本地预检失败与服务端 `command_rejected`/地图准入失败必须走同一个中央提示入口，避免离线
调试和联网模式呈现两套交互。

## 稳定错误码

客户端按稳定错误码映射玩家文案，不直接依赖英文服务端细节。当前装备与移动规则至少包括：

| 错误码 | 玩家提示 |
| --- | --- |
| `movement.no_propulsion` | 未安装可用推进器，战车无法移动 |
| `equipment.chassis_change_forbidden_in_field` | 野外地图中不能更换战车 |
| `equipment.chassis_change_requires_empty_loadout` | 更换战车前请先卸下其他战车装备 |
| `equipment.chassis_required` | 请先装备战车，再安装其他装备 |
| `equipment.chassis_required_for_field` | 未装备战车，无法进入野外地图 |
| `equipment.primary_weapon_required_for_field` | 未装备主武器，无法进入野外地图 |
| `inventory.revision_conflict` / `equipment.revision_conflict` | 装备状态已经更新，请重试 |

新增业务拒绝时，应先定义稳定错误码及中文文案，再接入中央提示；英文 `message` 只作尚未登记错误的
诊断回退，不应成为正式玩家文案。
