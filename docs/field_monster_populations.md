# 野外怪物种群与小地图传送点

更新：2026-09-01。

## 覆盖范围与证据边界

当前可进入的 810 张地图中，460 张运行定义为 `category: field`，现已全部启用普通怪物种群；
D04 保留首切配置，其余 459 张使用复刻版明确制定的等级和区域生态规则。
另外 350 张城镇、商店、大厅等地图不启用刷怪。按世界和地图代码联合识别，
不同星球的同名 C04 不共享种群或刷新计时器。

| 配置来源 | 地图数 | 含义 |
| --- | ---: | --- |
| 荣耀客户端地图编辑器记录 | 27 | 作为历史存在证据保留，不冒充完整服务器分布表 |
| D04 首切配置 | 1 | 一级区域，保留毒胶、感光质、奥姆幼虫、奥姆虫 |
| 放射等级与区域生态设计 | 459 | 覆盖其余野外图，每图3–5种普通怪物 |

这里使用的是此前整理的 `glory_monster_map_relations.json`，而不是一份覆盖全世界的原版服务端刷怪表。
源证据是地图 FCC 中**被注释的 `NpcNewAddress` 编辑器记录**，只能说明历史配置，
不能断言为正式服务器最后使用的分布。当前没有找到另一份独立的“怪物手册”文件。
因此生成配置将原始证据与复刻设计分开记录：`supporting_client_evidence` 只保存原始编辑器线索，
实际刷怪使用 `design_inferred_radial_ecology`，以后恢复服务端表时可以逐图替换而不混淆证据。

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
普通毒胶、奥姆幼虫“不攻击”的行为规则。

## 十级进度与区域生态

普通怪按用户确认的粗粒度进度划为十级。二级合并低温与毒性，三级合并恶性与血腥；
四级固定胶虫、甲壳奥姆虫、温和的罗格当虫和温和的艾格丝虫。后续等级继续遵守
同族前缀强弱顺序。完整机器可读列表位于生成配置的 `progression_tiers`。

按[官网怪物介绍](https://jz.ftxjjy.com/MonsterIntro.shtml)的分类转成六种生态主题：`slime`（毒胶系）、`photosensitive`（感光系）、
`om`（奥姆系）、`mutant_insect`（变异昆虫系）、`sama`（撒玛系）、`mechanical`（机械系）。
地图按相对城市出口的方向选择一到三个主题，不从全局等级池无差别抽取。

- 主网格以 D04 为一级中心，八方向每向外一圈增加一级，最高到七级。
- `YM/KL/MTY/BB/YL` 等三乘三区域以 C03 为八级中心，直线相邻为九级，角落为十级。
- 每张地图从当前危险级和相邻低一级选择3–5种普通怪，普通怪硬上限为5种。
- 精英怪、野外首领和BOSS以后使用独立附加组，不计入普通怪五种上限。
- 同一地图普通怪物权重暂时相同；选择结果由地图ID稳定决定，不会因重启随机换种。

## 权威刷新与配置入口

- 所有野外地图初始 200 只、上限 200；首次有玩家进入并加载权威地图实例时生成，
  并非启动时预建全部460张野外实例。
- 全图可走区域随机出生，优先满足 96 像素间距，不使用旧编辑器的固定点簇。
- 每 60 秒检查一次：低于 50% 补 40 只，低于 80% 补 20 只，否则补 10 只，始终受上限限制。
- 按物种权重补缺，当前各物种权重相同。怪物生命周期、攻击和死亡仍由服务端领域模型负责，客户端只呈现快照。

配置与生成流程：

1. `tools/build_glory_monster_runtime_catalog.py`：读取地图目录、关系表和名称常量，生成十级怪物表和459张设计种群；人口上限、生态和补量比例也在此集中定义。
2. `data/gameplay/glory/glory_monster_encounters_v1.json`：生成的逐图配置。
   `distribution_evidence` 为 `design_inferred_radial_ecology`，`source_map_id` 保留世界+区域，
   `supporting_client_evidence` 与 `confirmed_joins` 保留可追溯的原始客户端线索。
3. D04 继续由 `data/gameplay/stage3/d04_encounters_v1.json` 配置覆盖。
4. `python tools/audit_glory_runtime_content.py` 更新运行覆盖清单，分别列示历史证据地图和设计覆盖数量。

修改关系表解析或人口策略后执行 `python tools/build_glory_monster_runtime_catalog.py`，再执行审计脚本。
不要只手改生成文件，否则下一次生成会覆盖修改。怪物目录在启动时加载，修改后需重启游戏/服务端。

## 小地图传送点

`ActiveWorldController` 提交地图时通过 HUD 的 `set_map` 传入启用出口，HUD 不扫描服务器状态。
每个出口的 `source_anchor / world_size × minimap_texture_size` 投影到小地图原图。
标记为约 7 像素浅绿色 `×`（RGB 0.65、1、0.7），加深色描边提高可见度。

标记随原图一起滚动、拖动和裁剪；大/小模式不缩放标记，折叠模式不显示。
切换地图会清空旧标记，禁用出口不显示，同一坐标的多目的地只绘制一次。
本次不增加点击标记传送功能，也没有改动传送落点算法。

## 验证入口

- `python tools/tests/test_glory_monster_encounters.py`：名称关联、十级表、放射距离、五种上限及历史证据保留。
- `tests/server/combat/glory_field_population_test.gd`：加载全部810张运行定义，检查460张野外图均有种群、普通怪不超过5种，并抽样真实导航出生与一分钟补怪。
- `tests/server/combat/combat_definition_catalog_test.gd`：D04 行为、数量、战斗和权重补缺回归。
- `tests/client/presentation/combat/glory_ale_monster_presenter_test.gd`：启用物种的站立/移动/攻击三态和八向帧加载。
- `tests/ui/runtime/hud_runtime_smoke_test.gd`、`tests/integration/map_transition_scene_smoke_test.gd`：小地图标记、模式变化及大厅→城区→D04→C04→C03 切换。
