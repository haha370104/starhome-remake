# 文档导航

更新：2026-09-14。本页是完整文档目录；新对话先读交接，整体 review 再读评审导读。
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
| 游戏应当怎样玩？ | [玩法规格](../../游戏主要玩法.md)，在仓库外的 `outputs/` 中 |
| 开发有哪些硬约束？ | [项目全局约定](../PROJECT_CONTEXT.md) |
| 如何启动和手工验证？ | [仓库 README](../README.md)、[使用说明](../使用说明.md) |
| 独立服务器与离线直连到底共用了什么？ | [双运行模式架构](./runtime_modes_architecture.md) |
| 为什么采用这些边界？ | [技术架构](./technical_architecture.md)，注意目标结构不等于现有目录 |
| 接下来做什么？ | [开发路线图](./development_roadmap.md)，阶段完成只指各自验收范围 |
| 全量资源与可玩内容有什么区别？ | [运行内容与资源包](./runtime_content.md) |

证据优先级：用户确认的玩法/工程约束决定“应该怎样”；当前源码、配置和可复现测试决定
“实际怎样”；逆向文档决定“原客户端有什么证据”。三者有冲突时记录差异，不通过改文案
把实现自动判为正确。历史通过记录不代表当前工作树再次通过。

## 当前模块说明

| 文档 | 责任范围 / 阅读时注意 |
| --- | --- |
| [评审导读](./review_guide.md) | 当前职责图、源码入口、优先级、检查清单与已知缺口 |
| [工程规范](engineering_standards.md) | 分层、状态所有权、组件复用、测试与提交要求 |
| [客户端结构与阅读顺序](client_architecture.md) | 入口拆分、控制器、共享组件、状态链路及本轮验证范围 |
| [技术架构](./technical_architecture.md) | 架构决策、目标依赖、协议和完成定义；含尚未实现的目标设计 |
| [双运行模式架构](./runtime_modes_architecture.md) | 进程边界、启动握手、传输/模拟差异、状态归属、保存与验证 |
| [人物/背包/战车](./player_panels_architecture.md) | Player 聚合、同版本投影、换装事务、背包几何 |
| [装备展示模式](equipment_presentation_modes.md) | 世界、背包、面板三种图像身份和统一装配投影 |
| [自由背包布局](inventory_free_position.md) | 像素占位、拖放、吸附与原生图片尺寸分离 |
| [持久化](./persistence_architecture.md) | 3 秒自动保存、开发文件仓储、revision、SQLite 待接入边界 |
| [技能成长](./skill_progression_architecture.md) | 经验阈值、事件来源、综合等级和技能面板 |
| [地图解析管线](./map_resource_pipeline.md) | FCC/ALE/PKH、碰撞、静态合成、语义遮挡和缺失依赖 |
| [地图驻留与性能](./map_residency_and_performance.md) | 按玩家启停、休眠状态、在途事务、寻路退化及测量范围 |
| [野外怪物种群](./field_monster_populations.md) | 逐图刷怪、历史分布证据与复刻默认、小地图出口 |
| [运行内容与资源包](./runtime_content.md) | 当前地图/动画/物品/配方/矿源数量和完整性边界 |
| [已知内容注册表](./known_content_registry.md) | 身份和来源查询；旧 runtime 映射不能替代新运行目录 |
| [战斗诊断](./combat_diagnostics.md) | JSONL 位置、同一发子弹的跨端关联、复现采集方式 |
| [采矿、主装置与错误文案](mining_equipment_and_player_messages.md) | 装配准入、三秒周期、重启入账身份、两类工程臂 HUD/空点击 |
| [矿物渲染与装备叠层](mineral_rendering_and_equipment_layers.md) | 重复乘色修复、矿源变体、采掘臂帧率与面板层级 |
| [工业制造](industrial_manufacturing.md) | 提炼、主/附属装备、合金和维护包；83 条可执行规则与排除项 |
| [循环任务与训练](repeatable_quests.md) | 四类材料任务、每日五类训练、权威奖励/去重/跨天保存 |
| [底栏导航窗口](bottom_menu_windows.md) | 玩家名单、任务日志、系统菜单、商城 UI 及未实现功能 |
| [系统消息规范](system_message_guidelines.md) | 面向用户中文提示、中央通知和日志分工 |
| [素材目录与 Git](../assets/README.md) | 业务命名、版本白名单、普通 Git/LFS/缓存分工 |
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
