# NPC 个体配置

每张地图保存独立 NPC 列表；大厅见 [yian_harbor_hall_floor_1.json](./yian_harbor_hall_floor_1.json)。
不在场景脚本逐个硬编码 NPC 身份。

## 字段

- `id/name/appearance/kind`：稳定身份、名称、外观、业务种类（shop/quest/ambient）。
- `spawn`：世界脚点，不是图片左上角。
- `patrol.speed/animation_speed_scale/initial_delay`：每个 NPC 独立配置，不引用玩家速度。
- `patrol.points`：顺序巡逻点；各点 `position` 和随机停留区间 `dwell`，当前大厅为三角循环。
- `interaction.body/actions`：交互正文和动作声明，不在 JSON 塞入可执行代码。

## 模型与视图分工

- [领域 NpcBase](../../scripts/domain/npcs/npc_base.gd) 继承 MovableEntity，声明身份、巡逻点与交互能力；
  [ShopNpc](../../scripts/domain/npcs/shop_npc.gd)、[QuestNpc](../../scripts/domain/npcs/quest_npc.gd) 扩展业务入口。
- [NpcWorldView](../../scripts/npcs/npc_base.gd) 是 Node 表现层，驱动导航、等待、动画与交互暂停；
  文件同名不代表领域对象也是场景节点。
- [ActiveWorldController](../../scripts/client/world/active_world_controller.gd) 的 `_create_npc_for_kind()`
  创建视图子类；不是旧说明中的 `MainHall` 工厂。

当前巡逻是客户端环境表现，不保证多客户端看到完全相同位置。
当前商店买卖、材料循环任务和每日训练已有权威服务，见
[任务说明](../../docs/repeatable_quests.md) 与 [工业制造](../../docs/industrial_manufacturing.md)。
NPC 视图只发起交互，奖励、材料、金币和任务状态仍由服务端用例裁决，不在巡逻 Node 中结算。
接入真实业务时必须提交权威用例，不能在 Node 回调里修改货币、背包或任务奖励。

巡逻点应预先验证在导航图可走区域内；运行时最近可达点回退仅为容错，不替代配置校验。
