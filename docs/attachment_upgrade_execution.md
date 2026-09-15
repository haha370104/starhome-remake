# 接合器强化执行

2026-09-15 开放：商城顶部“接合器强化”进入独立窗口，选择背包或已装配接合器，
查看当前/下一级效果、材料拥有量与缺口、星际币消耗，确认后执行。

## 规则

- 九种普通接合器全部开放：新式最高+5、旧式最高+4，共40条阶段方案。赠品暂无已确认配方。
- 每次升一级，成功率100%，不降级、不碎装；这是本轮复刻默认，不声称恢复原服成功率。
- 只消耗实际背包材料和原配方金币。材料在商城购买时已经付过紫晶，强化不再次扣紫晶。
- 配方直接复用[材料预算表](attachment_upgrade_shop.md)，客户端不能指定等级、金额或消耗数量。
- 锁定装备不能强化，锁定材料不计入可用数量。已绑定装备可强化并保留绑定。
- 实例身份、槽位、耐久和耐久上限保持不变；损坏装备不会因强化自动修复，其效果仍遵循耐久失效规则。
- 已装配接合器强化后推进装配版本，按原路径刷新战车与权威战斗加值；背包接合器升级不会提供装配加值。
- 侦测数值可升级，但雷达/隐形玩法仍未实现，界面明确标识此限制。

旧式最高阶段需要钾、钡镁合金各999个；每叠99个时，加上其他材料超过40格背包，无法执行。
这两种材料的最大堆叠调整为999个，保留原材料用量、物品ID和现有小堆叠；其他物品不变。

## 领域与事务

`AttachmentUpgradePricing` 校验原配置，提供类型化 `AttachmentUpgradePlan`。
方案限制定义ID和当前等级，`VehicleEquipment` 拥有锁定、逐级与上限校验和等级变更行为。
`Player.upgrade_attachment` 查验所有权及背包/装配版本，在支付前完成装备校验；
`Inventory.pay_upgrade_cost` 整体预检金币和全部材料，再原子扣除并推进一次背包版本。
`AttachmentUpgradeService` 只解析不可信意图和生成投影，事务由既有 commerce → autosave 流程提交。
权威服务器提交前构建新战斗装配，提交后同步地图战斗状态；入口脚本不增加业务行为。

命令：`query_attachment_upgrades` 和 `upgrade_attachment`，后者只使用 `instance_id`、
`inventory_revision`、`loadout_revision`。正式会话绑定玩家身份，过期/重复请求失败且不多扣材料。
回包 `attachment_upgrades` 与人物、背包、战车来自同一已提交状态。

修复 `EquipmentSlotRecord` 原先遗漏的 `bound`/`locked` 字段，服务端映射与客户端恢复同时补齐。
旧存档缺省为false；已有存档中从未保存的标记无法追溯恢复。JSON存档与正式文件仓储已验证。

## 缺图补绘

相关缺失素材只有加工石1项。荣耀精确路径 `pic2/stuff/ProcessStone.ale` 的本地缺失及官网404证据保留。
用户本轮授权少于3项时参考现有素材补绘，因此用内置 image_gen 生成透明底加工石，导出64×64运行图标，
标记为复刻自制而非原版素材；没有跨版本替代。

最终图标：[icon.png](../assets/items/materials/processing_stone/icon.png)。
提示词及来源：[manifest.json](../assets/items/materials/processing_stone/manifest.json)。
提示词核心：参考原图灰绿金属、青色高光和等距视角，绘制钢制固定环内的浅青色加工晶石，透明底，无文字和场景。

## 验证

- `attachment_upgrade_test.gd`：40阶段 × 背包/装配，精确扣费、锁定、缺料、满级、版本、JSON重启、实例保持及权威炮击伤害。
- `attachment_upgrade_ui_test.gd`：真实商城入口、预览、确认取消、成功同步、下级缺料；支持实际渲染截图。
- `in_process_authoritative_transport_test.gd`：正式会话命令、仓储提交、磁盘重开及重复请求拒绝。
- 两项新专项已纳入 `tools/run_client_checks.py`。

本轮总门禁42/42通过（含零脚本警告），报告 `.godot/client-checks-20260915-133926-3884/summary.json`。
强化专项1975项、正式传输34项断言通过；最后装备图标模式修正另通过实际渲染UI专项，截图 `.godot/attachment-upgrade-panel.png`。
18个本轮GDScript文件函数注释检查通过；材料获取链审计40阶段缺失0、佣兵误过滤0。
