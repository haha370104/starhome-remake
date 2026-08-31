# 全野外怪物种群与小地图传送点

更新：2026-08-31。

## 覆盖范围与证据边界

当前可进入的 810 张地图中，460 张运行定义为 `category: field`，全部启用怪物种群。
其余 350 张城镇、商店、大厅等地图不启用刷怪。按世界和地图代码联合识别，
不同星球的同名 C04 不共享种群或刷新计时器。

| 配置来源 | 地图数 | 含义 |
| --- | ---: | --- |
| 荣耀客户端地图编辑器记录 | 27 | 20 个怪物类、85 条怪物—地图关系全部匹配到数值和素材实体 |
| 既有 D04 首切配置 | 1 | 保留现有四种怪物、属性、被动/反击行为及掉落配置 |
| 明确标记的复刻默认 | 432 | 缺少原始分布证据，暂用奥姆虫、奥姆幼虫、感光质、毒胶，各权重 1 |

这里使用的是此前整理的 `glory_monster_map_relations.json`，而不是一份覆盖全世界的原版服务端刷怪表。
源证据是地图 FCC 中**被注释的 `NpcNewAddress` 编辑器记录**，只能说明历史配置，
不能断言为正式服务器最后使用的分布。当前没有找到另一份独立的“怪物手册”文件。
432 张默认地图不能描述为已经还原原版；之后提供更完整分布时应替换默认配置。

六个世界的野外数：布里星 73、阿斯加德 85、贝特β星 71、德萨星 73、伯雷星 73、索卡星 85。
尚缺原包的四个注册地图不在上述 810 张运行地图中，本次未伪造资源。

## 怪物身份关联修正

旧工具仅通过名字或调色板匹配，漏掉 13 个类，而且普通奥姆虫与仿生奥姆虫共用
`NpcChengChong1.act`，会错误取到后者。现在关联链改为：

`地图怪物类 → npcclt1.fcc 的 m_sNpcName → great/code_string.fcc 中文常量 → npc_catalog 唯一同名实体`

不再以“调色板相同”推断怪物身份；同名多条记录也拒绝自动匹配。
每个匹配保留源类、名称常量及行号，供人工核对。

| 原始怪物类 | 运行怪物 |
| --- | --- |
| Npc成虫1 / 2 | 奥姆虫 / 毒性奥姆虫 |
| Npc幼虫1 | 奥姆幼虫 |
| Npc蠕虫1 / 2 / 3 | 胶虫 / 恶性胶虫 / 血腥的胶虫 |
| Npc铁甲虫1 / 2 / 3 | 甲壳奥姆虫 / 冷酷的甲壳奥姆虫 / 嗜血的甲壳奥姆虫 |
| Npc机甲A1 / 2 / 3 | 撒玛士兵 / 冷酷的撒玛士兵 / 血腥的撒玛士兵 |
| Npc机甲B1 / 2 / 3 | 撒玛卫士 / 残酷的撒玛卫士 / 嗜血的撒玛卫士 |
| NpcLightBall1 / 2 | 感光质 / 低温感光质 |
| NpcSlm2 | 低温毒胶 |
| NpcFire / 自走车 | 熔岩 / 自走车 |

新增种群复用已导入的荣耀版数值及 ALE 动画；没有跨版本借用素材，也没有修改原有
普通毒胶、奥姆幼虫“不攻击”的行为规则。全部地图共使用 21 种怪物，其中普通毒胶来自默认配置。

## 权威刷新与配置入口

- 每图初始 100 只，上限 100；首次加载权威地图实例时生成，并非启动时预建所有野外实例。
- 全图可走区域随机出生，优先满足 96 像素间距，不使用旧编辑器的固定点簇。
- 每 60 秒检查一次：低于 50% 补 20 只，低于 80% 补 10 只，否则补 5 只，始终受上限限制。
- 按物种权重补缺，当前各物种权重相同。怪物生命周期、攻击和死亡仍由服务端领域模型负责，客户端只呈现快照。

配置与生成流程：

1. `data/gameplay/glory/field_population_defaults_v1.json`：无证据地图的默认物种及权重。
2. `tools/build_glory_monster_runtime_catalog.py`：读取地图目录、关系表和名称常量，生成逐图配置；人口上限与补量比例也在此集中定义。
3. `data/gameplay/glory/glory_monster_encounters_v1.json`：生成的 459 张地图配置。
   `distribution_evidence` 区分 `client_editor_placement` / `remake_default`，
   `source_map_id` 保留世界+区域，`confirmed_joins` 保留可追溯的类关联。
4. D04 继续由 `data/gameplay/stage3/d04_encounters_v1.json` 配置覆盖。
5. `python tools/audit_glory_runtime_content.py` 更新运行覆盖清单，分别列示历史证据和默认配置数量。

修改默认权重后执行 `python tools/build_glory_monster_runtime_catalog.py`，再执行审计脚本。
不要只手改生成文件，否则下一次生成会覆盖修改。怪物目录在启动时加载，修改后需重启游戏/服务端。

## 小地图传送点

`ActiveWorldController` 提交地图时通过 HUD 的 `set_map` 传入启用出口，HUD 不扫描服务器状态。
每个出口的 `source_anchor / world_size × minimap_texture_size` 投影到小地图原图。
标记为约 7 像素浅绿色 `×`（RGB 0.65、1、0.7），加深色描边提高可见度。

标记随原图一起滚动、拖动和裁剪；大/小模式不缩放标记，折叠模式不显示。
切换地图会清空旧标记，禁用出口不显示，同一坐标的多目的地只绘制一次。
本次不增加点击标记传送功能，也没有改动传送落点算法。

## 验证入口

- `python tools/tests/test_glory_monster_encounters.py`：名称关联、调色板别名回归、全野外集合、默认配置隔离、无效权重拒绝。
- `tests/server/combat/glory_field_population_test.gd`：加载全部 810 张运行定义检查分类；全部 460 张野外生成种群；六世界抽样真实导航出生与一分钟补怪。
- `tests/server/combat/combat_definition_catalog_test.gd`：D04 行为、数量、战斗和权重补缺回归。
- `tests/client/presentation/combat/glory_ale_monster_presenter_test.gd`：启用物种的站立/移动/攻击三态和八向帧加载。
- `tests/ui/runtime/hud_runtime_smoke_test.gd`、`tests/integration/map_transition_scene_smoke_test.gd`：小地图标记、模式变化及大厅→城区→D04→C04→C03 切换。
