# 背包操作与食品效果

更新：2026-09-15。

## 交互与权威边界

背包物品右键优先打开能力菜单：服装/战车装备显示“装备”，可使用物品显示“使用”，
可堆叠物品显示“拆分”“合并”。拆分输入数量；合并把同定义、同绑定且未锁定的堆叠
尽量合入选中项，达到上限后保留余量。锁定操作禁用，单份物品禁用拆分。
空白处右键仍关闭最上层窗口。已存在同类食品增益时，使用前提示替换。

客户端链路：`GameWindowManager` 只处理最上层窗口路由，`InventoryPanel` 组合内容，
`InventoryCanvas` 命中物品，`InventoryContextMenu` 发布语义命令；
`PlayerPanelSession` 补齐装备版本。UI 不扣数量、不计算权威效果、不访问存档。

领域链路：`Player.change_stack/use_inventory_item/advance_food_status` 是聚合行为。
`InventoryStackActions` 保证拆分/合并数量、容量、绑定与 revision 不变量；
`ConsumableItem` 持有目录规则，`FoodStatus/FoodEffect` 持有体力、增益及同类冷却。
食品经验通过 `SkillBook.grant_experience` 进入既有技能结算；战斗目录派生伤害、
生命上限和食品防御，真实 `VehicleCombatState` 结算治疗和减伤。

服务层 `AuthoritativePlayerPanelService` 生成隔离候选，服务器提交成功后同步地图资源。
使用能量包前捕获实时战斗能源，不能使用上次存档的旧值。食品热更新不重置射击冷却、
维修状态或弹体；单纯拆分/合并不重建战斗角色。
`AuthoritativeFoodRuntime` 独立编排每秒推进，玩家唯一状态仍在 `AuthoritativeAutosaveService`。

新增命令只接受实例身份、背包 revision 及拆分数量：

- `use_inventory_item(instance_id, inventory_revision)`
- `split_inventory_item(instance_id, inventory_revision, quantity)`
- `merge_inventory_item(instance_id, inventory_revision)`

客户端不能提供效果、当前时间或恢复量。失败不提交候选；背包版本拒绝成功后的重复请求。
装备继续使用既有 `equip_vehicle_item/equip_character_item`，同时校验装配或玩家版本。

## 原客户端证据

正式来源为本地荣耀版 `../starhome_lz_ry_fcc_source/cltobj/stuffclt2.fcc`：

- 第84、160行起，低/中级能量包 `m_ncontent` 分别1000、10000。
- 第26205行起 `NewFoodBase` 声明 `m_nAddPhysical`、`m_szFoodKind`、
  `m_szSkillInfo`；每项包含效果数值、持续秒数和冷却秒数。
- 类型1～12依次为能量炮、导弹、火箭、驾驶、采矿、隐身、雷达、维修、制造、提炼、
  裁缝、烹饪经验百分比；13～15为三种炮的基础攻击加值；16为战车生命上限；
  17为战车基础防御；18为人物每秒回血；19为战车即时回血。
- 食品右键原菜单明确排除玻璃酒瓶，它仍只能作为材料使用。
- `ven/MainClient_Me_ven.fcc` 的 `EatNewFood` 第3643行起显示同类效果替换确认。
- `dzl/food/foodclient/food_playerclient.fcc` 给出体力上限100；体力变化由服务器回包提供。

`data/gameplay/consumable_effects_v1.json` 接入当前目录已有的31种食品、两种能量包，
另兼容旧 `low_grade_energy_pack` 定义，共34条。韩式寿司原表恢复体力为0，未统一改成10。
不额外投放目录之外的升级食品，不修改食品堆叠上限或添加素材。
`python -X utf8 tools/audit_consumable_effects.py` 逐条对照本地FCC类及继承字段；
只解析文本，不执行原客户端脚本。源文件SHA-256：
`e15e9ee489043692618d3e8b6fd2b6cd8519de5205d12c7ee248e9aec021c7bb`。

## 复刻规则与未证实边界

原客户端不能证明服务器减伤公式、离线计时和饥饿消耗频率，以下属于复刻实现：

- 同类效果替换，不同类型共存；冷却按效果类型共用，服务器Unix时间计算。
- 增益离线继续到期；离线期间不补人物回血；人物死亡不自动复活。
- 生命上限变化保持绝对当前生命，仅在超过新上限时截断，不凭空按比例回血。
- 食品防御从本次入射伤害扣除，最低0；其余未确认原服战斗公式沿用现有复刻规则。
- 体力恢复、上限和持久化已实现；未擅自编造原服饥饿衰减及低体力惩罚。

`PlayerStateRecord.food_status` 保存体力、效果、到期时间和冷却。旧存档缺失该字段时
默认体力100、无食品效果；非法类型、数值和重复效果在存档/投影边界拒绝。
背包底部显示体力及有效效果数量，悬停可查看加值与剩余时间。

## 回归入口

- `tests/domain/consumable_and_stack_test.gd`：全目录、数量守恒、绑定/锁定/满包、堆叠上限、冷却与离线时间。
- `tests/server/consumable_authority_test.gd`：实际使用、经验与战斗加值、JSON往返、正式服务器实时能源与回血、冷却保留。
- `tests/ui/runtime/inventory_context_menu_test.gd`：真实右键输入、菜单、拆分数量、权威回包和替换提示；`-- --capture` 可输出窗口截图。

三个专项纳入 `tools/run_client_checks.py`；本次执行记录以交接页中的报告为准。
