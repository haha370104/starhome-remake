# 代码评审导读

核对日期：2026-09-14。文档整理前基线 HEAD：`fa2e54b`；同时核对当前工作树的源码与配置。
随后已完成客户端职责拆分；当前入口与本轮实测范围见 [客户端架构](client_architecture.md)。
此处其他模块的评审清单仍不代表逐行审计或全量游戏回归已经完成。
新对话先读 [项目交接](project_handoff.md)；该页记录未纳入文档提交的业务改动和外部档案边界。

## 1. 先看结论

2026-09-17 P1 新增[战车加工](vehicle_workshop.md)：审查孔槽资格、跨装备同类上限、裂纹堆叠身份、
失败扣料/损毁确认、满包摘取回滚，以及加工快照进入真实战斗和存档的链路。客户端回归 75/75。

工程已从单大厅原型扩展为共享权威服的多地图可玩基础：移动/切图、怪物战斗、掉落拾取、
人物与战车装配、技能成长、自维修和采矿均有运行代码及测试入口。
商店买卖、循环/训练任务、裁缝/烹饪/工业制造已有权威结算链路。
2026-09-15新增[背包操作与食品效果](inventory_item_actions.md)：审查数量守恒、同类冷却、在线/离线计时、
战斗资源捕获与提交后热更新，食品时钟由独立 `AuthoritativeFoodRuntime` 编排。
但它还不是可直接部署的完整网游：正式身份认证、SQLite 适配器、经济幂等流水及
持久化世界状态仍有缺口。全量素材和配方注册也不代表全部业务可玩。

建议先看“状态在哪、谁能改、失败怎么收尾”，最后再看面板像素和资源细节。
2026-09-16 毒胶持续腐蚀的领域、权威快照及表现边界见[弹道与腐蚀第9.5节](projectile_hit_and_monster_state_reverse_engineering.md#95-毒胶喷吐与持续腐蚀2026-09-16)；
普通怪物无掉落名单和隐形材料修复见[掉落覆盖审计](monster_loot_coverage.md)。
2026-09-17 怪物受击动画漏接、免费版补图与剩余9项未证实绑定见[命中特效全量审计](monster_hit_effect_audit.md)。
2026-09-17 对原版装备、战斗、社交和生产的横向对照见[原版功能缺口核查](original_feature_gap_audit.md)。
该核查的历史基线尚未实现战车开槽；后续P1已交付，人物原创强化仍另行统计。
该核查同时记录源码入口及当前只读目录实测：佣兵208条、历练2/10、七类生产配方198条，不是全流程验收。
用户随后将多人交互延期；顺序、边界与当前进展见[非多人玩法补齐计划](pve_completion_plan.md)。
P0/P1/P2及P3多个子项已交付；[记忆模块](equipment_memory.md)新增五类提取转移，审查
`EquipmentMemoryTransfer`、`InventoryTransformation`、`EquipmentMemoryService` 与四个同名测试，
重点是跨实例原子性、失败载荷销毁和目标上限校验。P3整体尚未完成。
如果只做第一轮 review，优先读第 3 节 A—D，再看第 5 节风险表。

## 2. 当前真实运行关系

```text
main_hall.tscn / main_hall.gd                  dedicated_server.tscn
  ├─ LocalPlayerController（预测和移动）                  │
  ├─ ActiveWorldController（活动地图）                    │
  ├─ 世界交互 / 切图 / 战斗控制器                        │
  ├─ 世界表现 / HUD / GameWindowManager                  │
  ├─ PlayerPanelSession → CurrentPlayer : Player         │
  └─ ClientMultiplayerSession                           │
       └─ ClientTransportEndpoint                       │
            ├─ InProcessAuthoritativeTransport ─┐       │
            └─ NetworkTransportEndpoint / ENet ─┴─ AuthoritativeServer
                                                    ├─ SessionRegistry
                                                    ├─ AuthoritativeMapRegistry
                                                    │    └─ 活跃 MapInstance
                                                    │         ├─ 移动/导航
                                                    │         ├─ 战斗/怪物/掉落
                                                    │         └─ 采矿
                                                    ├─ PlayerPanelService → Player 聚合
                                                    ├─ Commerce / Quest / Manufacturing 用例
                                                    └─ AutosaveService → Repository
                                                         └─ 开发文件仓储
```

客户端与服务端复用模型/规则代码，不共享同一个可变权威对象。客户端 `CurrentPlayer` 是
当前操作者的权威快照投影；其他玩家有各自实体/视图，并非所有玩家共用一个单例。
进程内模式替换传输和进程边界，仍运行同一服务器；当前两种模式均由服务端物理帧驱动。
它不等于真实网络时序已经全部验收。

当前目录没有照抄技术架构中的目标树。实际入口如下：

| 目录 | 当前职责 |
| --- | --- |
| `scripts/domain/` | 物品/玩家/怪物/矿源模型、装备与技能规则、目录查询 |
| `scripts/network/` | 契约、验证、序列门禁和两种传输 |
| `scripts/server/` | 会话、地图模拟、玩法结算、面板用例、保存 |
| `scripts/client/` | 本地控制、网络会话、地图切换、世界表现及游戏窗口 |
| `scripts/maps/`、`navigation/` | 地图定义、入口/出口、路由、落点、寻路 |
| `scripts/characters/`、`npcs/`、`world/`、`ui/` | 既有 Node 表现层与 HUD；不都是领域代码 |
| `scripts/content/` | 内容包挂载、纹理/帧数据按需读取 |
| `data/`、`assets/` | 规则/索引/来源数据与图片/资源包；不是玩家数据库 |
| `tools/`、`tests/` | 离线恢复导入、审计门禁与分层回归 |

## 3. 按模块 review

### A. 充血模型与“同一个玩家”（最高优先级）

先读[面板与聚合说明](./player_panels_architecture.md)，再顺序读：

- [Player](../scripts/domain/players/player.gd)：背包、服装、战车、技能的一致性根。
- [GameItem](../scripts/domain/items/item.gd)、[Equipment](../scripts/domain/items/equipment.gd)、
  [ItemCatalog](../scripts/domain/items/item_catalog.gd)：定义与实例分离、类型实例化、耐久和三种展示来源。
- [Inventory](../scripts/domain/inventory/inventory.gd)、[CharacterEquipment](../scripts/domain/players/character_equipment.gd)、
  [PlayerVehicle](../scripts/domain/players/vehicle.gd)、[VehicleLoadout](../scripts/domain/players/vehicle_loadout.gd)：容器和固定槽位。
- [CurrentPlayer](../scripts/client/state/current_player.gd)、[PlayerStateMapper](../scripts/server/persistence/player_state_mapper.gd)、
  [PlayerPanelProjector](../scripts/shared/player_panel_projector.gd)：持久化、网络快照与对象之间的转换。

检查重点：

- [ ] 同一物品用 `instance_id` 维持身份；落地/入包/装备改变容器，而不是 UI 另造一份属性。
- [ ] 跨进程只有相同业务身份，不要求同一内存指针；跨容器转移不能复制物品或丢失耐久。
- [ ] 面板裸模与场景衣服都读 `CharacterEquipment`；战车面板和战斗是否使用同一装配结果。
- [ ] `CurrentPlayer.apply_bundle()` 在无效快照时是否能保留旧完整状态，同一 revision 才一起发布。
- [x] 纯面板投影器已移到 `scripts/shared`，客户端不再直接依赖服务器目录；共享依赖方向已纳入门禁。
- [ ] `Dictionary` 仍广泛存在，不能认为已完全收紧为类型契约；重点看配置加载/协议边界以外的裸字段。

测试：[充血模型](../tests/domain/player_rich_model_test.gd)、
[面板服务事务](../tests/server/player_panels/player_panel_service_test.gd)、
[面板运行](../tests/ui/runtime/player_panels_runtime_test.gd)。

### B. 存档、事务与身份（最高优先级）

先读[持久化说明](./persistence_architecture.md)。
代码：[AuthoritativeServer.open_session](../scripts/server/authoritative_server.gd)、
[SessionRegistry](../scripts/server/session_registry.gd)、
[AutosaveService](../scripts/server/persistence/authoritative_autosave_service.gd)、
[PlayerStateRepository](../scripts/server/persistence/player_state_repository.gd)、
[FilePlayerStateRepository](../scripts/server/persistence/file_player_state_repository.gd)、
[面板应用服务](../scripts/server/player_panels/authoritative_player_panel_service.gd)。
配置：[ServerConfig](../scripts/server/server_config.gd)、[SQL migration](../data/server/persistence/migrations/)。

- [ ] 新会话仍分配 `player.N`，连接顺序不能作为多人账号归属；没有认证前不能开放公网。
- [ ] 每 3 秒保存的是服务器聚合；换装/拾取提交失败不得先成功回包或消除地面物品。
- [ ] 自动保存与经济命令是否覆盖彼此的新状态；乐观 revision、隔离副本与回滚是否贯穿调用链。
- [ ] 拾取/采矿同时修改玩家聚合和地图实体，审查提交顺序、崩溃窗口、重复消息和断线重试。
- [ ] 文件仓储不是 SQLite；真实 SQLite 驱动、适配器、幂等回执和备份恢复仍需完成。
- [ ] 地图休眠保留状态只限当前服务端进程，不能当成怪物/掉落/矿源的重启恢复。

测试：[仓储与迁移](../tests/server/persistence/player_state_persistence_test.gd)、
[3 秒保存及重载](../tests/server/persistence/authoritative_autosave_test.gd)、面板服务事务测试。

### C. 传输、移动预测与切图（最高优先级）

先读[双运行模式架构](./runtime_modes_architecture.md)，再看[技术架构 §2、§6](./technical_architecture.md)。
2026-09-17 移动开炮重点核对[移速及炮口同步](combat_diagnostics.md#2026-09-17-移动途中开炮的坐标同步)：
静止快照也必须提供装备移速，旧 tick 不回退速度，客户端跨拐点不丢距离；确认发射只校准
可见炮口，不能平移权威终点、修改命中或回写玩家位置。
野外出口另须核对[地图构建产物](map_resource_pipeline.md)：动画组件正确不代表静态图集已
排除旧箭头，全野外审计必须同时覆盖独立目录及内容包，实际渲染验证位于战车下方。
代码：[LocalPlayerController](../scripts/client/gameplay/local_player_controller.gd)、
[LocalMovementPredictor](../scripts/client/network/local_movement_predictor.gd)、
[ClientMultiplayerSession](../scripts/client/network/client_multiplayer_session.gd)、
[进程内传输](../scripts/network/transport/in_process_authoritative_transport.gd)、
[ENet 传输](../scripts/network/transport/network_transport_endpoint.gd)、
[网络契约](../scripts/network/contracts/)、[ActiveWorldController](../scripts/client/world/active_world_controller.gd)。

- [ ] 两个传输最终都到 `dispatch_transport_command()`；本地调试没有直接改伤害、背包或存档的旁路。
- [ ] 预测、输入确认、路线完成是不同事件；收到旧快照不能把移动中的玩家反复拉回。
- [ ] 只有本地控制器写移动状态；世界视图不能和预测器各推进一套位置。
- [ ] 初次加载屏在存档目标地图提交前保持显示；切图失败恢复旧图，晚到旧图事件不能污染新图。
- [ ] 协议绑定真实 peer 会话；拒绝伪造实体、越权目标、旧序号、非法坐标/类型和错误地图实例。

测试：[进程内完整链路](../tests/integration/in_process_authoritative_transport_test.gd)、
[客户端状态接缝](../tests/integration/client_state_seam_characterization_test.gd)、
[场景切图](../tests/integration/map_transition_scene_smoke_test.gd)、
[真实 ENet 双客户端](../tools/run_enet_integration.ps1)、[真实 ENet 切图](../tools/run_enet_map_transition_integration.ps1)。
仍应人工/自动补验带延迟与抖动的并发战斗，不能以本机无延迟测试替代。

### D. 战斗、怪物、掉落、采矿与成长

先读[技能](./skill_progression_architecture.md)、[种群](./field_monster_populations.md)、
[战斗诊断](./combat_diagnostics.md)。
代码：[地图实例](../scripts/server/authoritative_map_instance.gd)、
[战斗模块](../scripts/server/modules/combat/authoritative_combat_module.gd)、
[MonsterLifecycle](../scripts/domain/combat/monster_lifecycle.gd)、
[ProjectileSweep](../scripts/domain/combat/projectile_sweep.gd)、
[DropTable](../scripts/domain/combat/drop_table.gd)、
[采矿模块](../scripts/server/modules/mining/authoritative_mining_module.gd)、
[SkillBook](../scripts/domain/players/skill_book.gd)。

配置从 [data/gameplay](../data/gameplay/) 进入：`stage3/` 是最初精修配置，`glory/` 是全量扩展；
目录名表示演进来源，不代表还存在两套离线/联机服务器。

- [ ] 怪物主动/反击/不攻击由领域规则决定；游荡采用个体错峰（默认首次0.05～5秒、后续3.75～6.25秒），补怪和唤醒不重新同步；返巢锁定与失败寻路退避不能相互打架。
- [ ] 车身移动与炮口攻击方向独立；开火不取消移动。客户端提前爆炸只改变表现，不发放伤害/经验。
- [ ] 死亡、掉落、拾取、采矿周期和经验每次只结算一次；经验按有效伤害/真实移动/有效产出发放。
- [ ] 自维修来自底盘能力与装备加成，维修等级用于准入；不是旧的固定 5 点加等级公式。
- [ ] 刷怪分布、掉落概率、矿源分布中的复刻默认没有伪装成原服数值。
- [ ] 配方可查询不等于均可制造；核对 AuthoritativeManufacturingService 的可执行子集。
- [ ] 商店、任务已有服务端用例，但须审查身份、revision、奖励唯一性和崩溃重试，不能据此宣称生产级经济完成。

新增阅读入口：[工业生产](industrial_manufacturing.md)、[循环任务/训练](repeatable_quests.md)、
[采矿与工程臂](mining_equipment_and_player_messages.md)、
[AuthoritativeCommerceService](../scripts/server/commerce/authoritative_commerce_service.gd)、
[RepeatableQuestService](../scripts/server/commerce/repeatable_quest_service.gd)、
[AuthoritativeManufacturingService](../scripts/server/manufacturing/authoritative_manufacturing_service.gd)。

测试：[战斗模块](../tests/server/combat/authoritative_combat_module_test.gd)、
[D04 权威链路](../tests/integration/d04_authoritative_combat_test.gd)、
[全野外种群](../tests/server/combat/glory_field_population_test.gd)、
[采矿服务端](../tests/server/mining/authoritative_mining_server_test.gd)、
[怪物寻路](../tests/navigation/monster_route_planner_test.gd)。

### E. 地图、遮挡、资源与性能

先读[地图解析](./map_resource_pipeline.md)、[地图驻留](./map_residency_and_performance.md)、
[运行内容](./runtime_content.md)。
代码：[MapDefinitionLoader](../scripts/maps/map_definition_loader.gd)、
[路由](../scripts/maps/runtime_map_route_resolver.gd)、
[落点解析](../scripts/maps/map_transition_landing_resolver.gd)、
[地图注册表](../scripts/server/authoritative_map_registry.gd)、
[SemanticSceneLayer](../scripts/world/semantic_scene_layer.gd)、
[传送点素材目录](../scripts/client/world/map_transition_marker_catalog.gd)、
[内容挂载](../scripts/content/runtime_content_bootstrap.gd)。

- [ ] 碰撞来自导航数据，不从图片 alpha 猜；源入口号、可达落点和传送点素材方向分别解析。
- [ ] 静态图层重合验证和角色遮挡是两种验收；楼梯踏板/扶手使用可复用资产 profile，不写世界坐标补丁。
- [ ] 人体、衣服、翅膀按整体角色脚点排序；as1—as8 与 jt 各用原绑定帧序，不能用方向猜素材替换。
- [ ] 只有有人或有待结算事务的图继续模拟；休眠后回图不白送满血怪或满矿。
- [ ] ZIP 挂载、帧索引缓存、纹理加载与地图模拟驻留是不同层，分别测量内存/CPU/GPU。
- [ ] 新全量资源包仍存在原始命名泄漏，见第 5 节；不能因为打包进 ZIP 就豁免工程规范。

测试：[语义遮挡](../tests/world/semantic_scene_depth_smoke_test.gd)、
[导航](../tests/navigation/diamond_navigation_smoke_test.gd)、
[地图驻留](../tests/server/map_residency_test.gd)、
[全量地图包](../tests/maps/glory_full_map_pack_test.gd)、
[内容完整性](../tests/domain/content/runtime_content_completeness_test.gd)。

### F. UI、角色/NPC 表现与工程可读性

先读[免费 HUD](./free_hud_rendering.md)、[面板逆向](./combat_and_equipment_ui_reverse_engineering.md)、
[素材关联](./asset_relationships.md)。
代码：[HallHud](../scripts/ui/hall_hud.gd)、[GameWindowManager](../scripts/client/ui/windows/game_window_manager.gd)、
[WorldCharacter](../scripts/characters/world_character.gd)、
[NpcBase 领域类](../scripts/domain/npcs/npc_base.gd)、[NpcWorldView](../scripts/npcs/npc_base.gd)。

- [ ] 窗口放大增加地图范围，HUD 固定像素；技能面板为非模态游戏窗口。
- [ ] 物品原图尺寸、占用矩形和面板展示图不是同一概念；掉落、背包、面板选择同一定义的不同视图。
- [ ] 角色/战车/怪物阴影、底部血条、悬浮名称、伤害飘字按原证据分别验收。
- [ ] NPC 巡逻目前是客户端环境表现，不承担经济权威；未来任务/交易不可直接加在 Node 回调里结算。
- [ ] 具名函数中文 `##` 注释说明作用、每个参数、返回值与抽象边界；模板式“执行该操作”不能算高质量说明。

测试：[HUD 运行](../tests/ui/runtime/hud_runtime_smoke_test.gd)、面板运行测试、
[怪物悬浮名](../tests/client/presentation/combat/monster_hover_name_test.gd)、
[掉落实体表现](../tests/client/presentation/combat/ground_loot_world_controller_test.gd)。

## 4. 推荐贯穿阅读的三条调用链

1. **装备衣服**：面板意图 → 会话/传输 → 面板服务 → 隔离 Player 换装 → 持久提交 →
   同 revision 三快照 → CurrentPlayer → 人物窗口和世界衣服一起变化。
2. **移动中开炮并拾取**：移动预测继续 → 能力意图 → 权威弹道/怪物生命 →
   死亡/地面物品 → 拾取校验 → 背包提交成功 → 地面消失 → 技能/综合等级更新。
   沿线检查每一步失败、重发、切图时谁保留状态。
3. **重启后进上次地图**：打开开发仓储 → 会话绑定角色 → 恢复 Player → 按需创建目标地图 →
   预载/原子提交 → 关闭加载屏 → 原地图无人且结清事务后休眠。
   特别区分“角色存档恢复”和“整个世界重启恢复”。

## 5. 当前已知缺口与 review 优先级

以下是文档/源码对照发现或明确保留的债务，不是这次已经修好的功能。

| 优先级 | 事实 / 风险 | 后续 review 的完成标准 |
| --- | --- | --- |
| P0（部署前） | `open_session` 按顺序分配 `player.N`；无正式账户认证 | 身份归属稳定、不能因连接顺序读到别人的角色 |
| P0（生产经济前） | 已有经济玩法但仍使用开发文件仓储；SQLite 端口/SQL 不等于适配器 | 真驱动事务、幂等回执、备份及异常重启恢复 |
| P1 | 聚合、地图中的战车状态、客户端投影各有副本 | 明确每一阶段写入者，换装/受伤/保存不覆盖彼此 |
| P1 | 客户端入口已拆分；服务端 facade 和权威战斗模块仍集中多种职责 | 后续按服务端状态所有权和失败边界继续拆分 |
| P1 | 全量精灵索引/包仍保留历史命名债务；旧报告曾计 500 个引用 | 生成器、包内路径和索引一起审计/迁移，不放宽门禁；旧数量不作本轮测量结果 |
| P1 | 总门禁仍未覆盖全部测试；本轮组件测试和架构检查已接入 | 补全量内容、落点等覆盖；完整清单以检查脚本为准 |
| P1 | 432 张野外采用基础四怪复刻默认；463 项物品素材缺失 | 持续保留来源/缺失标记，具体地图/物品逐项验收 |
| P2 | Dictionary、Node 动态建树、低信息函数注释仍多 | 在 R4—R8 中按模块收紧，不能声称已完成纯类型化重构 |

资源数字为保存的完整性清单口径，不是长期固定指标。
详见 [运行内容说明](./runtime_content.md)。

## 6. 验证入口与本次验证范围

统一门禁在仓库根执行：

```powershell
./tools/run_project_checks.ps1 -GodotExecutable 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
```

它会执行暂存变更规模、LFS、客户端架构、注释检查、Godot 导入、入口警告检查、脚本测试、
真实 ENet 双客户端/重连/切图及资源来源审计。会生成 `.godot/` 缓存/日志，部分步骤调用导入器；
不把它当成纯只读命令。测试清单以[脚本本身](../tools/run_project_checks.ps1)为准。

当前未被总门禁显式列入的代表性测试包括全量内容完整性、完整地图包、传送落点、
ALE 仓库、全量怪物动画及每日训练。采矿已接入，仍可按模块单独运行，例如：

```powershell
& 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/server/mining/authoritative_mining_server_test.gd
```

本次只核对文档链接、入口存在性、测试清单及关键配置/代码，不重新宣称门禁全绿。
文档入口检查：`python -X utf8 tools/check_documentation_links.py`。
尤其现有命名违规未处理，不能因为历史 ENet 或警告检查通过就视为可提交/可发布。

建议 review 产出按 A—F 分模块记录：问题、状态所有者、复现、预期契约、测试缺口。
不要先重写逆向文档；先确定当前实现与证据/需求究竟在哪一步分叉。
