# 装备耐久维护规则

P2-B 已完成：资格、工具、领域模型、权威交易、维护窗口、运行期磨损与副武器弹药已接入。

## 原版依据与复刻参数

- [生成器](../tools/build_equipment_maintenance_rules.py)从装备继承属性、服装 `m_szDoupStuff` 和 `ven/FastRestoreCltClass.fcc` 生成[维护配置](../data/gameplay/equipment_maintenance_rules_v1.json)。
- 929 个地面装备/服装资格中，551 个具有完整常规维护规则；137 个存在未接入材料，逐项列在 `unresolved`。余下包含明确不可维修或没有确认维护配方的类型。普通护甲遵守 `m_nAgreeRepairHardiness=0`，有后期明确覆盖值的变体逐项保留。
- 常规车载装备费用为 `m_nRepaireHardinessUpkeep * m_nWorth / 100`，材料来自原字段。部分初级车炮引擎在该版源码中明确注释掉材料，故允许免材料维护；不把注释当生效配方。
- 普通维护后的新耐久上限来自原服务器回包，客户端没有损耗公式。**复刻设定每次减少当前上限的 1%，向上取整，最低留 1 点**。执行前必须展示新上限。服装修补与速修保持上限。
- 服装维护使用裁缝等级、修补材料与 `m_nDoupOneSuffer` 修补经验；该字段不是“每次受击扣耐久”。所有经验仍须走奖励切面。
- 六种[速修箱](../data/gameplay/equipment_maintenance_items_v1.json)：电磁缓释箱恢复 300/600/1000 点；光导单体/群体箱恢复当前上限的 100%，作用于已装配战车装备；离子箱恢复背包中的一件。普通护甲和服装不冒充普通战车装备接受这些工具。
- 工具价格为复刻星际币定价：500/900/1400、2000/6000、2000。免费版六张原图已导入素材子仓库；荣耀与激战对应精确地址均 404，原始 SHA256 和地址保留在物品定义。
- 常规维护地点为配置中的基地/城区/既有生产设施地图；通过背包入口操作，不恢复已删除 NPC。速修的装配/背包范围独立校验。
- 维修链路完成后已启用磨损，`wear_thresholds` 为可配置复刻节奏：武器每 20 次有效开火 1 点、引擎每 60 秒实际移动 1 点、挖掘臂每 20 次成功采掘周期 1 点、服装每 100 次实际受伤 1 点。原版 `m_nNoDurable`、缺维护链和明确不可常规维护装备不启用磨损。副武器按实际选中的实例计数，失败/冷却/缺能量不计数。
- 装备拥有使用余量，换装、跨图、救援和重启保留。只在刚损坏时重算属性；损坏武器停止开火，引擎停止提供推进力，损坏服装停止提供技能与原创强化增益。维修不清空使用余量、不重置开火冷却、不补工作能量。
- 原荣耀服装 `wear_degree` 已映射为耐久上限；旧版误存为完整 1/1 的服装恢复原上限，已损坏的 0/1 不自动修好。

## 验证

弹药使用独立 `WeaponMagazine` 保存当前弹量，容量从装备和加工派生。[弹药配置](../data/gameplay/equipment_ammunition_rules_v1.json)保留 59 个原版地面装备的容量及每发价格；非攻击装置只登记原字段，能力在 P4/P5 按其资格启用。缺口乘以 `m_nAddBulletWorth` 的费用来自 `cltobj/firegunclt.fcc:201`、`cltobj/appendequipclt.fcc:911`。新物品和缺少弹仓字段的旧档仅首次初始化满弹。能量炮不消耗副武器弹药。

维护窗口新增「补充弹药」，支持背包和已装配装备，地点、锁定、满弹、费用与库存版本均由服务端验证。底部原副武器图标显示实时余量，仅数字变化时复用控件。[弹药测试](../tests/domain/equipment_ammunition_test.gd) 23 项通过；维护窗口追加补弹测试后共 19 项通过。

[领域测试](../tests/domain/equipment_maintenance_model_test.gd) 2561 项通过，覆盖全部资格与材料身份，以及满耐久、锁定、损坏修复、普通维护降上限、速修保上限、服装隔离和地点名单。
P2-A 全量回归 78/78 通过，报告 `.godot/client-checks-20260917-223645-35272/summary.json`。

[维护交易测试](../tests/server/commerce/equipment_maintenance_authority_test.gd) 37 项通过，覆盖材料/金币原子结算、群体速修单次扣箱、绑定传播、原始加工保留、重发和裁缝经验倍率；[维护窗口测试](../tests/ui/runtime/equipment_maintenance_panel_test.gd) 15 项通过，已实际渲染检查。背包右键「耐久维护 / 速修」进入，窗口支持常规维护、速修和工具购买。加工窗口回归 15 项通过，GDScript 警告与错误均为 0。

[使用余量模型](../tests/domain/equipment_usage_model_test.gd) 35 项、[实际磨损/修复/重启](../tests/server/combat/equipment_usage_authority_test.gd) 20 项通过。同档车炮连续输出回归 13985 项通过，八档仍均满足至少四五秒输出。

P2 整体覆盖 84 项测试。首次运行 83/84（`.godot/client-checks-20260917-233329-38864/summary.json`）；能量包回归发现战斗刷新覆盖刚结算的能源，已将同步限定为装备耐久/弹仓，并补跑 `consumable_authority_test` 通过（`.godot/ammunition-consumable-regression.log`）。其余 83 项通过，包含地图切换、持久化、进程内权威传输、装备表现、采矿、制造、食品、称号和战斗能源。
