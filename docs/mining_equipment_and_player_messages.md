# 采矿装配准入与玩家中文提示

## 采矿规则（2026-09-07）

修复前 `AuthoritativeMiningModule.begin_collection` 校验矿物选择、距离和技能，但服务器入口未校验装备，因此安装能量炮也能采矿。

现在：

- `ItemCatalog` 在旧数据适配边界把地面采掘臂规范化为 `mining_arm`；实例类型为 `VehicleMiningArm`，不继承炮的攻击行为。
- 原版证据：荣耀 `cltobj/equipclt.fcc` 的 `CollecTor:BaseEquip`（约 4934 行）声明 `m_nLocation=1`、`m_nEquipKind2=4`。此前子类导出未展开槽位继承。主装置槽内只能装一件能量炮或采掘臂，背包持有采掘臂不算安装。
- `VehicleLoadout.validate_mining` 校验底盘、主装置类型，采掘臂自身校验耐久与使用技能等级。不是按中文名称或客户端传入的布尔值判断。
- 权威服务器在开始采矿和每次三秒产出结算前，分别从最新存档内存聚合恢复 `Player` 并调用同一领域规则。失败时停止本次预约，不扣矿、不入包、不增加采矿经验。
- 采掘臂装配可以进入野外，但不登记能量炮攻击能力。客户端也不为已确认装备采掘臂的角色预测主炮开火；即使伪造攻击请求，服务端仍会拒绝。
- 不改变现有采矿产量、三秒周期、矿物技能要求和能耗规则；本次不声称完整还原原版采掘效率或能量消耗公式。

### 表现资源

商人白名单现有 7 档地面采掘臂（10/30/60/100/150/200/250 级）八向资源按需导入，目录为 `assets/equipment_world/mining_arms/level_N/working`。换装时使用同一 `PlayerVehicle.loadout` 选择实际组件，不能继续显示上一把能量炮。

`tools/import_glory_mining_arms.py` 复用现有荣耀帧导出器，保留 ALE 的每帧 origin 和方向帧块，源路径和哈希保存在 `mining_arms/source_manifest.json`。不启用太空采掘臂，不修改其他装备映射或玩家存档。

## 中文错误边界

`PlayerErrorMessages.describe(code, detail)` 是客户端统一映射入口。网络协议保留稳定错误码及诊断原文，领域与权威计算不因翻译而变化。

- 常见采矿、战斗、自维修、背包、换装、商店、任务、生产、拾取等失败按错误码给出中文原因和下一步。
- 已有简短纯中文业务提示保留数值细节，例如每日任务次数；混合英文、内部路径不直接透传。
- 未登记错误使用业务类别的中文回退，完全未知错误显示“操作暂时无法完成，请稍后重试”。不能用“操作失败：”拼接英文异常作为回退。
- 中央提示与左上状态栏使用相同映射，初始连接、地图预载/提交失败界面也经过映射；日志仍记录错误码及原始详情供开发排查。
- 新增错误时优先添加稳定错误码映射，不在不同窗口中复制翻译逻辑，也不通过英文句子匹配识别业务。

## 采矿动作接线修正（2026-09-13）

此前的资源导入不等于动画已接通：世界装置的 idle/move/attack 都被设为静态，且没有消费权威采矿状态。点击矿物也未在 UI 入口检查装备，无条件的“正在准备采矿”会误导玩家。

- 点击入口读取 `CurrentPlayer.vehicle.loadout.validate_mining`；能量炮、背包内未装配的臂、损坏或技能不足均不发送采矿请求，立即显示中文原因。服务端入口和每次产出前的校验继续保留，客户端校验不代表授权。
- 成功换装后按权威 `vehicle_loadout_revision` 变化立即中断旧动作，短暂换炮再换回臂也不会恢复旧预约。移动、攻击、死亡、背包结算失败、矿源耗尽会结束动作。
- 战斗快照增加可选 `local_mining`：`{active:false}` 或 `{active:true,source_id,target_position:[x,y]}`。客户端验证字段类型和有限坐标；离线传输与 ENet 均消费同一个权威快照。
- `MiningVisualController` 仅将活动状态投影为主装置的 `collect` 八向动画。该动作仅为 `VehicleMiningArm` 登记，不能把炮伪装成采掘臂；重复快照不重置动画时钟，停止/切图释放局部动作和朝向。
- 荣耀源码 `CollecTor.PlayCollect` 设置采集朝向，`PlayCollectAle` 递归播放 `move`，`StopPlayCollect` 终止循环。复刻沿用导出资源的方向帧块、循环和帧率；尚未确认原 `PlayAni(...,60,...)` 的时基单位，不声称播放速度已逐毫秒还原。

2026-09-14 时序更新：上述历史默认 10 fps 已改为 `1000 / 60 ≈ 16.67 fps`，即每帧 60 ms；5/6 帧分别约 300/360 ms 一轮。依据是 `CollecTor.PlayCollectAle` 的第二参数 60，以及 `npcbasecltmain.fcc:940,1035` 将同一参数明确称为 `m_nPlayActionDelay`（播放动画的延迟时间）。60 ms 是本次基于脚本语义的换算，不是已完成原引擎计时调用链证明。只调整采掘臂表现，不改变权威三秒采矿周期。7 档臂的帧率已加入 D04 回归，现为 333 项通过。

本轮已执行：权威采矿服务器 24 项、采矿模块 60 项、进程内传输 22 项、D04 世界表现 326 项；包含炮点击完整周期无产出、立即换装中断、7 档臂各 8 向实际帧变化、停采静帧及畸形快照拒绝。正式入口静态检查 0 warning / 0 error。上述测试已有总门禁登记，本轮未运行全库门禁，也未操作用户运行中的游戏或存档。

当前动作表现接入本地玩家；远端玩家世界表现仍是现有独立范围，不能把该字段当作已完成全部远端采矿展示。

## 2026-09-14：重启后采矿入账冲突与工程臂主槽

- 实际用户日志中的错误为 `inventory.duplicate_item: reward item identity already exists`，
  存档里仍有 `d04_field_zone.instance.1.cycle.0`。旧采集 token 只由地图实例和内存计数器组成，
  重启或地图重建后从零计数，与已持久化矿石的实例编号重复；这不是背包容量问题。
- 每个权威采矿模块现在生成 128 位随机命名空间，周期编号由地图、命名空间、计数器组成。
  同一预约重试仍使用原 token；没有移除背包重复入账校验，也无需清空或迁移用户存档。
  进程内传输与 ENet 继续共用同一服务端结算。若其他路径出现编号冲突，界面明确提示入账编号冲突，日志保留原错误。
- `ItemCatalog` 将荣耀 `Repair`（主槽 Location 1、EquipKind2 3）从误分类的 `vehicle_weapon`
  归一化为 `repair_arm`，构造普通 `VehicleEquipment`，不再作为 `VehicleWeapon` 注册开炮。
  商店继续出售原来六档地面维修臂。此修复不代表已实现对其他玩家的主动维修能力。
- `VehicleEquipment.primary_device_kind()` 为 HUD 与输入路由提供同一业务类型；
  `CurrentPlayer → HallHud.set_primary_device → HudState → FreeBottomMainBar` 同步换装、卸下和选中态。
  输入协议中 `energy_cannon` 暂保留为主槽兼容键，不再据此判断所装物品。
- 主槽选中工程臂时，空地左键静默返回，不提交能力意图、不产生弹体、不改动移动路线。
  拾取和点矿逻辑仍先处理；显式选择的导弹等战术槽不被工程臂拦截。
- 底栏使用已批准的免费版 HUD 图标：`pic/equipface/tank_collent.ale` 与 `tank_repair.ale`，
  两帧原尺寸 29×22，对应 normal/selected；运行时使用 `weapon_modes/mining_arm`、`repair_arm`
  语义路径。荣耀对应 `cltobj/equipclt.fcc` 的 `m_sEquipFaceFile` 也确认两类有独立图标；
  其 34×32 三帧版本不混入免费版 HUD。来源哈希与裁切帧已记入 `free_hud_sources.json`。

本次回归包含真实测试存档重启后两周期累积产出、防重复校验仍拒绝旧编号、13 款工程臂模型/HUD/空点击、
主槽换装/卸下/战术槽互不干扰及像素尺寸。未改动用户存档。

验证结果：采矿服务器 31、采矿模块 81、进程内传输 22、D04 世界表现 438、HUD 89、
物品目录 26、武器商人 74、人物装备面板 87、装配权威战斗 8、中文消息 76 项通过；
主入口静态检查 0 warning / 0 error，35 项 HUD 来源审计与素材大小策略通过。
这不是全库测试结论，工作区中其他模块的未提交改动未纳入本次提交。

## 历史验证（2026-09-07）

- `authoritative_mining_server_test.gd`：17 项，含能量炮拒绝、背包臂拒绝、真实换装、三秒产出、换炮后拒绝后续产出、损坏臂拒绝。
- `authoritative_mining_module_test.gd`：60 项，原采矿模块规则保持。
- `player_error_messages_test.gd`：75 项，已登记文案、未知/混合英文/路径回退、中央与状态栏、连接失败。
- `hall_multiplayer_presenter_smoke_test.gd`：25 项；`d04_player_vehicle_presentation_test.gd`：95 项，覆盖 7 档臂真实资源与换装组件。
- 物品目录 26 项、武器商人 74 项、实际装配战斗 8 项、战斗目录 2274 项、战斗模块 161 项通过。入口脚本静态检查 0 warning / 0 error。

新增中文提示与采矿服务端/模块测试已接入 `tools/run_project_checks.ps1`。未宣称全库门禁通过：其他正在修改的模块仍有函数注释缺项；本次仅提交本任务的代码、资源和文档。
