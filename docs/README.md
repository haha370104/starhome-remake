# 文档导航

更新：2026-09-18。本页是完整文档目录；新对话先读交接，整体 review 再读评审导读。
导航覆盖由 `python -X utf8 tools/check_documentation_links.py` 检查，不靠文件名或提交时间猜顺序。

## 新对话最短阅读路径

1. [项目交接](project_handoff.md)：当前能力、未完成边界、最近提交、存档与外部档案、接续提示词。
2. [项目硬约束](../PROJECT_CONTEXT.md)：版本白名单、中文注释、权威所有权、提交和 LFS。
3. [复刻对齐方案](remake_alignment_plan.md)：从现象到证据、模型、权威用例、视觉验收的统一流程。
4. [原客户端代码阅读](original_client_reading_guide.md)：FCC 检索、继承/回调、图像语义和证据卡。
5. [双运行模式](runtime_modes_architecture.md) → [评审导读](review_guide.md) → 下方具体模块。

## 阅读入口与口径

| 想回答的问题 | 先读 |
| --- | --- |
| 新对话如何接着做？ | [项目交接](project_handoff.md) |
| 怎样系统对齐原版而不是反复补丁？ | [复刻对齐方案](remake_alignment_plan.md) |
| 怎样从名称、截图找到原客户端代码？ | [原客户端阅读指南](original_client_reading_guide.md) |
| 当前到底做到了哪里，先 review 什么？ | [代码评审导读](./review_guide.md) |
| 原版有哪些功能还没接入？ | [原版功能缺口核查](original_feature_gap_audit.md)：战车开槽/镶嵌、装备成长、多人玩法及主动精简的边界 |
| 游戏应当怎样玩？ | [玩法规格](../../游戏主要玩法.md)，在仓库外的 `outputs/` 中 |
| 开发有哪些硬约束？ | [项目全局约定](../PROJECT_CONTEXT.md) |
| 如何启动和手工验证？ | [仓库 README](../README.md)、[使用说明](../使用说明.md) |
| 独立服务器与离线直连到底共用了什么？ | [双运行模式架构](./runtime_modes_architecture.md) |
| 为什么采用这些边界？ | [技术架构](./technical_architecture.md)，注意目标结构不等于现有目录 |
| 接下来做什么？ | [非多人玩法补齐计划](pve_completion_plan.md)是当前玩法顺序；[开发路线图](./development_roadmap.md)保留工程阶段和历史验收 |
| 全量资源与可玩内容有什么区别？ | [运行内容与资源包](./runtime_content.md) |

证据优先级：用户确认的玩法/工程约束决定“应该怎样”；当前源码、配置和可复现测试决定
“实际怎样”；逆向文档决定“原客户端有什么证据”。三者有冲突时记录差异，不通过改文案
把实现自动判为正确。历史通过记录不代表当前工作树再次通过。

## 当前模块说明

- [战车加工实施台账](vehicle_workshop.md)：P0/P1 资格、原版与复刻规则、材料用途、实例状态兼容。
- [普通装备加工](equipment_processing.md)：P2 属性上限、原版材料、同源变体与加工实例。
- [护甲精工](armor_refinement.md)：P3-B 八阶护甲、失败销毁及晶石保留。
- [季节时装改良](clothing_improvement.md)：P3-C 七类纤维、百级单方向成长、获取链和旧帽子槽位兼容。
- [记忆模块](equipment_memory.md)：P3-D 六类成长提取转移（含锻造）、风险确认和跨实例原子事务。
- [普通装备品质](equipment_quality.md)：原版四档固定加成、制造品质分布与旧档兼容。
- [普通装备拆解](equipment_dismantling.md)：15款绿色以上装备、四档返还、容量预检与销毁确认。
- [装备锻造](equipment_forging.md)：原版扩展上限、失败与加工清除、锻造模块转移。
- [PVE装置能力](pve_devices.md)：发生器规则、权威触发与原版状态特效；隐身和雷达范围核查。
- [个人仓库](personal_warehouse.md)：六柜存取、原版扩容费用、完整实例状态与旧档兼容。
- [批量生产](batch_production.md)：原版次数/速度核查、复刻计时与取消方案；实施状态在文中单列。
- [智脑扩展](smart_assistant_extensions.md)：自动补给、四套装配、PVE击毁记录及原版/复刻边界。
- [设置与退出](client_settings_and_exit.md)：本地显示/按键/音量偏好、正常退出的权威保存和失败重试。
- [奥斯格兰装备](austin_glens_equipment.md)：P5-B成长、固定符文和PVE受击能力，状态及原版证据单列。
- [晶源体与晶源核](crystal_source_equipment.md)：P5-A独立品质/成长、三核心槽、五合一及原文数量差异；当前状态见文首。
- [撒玛装备](sama_equipment.md)：P5-C阶段、品质、转移和穿透/脉冲/核变技能台账。
- [中枢控制器](central_controller.md)：P5-D桥接芯片、圣焱核心、六件附属装备成长及致命一击。
- [装备十星强化](equipment_strengthening.md)：P3-B 独立星级、材料投入与失败降星。
- [萤石与耀石加工](extra_attribute_processing.md)：P3-A 独立通道、失败退级、获取与实际属性。
- [维护、磨损与弹药](equipment_maintenance.md)：P2 常规维护/速修、实际使用余量、补弹与验收。

- [缺失素材跨版本检索与恢复](cross_release_asset_recovery.md)：免费/激战候选、用户差异选择、15项正式恢复及完整结果表。

- [经验与掉落倍率切面](reward_modifiers.md)：账号/技能/物品规则、食品经验迁移、VIP扩展端口及权威结算。

- [日常活动与智脑](daily_activities_and_smart_assistant.md)：佣兵/历练紫晶收入、八按钮 HUD、主动回城与客户端增强。
- [掉落期望与材料升级](original_monster_drop_balance.md)：材料相对等级期望、稀有物分类、柔解剂和晶石5比1生产。

| 文档 | 责任范围 / 阅读时注意 |
| --- | --- |
| [评审导读](./review_guide.md) | 当前职责图、源码入口、优先级、检查清单与已知缺口 |
| [工程规范](engineering_standards.md) | 分层、状态所有权、组件复用、测试与提交要求 |
| [客户端结构与阅读顺序](client_architecture.md) | 入口拆分、控制器、共享组件、状态链路及本轮验证范围 |
| [技术架构](./technical_architecture.md) | 架构决策、目标依赖、协议和完成定义；含尚未实现的目标设计 |
| [双运行模式架构](./runtime_modes_architecture.md) | 进程边界、启动握手、传输/模拟差异、状态归属、保存与验证 |
| [背包操作与食品效果](inventory_item_actions.md) | 右键菜单、拆分合并、原版食品、权威时钟与存档 |
| [人物/背包/战车](./player_panels_architecture.md) | Player 聚合、同版本投影、换装事务、背包几何 |
| [人物装备强化与变异/BOSS](character_equipment_enhancement_design_v1.md) | 已实现的三类强化、操作费用、原创图标、37种新怪数值与掉落期望、调参入口 |
| [装备展示模式](equipment_presentation_modes.md) | 世界、背包、面板三种图像身份和统一装配投影 |
| [自由背包布局](inventory_free_position.md) | 像素占位、拖放、吸附与原生图片尺寸分离 |
| [持久化](./persistence_architecture.md) | 3 秒自动保存、开发文件仓储、revision、SQLite 待接入边界 |
| [技能成长](./skill_progression_architecture.md) | 经验阈值、事件来源、综合等级和技能面板 |
| [地图解析管线](./map_resource_pipeline.md) | FCC/ALE/PKH、碰撞、静态合成、语义遮挡和缺失依赖 |
| [地图驻留与性能](./map_residency_and_performance.md) | 按玩家启停、休眠状态、在途事务、寻路退化及测量范围 |
| [怪物掉落覆盖](./monster_loot_coverage.md) | 无掉落怪物全量名单、D03 隐形材料掉落修复 |
| [怪物命中特效覆盖](monster_hit_effect_audit.md) | 119种怪物审计、免费版22段补图、原版绑定证据与剩余9项 |
| [野外怪物种群](./field_monster_populations.md) | 逐图刷怪、历史分布证据与复刻默认、小地图出口 |
| [运行内容与资源包](./runtime_content.md) | 当前地图/动画/物品/配方/矿源数量和完整性边界 |
| [已知内容注册表](./known_content_registry.md) | 身份和来源查询；旧 runtime 映射不能替代新运行目录 |
| [战斗诊断](./combat_diagnostics.md) | JSONL 位置、同一发子弹的跨端关联、复现采集方式 |
| [工作能量与连续输出](vehicle_energy_endurance.md) | 四五秒验收、八档车炮实测、储备耗尽及连点/换车回归 |
| [采矿、主装置与错误文案](mining_equipment_and_player_messages.md) | 装配准入、三秒周期、重启入账身份、两类工程臂 HUD/空点击 |
| [矿物渲染与装备叠层](mineral_rendering_and_equipment_layers.md) | 重复乘色修复、矿源变体、采掘臂帧率与面板层级 |
| [工业制造](industrial_manufacturing.md) | 提炼、主/附属装备、合金和维护包；83 条可执行规则与排除项 |
| [循环任务与训练](repeatable_quests.md) | 四类材料任务、每日五类训练、权威奖励/去重/跨天保存 |
| [成就与称号](achievements.md) | 击杀、采矿、任务成就，自动晋升与权威战斗增益 |
| [底栏导航窗口](bottom_menu_windows.md) | 玩家名单、任务日志、系统菜单、商城 UI 及未实现功能 |
| [系统消息规范](system_message_guidelines.md) | 面向用户中文提示、中央通知和日志分工 |
| [素材目录与 Git](./asset_management.md) | 业务命名、版本白名单、普通 Git/LFS/缓存分工 |
| [NPC 配置](../data/npcs/README.md) | 个体配置、领域 NPC 与视图 NPC 的边界 |

## 原客户端证据：按问题查，不当成实现完成清单

| 文档 | 用途 |
| --- | --- |
| [素材关联关系](./asset_relationships.md) | 物品的背包图/面板图/世界动画，人物分层、怪物、阴影与特效 |
| [战斗与装备 UI 逆向](./combat_and_equipment_ui_reverse_engineering.md) | 人物、背包、战车窗口布局、数值、字体、交互和装备悬浮 |
| [免费版 HUD](./free_hud_rendering.md) | 顶底栏、快捷栏、小地图、固定像素布局；唯一版本豁免 |
| [物品悬浮](./glory_item_hover_rendering.md) | 背包/掉落高亮、说明框及尺寸，不用统一缩放猜测 |
| [特殊战车装备](./glory_special_vehicle_equipment.md) | 逻辑槽和视觉槽、套装/被动证据；不代表全部效果已实现 |
| [弹道命中与怪物状态](./projectile_hit_and_monster_state_reverse_engineering.md) | 旧端预测显示与权威结算边界 |
| [怪物弹体速度](./monster_projectile_speed_reverse_engineering.md) | 速度/延时证据与复刻参数区分 |
| [怪物覆盖层与阴影检查](monster_overlay_shadow_check.md) | 动作、阴影、悬浮层的证据及验证边界 |
| [武器商店逆向](weapon_merchant_ui_reverse.md) | 商品、等级、价格、装备详细信息与商店行为证据 |
| [免费版人物历练与佣兵](free_experience_and_mercenary_audit.md) | 10 条每日历练、495 条佣兵定义、每日规则和服务端边界 |
| [免费版佣兵任务全表](free_mercenary_task_catalog.md) | 全部任务条件、目标、数量、等级、品质和原积分；非运行配置 |
| [原版掉落与佣兵全量审计](original_drops_and_mercenary_audit.md) | 79种掉落名称的实际覆盖、495条任务逐条判定、金币捐赠误过滤修复 |
| [元素提炼与合金供应](industrial_material_supply.md) | 硫磷钾提炼、镍锌钛钪镁钡矿点、合金等级与原料获取链 |
| [升级材料商城与预算](attachment_upgrade_shop.md) | 七种材料单价、当前强化等级计价、40阶段用量及权威购买 |
| [接合器强化执行](attachment_upgrade_execution.md) | 单级强化、原子支付、装配生效、存档及加工石补绘 |
| [系统提示](./reverse_engineering/system_message_rendering.md) | 屏幕中央提示的字体、位置及生命周期 |
| [矿源渲染](./reverse_engineering/mine_source_rendering.md) | 远程矿源对象、调色板、储量与渲染的分离 |
| [FCC 与全量资源恢复](./fcc_resource_recovery.md) | 密钥来源、DLL 解密、索引下载、动画解析、官网精确依赖补抓 |

## 历史记录与迁移依据

保留原文件，不挪走用户提供的评审和证据；引用它们时必须带上阶段/日期。

| 文档 | 当前定位 |
| --- | --- |
| [2026-08-27 代码评审](./code_review_2026-08-27.md) | 当时的问题基线；不能把全部条目视为今天仍未修复，也不能全部视为已关闭 |
| [阶段 2 图谱种子](./stage2_map_graph_seed.md) | 最初大厅→城区→D04 的拓扑/入口证据；早期资源数量已过时 |
| [阶段 3 内容证据](./stage3_content_evidence.md) | 最初四怪/新兵装备纵切的来源与重建默认；不是全量内容目录 |
| [启动警告清理](./gdscript_warning_cleanup.md) | 2026-08-31 的清理记录和检查器范围；不是全部运行分支无错误的证明 |
| [开发路线图](./development_roadmap.md) | 计划与阶段验收历史；今天的横向覆盖优先看评审导读和运行内容清单 |

## 文档维护约定

1. 新模块说明登记在此，并在评审导读添加源码、配置、测试入口；不靠新增日期报告替代维护模块文档。
2. 运行状态变化同步更新对应模块文档；数字注明来源清单和日期，不把注册数量写成已玩通数量。
3. 逆向结论注明【客户端证据】【复刻默认】【待验证】；没有服务端证据时不推断原服公式。
4. 历史记录保留原始范围，在入口添加过时提示；工程规则以 `PROJECT_CONTEXT.md` 为准。
5. 测试记录写清命令、覆盖及时间；“有测试文件”“加入门禁”“本次实际跑过”分别表述。

## 外部档案索引（不随仓库克隆自动获得）

| 入口 | 内容 |
| --- | --- |
| [游戏主要玩法](../../游戏主要玩法.md) | 用户整理的玩法规格；后续明确确认可覆盖早期条目 |
| [荣耀源码](../../starhome_lz_ry_fcc_source/)、[免费源码](../../starhome_lz_fr_fcc_source/) | 可读 FCC 及来源清单 |
| [荣耀原件](../../starhome_lz_ry_full/)、[荣耀解析成果](../../starhome_lz_ry_full_parsed/) | 下载/FTC/ALE/表、惰性缓存；原目录只用于逆向归档 |
| [地图解析档案](../../starhome_lz_ry_maps_parsed/) | 地图名称、层、导航、跳转图及缺失清单 |
| [缺失构件人工复核](../../starhome_lz_ry_maps_missing_review/index.html) | 当前保存的标记图与逐图 JSON，不是实时官网探测 |
| [城区缺失资源调查](../../city_map_resource_audit/README.md) | files_dir 不是完整全集的历史证据 |

当前入口说明按 2026-09-14 代码校准；原客户端证据、历史评审和旧阶段报告保留其原始时间与范围。
本轮检查本地链接和索引覆盖，不执行外链访问，也不把“链接存在”当作其中每条规则已被运行验证。

## 仓库协作

- [主仓库与素材子模块](./repository_layout.md)：克隆、资源拉取、版本固定、提交顺序和历史拆分。

## 接合器与商城更新（2026-09-15）

- [装配规则、紫晶商城和领域边界](attachments_and_premium_shop.md)
- [升级材料的实际获取缺口](attachment_upgrade_material_audit.md)
