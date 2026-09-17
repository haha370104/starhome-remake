# 运行内容与资源包

文档校准：2026-09-14。本文补足早期“只导入大厅与四种怪物”之后的全量扩展状态。
下表是当前保存的完整性清单快照，并未在本轮重新生成；后续工业材料/生产目录等扩展需另查配置。

## 1. 三类目录不要混用

| 层级 | 入口 | 能证明什么 |
| --- | --- | --- |
| 已知身份/证据注册 | [known_content_registry_v1.json](../data/content/known_content_registry_v1.json) | 原端存在的身份、名称和来源关系；不是最新启用列表 |
| 可装载运行目录 | [完整性清单](../data/content/glory_runtime_content_manifest_v1.json)、[地图运行索引](../data/content/glory_map_runtime_index_v1.json) | 定义/动画已注册并可被运行层查找；不保证全部原服玩法已还原 |
| 服务端实际启用 | [玩法配置](../data/gameplay/)、地图目录与地图实例 | 哪张图生成什么、如何计算；需同时检查来源标记和测试 |

内容清单是生成时的审计快照，不是实时健康探针。`KnownContentRegistry` 中旧 runtime 映射的
4 怪/14 物品/9 地图口径不能与新运行目录简单相加或当成当前总数。

## 2. 当前数量与缺口

以下数字来自上述完整性清单，不是逐地图手工验收结果：

| 内容 | 当前口径 | 不能据此声称 |
| --- | --- | --- |
| 地图 | 814 个来源注册，810 可装载，4 个缺原包 | 810 张都有独立美术、所有边/遮挡均人工验收 |
| 动画 | 13,888 个解码 ALE + 81 怪物 ACT 变体 + 25 矿物 ACT 变体 = 13,994 条运行动画 | 原始 ALE 在运行时现场解密，或每个动画都已接入玩法 |
| 怪物 | 119 个数值定义；460 张野外启用种群 | 119 种都已投放；当前种群使用 21 种 |
| 刷怪证据 | 27 图客户端编辑器历史关系、1 图 D04 精修、432 图复刻默认 | 拿到了原服务端全世界最终刷怪表 |
| 物品 | 1,284 个运行定义，其中 1,270 个生成扩展；463 项缺荣耀素材 | 每项都可购买/掉落/合成/展示全部视图 |
| 配方 | 346 条：本地制造 123、制造 128、升级 80、拆解 15 | 服务端生产/升级/拆解事务已实现 |
| 矿源 | 35 种定义；27 张有客户端分布证据，28 张运行启用 | 所有地图都有矿、世界矿量已存数据库 |

四个缺原包注册为 `map:nft_bt/blackroom`、`map:nft_bt/yzzl`、
`map:nft_ds/roomsvr3`、`map:nft_sk/yzzl`。这些是来源注册标识，不是推荐给业务代码拼接的路径。
场景构件缺失另见地图解析产物/缺失审计，不能与“整张地图缺包”混为一类。

城区入口以 `data/maps/yian_harbor_city.json` 为准；在早期八张室内图之外，已接入提炼厂二/三层、
美容店、兵工厂和独立的宇航中心定义。二/三层存在空间复用的复刻限制，不能把多层入口数量
等同于独立原版美术。化工厂入口按用户要求不保留；花店/科研等外部目标仍须由路由验证，
配置出现 `external:true` 不表示已有可进入地图。室内资源继续按需加载。

可执行生产不是上表 346 条原始配方的直接计数：现有裁缝/烹饪目录与工业目录共同被
`ManufacturingRecipeBook` 消费；工业目录有 83 条可执行记录、7 条明确排除项。
商店与四类材料任务、五类每日训练也已接入权威用例，详情见
[工业制造](industrial_manufacturing.md)、[任务](repeatable_quests.md)。

本轮读取仓库外 `starhome_lz_ry_maps_missing_review/missing_scene_review.json`：保存的快照为
49 张有缺失构件的唯一地图、298 个缺失摆放、25 种唯一资源，其中 11 个锚点在画布外。
这不是 4 张缺整包地图，也不是“814 个来源注册只解析了 497 个”；来源分支注册、唯一地图输出、
正式运行 ID 是不同口径。人工确认入口见 [标记图目录](../../starhome_lz_ry_maps_missing_review/index.html)。

## 3. 加载链路

1. [RuntimeContentBootstrap](../scripts/content/runtime_content_bootstrap.gd) 一次挂载地图、
   精灵、怪物调色板和矿物调色板目录声明的 ZIP。
2. [RuntimeContentPackCatalog](../scripts/content/runtime_content_pack_catalog.gd) 校验目录并挂载；
   [RuntimeTextureLoader](../scripts/content/runtime_texture_loader.gd) 在需要时读纹理。
3. [AleSpriteRepository](../scripts/content/ale_sprite_repository.gd) 查逻辑引用、帧描述和图集页，
   保留帧/页缓存。这里的 ALE 名称表示来源格式，运行时消费的是已解码内容。
4. [地图预载器](../scripts/client/presentation/client_map_preloader.gd) 准备地图 bundle，
   [ActiveWorldController](../scripts/client/world/active_world_controller.gd) 成功后才替换活动地图。
5. 服务端通过 `ensure_runtime_map()` 按玩家进入装载导航和种群。挂载全部包不意味着
   同时实例化全部地图或加载全部纹理；休眠规则见[地图驻留](./map_residency_and_performance.md)。

## 4. 修改与再生成入口

- 地图离线恢复：[map_pipeline](../tools/map_pipeline/)，详细步骤见[地图解析管线](./map_resource_pipeline.md)。
- 地图包：[build_glory_map_content_packs.py](../tools/build_glory_map_content_packs.py)。
- 精灵包：[build_glory_sprite_content_packs.py](../tools/build_glory_sprite_content_packs.py)。
- 物品、怪物、采矿分别由 `tools/build_glory_*_runtime_catalog.py` 生成。
- 横向完整性清单：[audit_glory_runtime_content.py](../tools/audit_glory_runtime_content.py)。

这些是生成器，不是无副作用的查看命令；变更时先核对脚本参数、输入和输出。
原端目录/哈希只能进入来源字段，正式资源必须按业务命名。当前全量精灵包存在命名债务，
需要同时修生成器、ZIP 内部路径及索引；不得只改索引导致失联，也不得关闭来源/命名门禁。

## 5. Git 与复现边界

包位于 `assets/content_packs/`，由 Git LFS 管理；解码后的巨量松散文件与原客户端全集
不作为仓库业务目录。克隆后先拉取 LFS 实体，再让 Godot 导入；仅有指针无法运行地图。
规则见[素材管理](../assets/README.md)。离线再生成仍依赖工作区外部源档案，克隆仓库并不等于
具备全部逆向输入；运行所需包和开发所需档案必须分别管理。

## 2026-09-17 已批准的跨版本恢复索引

在荣耀基础及调色板索引之后，`AleSpriteRepository` 合并 `recovered_sprite_runtime_index_v1.json`。
已批准恢复188个精确引用，合计14182条；原完整性清单仍是历史生成快照，不能拿其463项原始缺失数字当实时缺口。
初始15项位于素材子模块的业务目录，新增173项位于恢复内容包；元数据与来源审计分开；同名路径不自动回退，既有荣耀资源不能被覆盖。
[恢复与全量检索表](cross_release_asset_recovery.md) 区分用户已批准接入、可用候选、历史已补齐与仍缺失。

2026-09-17 追加：用户授权的188条跨版本素材已全部接入，包含173条新增引用、加工石原图、6个弹体绑定与交易中心3处动态屏幕。来源、未恢复项和重建方式见 [跨版本恢复](cross_release_asset_recovery.md)。
