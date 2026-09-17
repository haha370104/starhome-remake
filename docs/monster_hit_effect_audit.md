# 怪物命中特效全量审计

更新：2026-09-17。范围是怪物命中玩家战车的效果，不包含怪物死亡动画、玩家武器爆炸或未投放素材。

## 结果与证据边界

当前119种怪物：103种有显式命中映射，7种毒胶使用已有独立腐蚀效果，9种原服映射尚未核实。
上轮已修复15种感光质/奥姆幼虫映射，本轮再补88种，导入22段免费版原图。
检查旧npcinfo字段时，112种普通受击流程中有47条资源缺失、65条指向本体/本体原型动画。
这说明“资源能加载”不能作为“命中特效正确”的证据；当前运行目录已完全停止读取该旧字段。

原版 `mainclient_me.fcc:1394 OnNpcmyattack`、`mainclient_char.fcc:1287 OnNpcattack`
接收服务器指定的效果索引，再用 `global/golbalstring.fcc:m_szNPCBulletAvi` 创建 `laserblast`。
`effect.fcc:6` 定义按66ms逐帧播放一次，位于受击目标当时脚点、层级加一，之后不跟随移动战车。

映射分为两类证据：旧类中的效果声明（部分已注释），以及弹体PD/爆炸BZ的明确家族配对。
两者都无法证明停服服务器当时下发的具体索引或调色板；本表是依据客户端证据建立的复刻配置，
不声称103种均已还原服务器逐怪绑定。机械族旧类声明878/887，而全局表另有904；这轮采用
类声明的共享闪光并保留该不确定性，没有仅凭全局数组顺序替换成904。
水晶吞噬者使用YS_b弹体，因此按该弹体家族映射；其他水晶怪及炼狱Boss未发现足够的绑定证据。

用户批准“用免费版补吧”后导入22段原图。甲壳奥姆虫源848共7帧，荣耀官网精确原路径404；
其他新增图的荣耀本地档案没有字节相同副本（未把未探测的官网路径写成404）。已有荣耀图继续复用。
导入不缩放、不重画；保留原始RGBA、逐帧原点、66ms时序。来源、SHA-256、授权、映射依据均写入
[显式配置](../data/gameplay/glory/monster_hit_effects_v1.json)和对应素材目录的import_metadata.json。

## 已接入的效果家族

“旧类”表示按原类声明；“家族推断”表示以同家族PD/BZ配对。变异、精英和Boss按其实际弹体归属，
不按显示名猜测（例如凶猛的奥姆虫精英实际复用了幼虫弹体）。

| 效果族 | 怪物数 | 素材来源 | 映射证据 | 原图预览/来源 |
| --- | ---: | --- | --- | --- |
| orb_and_larva_impact | 15 | 荣耀版 | 旧类声明 | 已有ALE资源；路径见显式配置 |
| om_adult_impact | 9 | 免费版 | 旧类声明 | [帧图](../assets/monsters/om_adult/shared/effects/impact/frames.png) / [来源](../assets/monsters/om_adult/shared/effects/impact/import_metadata.json) |
| gel_worm_impact | 6 | 免费版 | 旧类声明 | [帧图](../assets/monsters/gel_worm/shared/effects/impact/frames.png) / [来源](../assets/monsters/gel_worm/shared/effects/impact/import_metadata.json) |
| armored_om_impact | 6 | 免费版 | 旧类声明 | [帧图](../assets/monsters/armored_om/shared/effects/impact/frames.png) / [来源](../assets/monsters/armored_om/shared/effects/impact/import_metadata.json) |
| logdang_mild_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/logdang_mild/shared/effects/impact/frames.png) / [来源](../assets/monsters/logdang_mild/shared/effects/impact/import_metadata.json) |
| logdang_alert_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/logdang_alert/shared/effects/impact/frames.png) / [来源](../assets/monsters/logdang_alert/shared/effects/impact/import_metadata.json) |
| logdang_violent_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/logdang_violent/shared/effects/impact/frames.png) / [来源](../assets/monsters/logdang_violent/shared/effects/impact/import_metadata.json) |
| aiges_mild_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/aiges_mild/shared/effects/impact/frames.png) / [来源](../assets/monsters/aiges_mild/shared/effects/impact/import_metadata.json) |
| aiges_alert_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/aiges_alert/shared/effects/impact/frames.png) / [来源](../assets/monsters/aiges_alert/shared/effects/impact/import_metadata.json) |
| aiges_violent_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/aiges_violent/shared/effects/impact/frames.png) / [来源](../assets/monsters/aiges_violent/shared/effects/impact/import_metadata.json) |
| skull_dragon_mild_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/skull_dragon_mild/shared/effects/impact/frames.png) / [来源](../assets/monsters/skull_dragon_mild/shared/effects/impact/import_metadata.json) |
| skull_dragon_alert_impact | 1 | 免费版 | 家族推断 | [帧图](../assets/monsters/skull_dragon_alert/shared/effects/impact/frames.png) / [来源](../assets/monsters/skull_dragon_alert/shared/effects/impact/import_metadata.json) |
| skull_dragon_violent_impact | 3 | 免费版 | 家族推断 | [帧图](../assets/monsters/skull_dragon_violent/shared/effects/impact/frames.png) / [来源](../assets/monsters/skull_dragon_violent/shared/effects/impact/import_metadata.json) |
| sand_scorpion_impact | 3 | 免费版 | 家族推断 | [帧图](../assets/monsters/sand_scorpion/shared/effects/impact/frames.png) / [来源](../assets/monsters/sand_scorpion/shared/effects/impact/import_metadata.json) |
| angler_spider_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/angler_spider/shared/effects/impact/frames.png) / [来源](../assets/monsters/angler_spider/shared/effects/impact/import_metadata.json) |
| floating_soldier_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/floating_soldier/shared/effects/impact/frames.png) / [来源](../assets/monsters/floating_soldier/shared/effects/impact/import_metadata.json) |
| machinegun_soldier_impact | 1 | 免费版 | 家族推断 | [帧图](../assets/monsters/machinegun_soldier/shared/effects/impact/frames.png) / [来源](../assets/monsters/machinegun_soldier/shared/effects/impact/import_metadata.json) |
| mechanical_soldier_impact | 1 | 免费版 | 家族推断 | [帧图](../assets/monsters/mechanical_soldier/shared/effects/impact/frames.png) / [来源](../assets/monsters/mechanical_soldier/shared/effects/impact/import_metadata.json) |
| heavy_mech_impact | 2 | 免费版 | 家族推断 | [帧图](../assets/monsters/heavy_mech/shared/effects/impact/frames.png) / [来源](../assets/monsters/heavy_mech/shared/effects/impact/import_metadata.json) |
| blazing_armor_king_impact | 1 | 免费版 | 家族推断 | [帧图](../assets/monsters/blazing_armor_king/shared/effects/impact/frames.png) / [来源](../assets/monsters/blazing_armor_king/shared/effects/impact/import_metadata.json) |
| electric_king_impact | 1 | 免费版 | 家族推断 | [帧图](../assets/monsters/electric_king/shared/effects/impact/frames.png) / [来源](../assets/monsters/electric_king/shared/effects/impact/import_metadata.json) |
| many_legged_impact | 3 | 免费版 | 家族推断 | [帧图](../assets/monsters/many_legged/shared/effects/impact/frames.png) / [来源](../assets/monsters/many_legged/shared/effects/impact/import_metadata.json) |
| berserk_beetle_impact | 6 | 免费版 | 家族推断 | [帧图](../assets/monsters/berserk_beetle/shared/effects/impact/frames.png) / [来源](../assets/monsters/berserk_beetle/shared/effects/impact/import_metadata.json) |
| mechanical_flash_impact | 27 | 荣耀版 | 旧类声明 | 已有ALE资源；路径见显式配置 |

## 逐怪状态

“待核实”会安全地不播放普通爆炸，绝不把本体动画贴到战车上；这9种仍属于未完成的受击表现。
“独立毒雾”沿用喷吐、地面云和附着持续效果，不能误标为缺少一次性爆炸。

| NPC | 名称 | 当前命中效果 | 素材来源 |
| --- | --- | --- | --- |
| toxic_gel_standard | 毒胶 | 独立毒雾 | 荣耀版 |
| photosensitive_orb_standard | 感光质 | orb_and_larva_impact | 荣耀版 |
| om_larva_standard | 奥姆幼虫 | orb_and_larva_impact | 荣耀版 |
| om_adult_standard | 奥姆虫 | om_adult_impact | 免费版 |
| glory_npc_005 | 低温毒胶 | 独立毒雾 | 荣耀版 |
| glory_npc_006 | 低温感光质 | orb_and_larva_impact | 荣耀版 |
| glory_npc_007 | 毒性奥姆幼虫 | orb_and_larva_impact | 荣耀版 |
| glory_npc_008 | 毒性奥姆虫 | om_adult_impact | 免费版 |
| glory_npc_009 | 恶性毒胶 | 独立毒雾 | 荣耀版 |
| glory_npc_010 | 恶性感光质 | orb_and_larva_impact | 荣耀版 |
| glory_npc_011 | 血腥的奥姆幼虫 | orb_and_larva_impact | 荣耀版 |
| glory_npc_012 | 血腥的奥姆虫 | om_adult_impact | 免费版 |
| glory_npc_013 | 胶虫 | gel_worm_impact | 免费版 |
| glory_npc_014 | 温和的罗格当虫 | logdang_mild_impact | 免费版 |
| glory_npc_015 | 甲壳奥姆虫 | armored_om_impact | 免费版 |
| glory_npc_016 | 温和的艾格丝虫 | aiges_mild_impact | 免费版 |
| glory_npc_017 | 恶性胶虫 | gel_worm_impact | 免费版 |
| glory_npc_018 | 残酷的撒玛卫士 | mechanical_flash_impact | 荣耀版 |
| glory_npc_019 | 警觉的罗格当虫 | logdang_alert_impact | 免费版 |
| glory_npc_020 | 警觉的撒玛近卫军 | mechanical_flash_impact | 荣耀版 |
| glory_npc_021 | 冷酷的甲壳奥姆虫 | armored_om_impact | 免费版 |
| glory_npc_022 | 警觉的艾格丝虫 | aiges_alert_impact | 免费版 |
| glory_npc_023 | 血腥的胶虫 | gel_worm_impact | 免费版 |
| glory_npc_024 | 暴戾的罗格当虫 | logdang_violent_impact | 免费版 |
| glory_npc_025 | 嗜血的甲壳奥姆虫 | armored_om_impact | 免费版 |
| glory_npc_026 | 暴戾的艾格丝虫 | aiges_violent_impact | 免费版 |
| glory_npc_027 | 温和的骷髅龙 | skull_dragon_mild_impact | 免费版 |
| glory_npc_028 | 撒玛士兵 | mechanical_flash_impact | 荣耀版 |
| glory_npc_029 | 自走车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_030 | 鱼鳞战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_031 | 韦德战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_032 | 撒玛卫士 | mechanical_flash_impact | 荣耀版 |
| glory_npc_033 | 警觉的骷髅龙 | skull_dragon_alert_impact | 免费版 |
| glory_npc_034 | 撒玛近卫军 | mechanical_flash_impact | 荣耀版 |
| glory_npc_035 | 冷酷的撒玛士兵 | mechanical_flash_impact | 荣耀版 |
| glory_npc_036 | 熔岩 | om_adult_impact | 免费版 |
| glory_npc_037 | 暴戾的骷髅龙 | skull_dragon_violent_impact | 免费版 |
| glory_npc_038 | 警觉的鱼鳞战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_039 | 血腥的撒玛士兵 | mechanical_flash_impact | 荣耀版 |
| glory_npc_040 | 沙蝎 | sand_scorpion_impact | 免费版 |
| glory_npc_041 | 暴戾的鱼鳞战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_042 | 嗜血的撒玛卫士 | mechanical_flash_impact | 荣耀版 |
| glory_npc_043 | 暴戾的撒玛近卫军 | mechanical_flash_impact | 荣耀版 |
| glory_npc_044 | 钢锁 | mechanical_flash_impact | 荣耀版 |
| glory_npc_045 | 猛犸战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_046 | 机器爬虫 | mechanical_flash_impact | 荣耀版 |
| glory_npc_047 | 安格列蛛 | angler_spider_impact | 免费版 |
| glory_npc_048 | 悬浮兵 | floating_soldier_impact | 免费版 |
| glory_npc_049 | 机枪兵 | machinegun_soldier_impact | 免费版 |
| glory_npc_050 | 机械兵 | mechanical_soldier_impact | 免费版 |
| glory_npc_051 | 重机甲 | heavy_mech_impact | 免费版 |
| glory_npc_052 | 多足怪 | many_legged_impact | 免费版 |
| glory_npc_053 | 狂暴甲 | berserk_beetle_impact | 免费版 |
| glory_npc_054 | 威猛的水晶吞噬者 | berserk_beetle_impact | 免费版 |
| glory_npc_055 | 凶恶的水晶吞噬者 | berserk_beetle_impact | 免费版 |
| glory_npc_056 | 嗜血的水晶变异者 | **待核实** | 未选择 |
| glory_npc_057 | 残忍的水晶变异者 | **待核实** | 未选择 |
| glory_npc_058 | 狂暴的水晶破坏者 | **待核实** | 未选择 |
| glory_npc_059 | 冷酷的水晶破坏者 | **待核实** | 未选择 |
| glory_npc_060 | 威猛的水晶吞噬者(精英) | berserk_beetle_impact | 免费版 |
| glory_npc_061 | 凶恶的水晶吞噬者(精英) | berserk_beetle_impact | 免费版 |
| glory_npc_062 | 嗜血的水晶变异者(精英) | **待核实** | 未选择 |
| glory_npc_063 | 残忍的水晶变异者(精英) | **待核实** | 未选择 |
| glory_npc_064 | 狂暴的水晶破坏者(精英) | **待核实** | 未选择 |
| glory_npc_065 | 冷酷的水晶破坏者(精英) | **待核实** | 未选择 |
| glory_npc_067 | 仿生毒胶 | 独立毒雾 | 荣耀版 |
| glory_npc_068 | 仿生感光质 | orb_and_larva_impact | 荣耀版 |
| glory_npc_069 | 仿生奥姆虫 | om_adult_impact | 免费版 |
| glory_npc_070 | 变异毒胶 | 独立毒雾 | 荣耀版 |
| glory_npc_071 | 变异感光质 | orb_and_larva_impact | 荣耀版 |
| glory_npc_072 | 变异奥姆幼虫 | orb_and_larva_impact | 荣耀版 |
| glory_npc_073 | 变异奥姆虫 | om_adult_impact | 免费版 |
| glory_npc_074 | 变异低温毒胶 | 独立毒雾 | 荣耀版 |
| glory_npc_075 | 变异低温感光质 | orb_and_larva_impact | 荣耀版 |
| glory_npc_076 | 变异毒性奥姆幼虫 | orb_and_larva_impact | 荣耀版 |
| glory_npc_077 | 变异毒性奥姆虫 | om_adult_impact | 免费版 |
| glory_npc_078 | 变异恶性毒胶 | 独立毒雾 | 荣耀版 |
| glory_npc_079 | 变异恶性感光质 | orb_and_larva_impact | 荣耀版 |
| glory_npc_080 | 变异血腥奥姆幼虫 | orb_and_larva_impact | 荣耀版 |
| glory_npc_081 | 变异胶虫 | gel_worm_impact | 免费版 |
| glory_npc_082 | 变异罗格当虫 | logdang_mild_impact | 免费版 |
| glory_npc_083 | 变异甲壳奥姆虫 | armored_om_impact | 免费版 |
| glory_npc_084 | 变异艾格丝虫 | aiges_mild_impact | 免费版 |
| glory_npc_085 | 变异恶性胶虫 | gel_worm_impact | 免费版 |
| glory_npc_086 | 变异毒性罗格当虫 | logdang_alert_impact | 免费版 |
| glory_npc_087 | 变异冷酷甲壳奥姆虫 | armored_om_impact | 免费版 |
| glory_npc_088 | 变异毒性艾格丝虫 | aiges_alert_impact | 免费版 |
| glory_npc_089 | 变异熔岩 | om_adult_impact | 免费版 |
| glory_npc_090 | 变异撒玛近卫军 | mechanical_flash_impact | 荣耀版 |
| glory_npc_091 | 变异撒玛士兵 | mechanical_flash_impact | 荣耀版 |
| glory_npc_092 | 变异骷髅龙 | skull_dragon_mild_impact | 免费版 |
| glory_npc_093 | 变异鱼鳞战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_094 | 变异撒玛卫士 | mechanical_flash_impact | 荣耀版 |
| glory_npc_095 | 变异韦德战车 | mechanical_flash_impact | 荣耀版 |
| glory_npc_096 | 变异沙蝎 | sand_scorpion_impact | 免费版 |
| glory_npc_097 | 恐怖的奥姆幼虫(精英) | orb_and_larva_impact | 荣耀版 |
| glory_npc_098 | 凶猛的奥姆虫(精英) | orb_and_larva_impact | 荣耀版 |
| glory_npc_099 | 狂热的胶虫(精英) | gel_worm_impact | 免费版 |
| glory_npc_100 | 残暴的罗格当虫(精英) | logdang_violent_impact | 免费版 |
| glory_npc_101 | 暴怒甲壳奥姆虫(精英) | armored_om_impact | 免费版 |
| glory_npc_102 | 疯狂的艾格丝虫(精英) | aiges_violent_impact | 免费版 |
| glory_npc_103 | 残忍的熔岩(精英) | om_adult_impact | 免费版 |
| glory_npc_104 | 残忍撒玛近卫军(精英) | mechanical_flash_impact | 荣耀版 |
| glory_npc_105 | 残忍的撒玛士兵(精英) | mechanical_flash_impact | 荣耀版 |
| glory_npc_106 | 残忍的骷髅龙(精英) | skull_dragon_violent_impact | 免费版 |
| glory_npc_107 | 残忍的鱼鳞战车(精英) | skull_dragon_violent_impact | 免费版 |
| glory_npc_108 | 残忍的撒玛卫士(精英) | mechanical_flash_impact | 荣耀版 |
| glory_npc_109 | 残忍的韦德战车(精英) | mechanical_flash_impact | 荣耀版 |
| glory_npc_110 | 残忍的沙蝎(精英) | sand_scorpion_impact | 免费版 |
| glory_npc_111 | 堕落的毒心虫（BOSS） | many_legged_impact | 免费版 |
| glory_npc_112 | 暴走邪恶机甲（BOSS） | heavy_mech_impact | 免费版 |
| glory_npc_113 | 漂浮机甲兵（BOSS） | floating_soldier_impact | 免费版 |
| glory_npc_114 | 被遗忘的爬虫（BOSS） | mechanical_flash_impact | 荣耀版 |
| glory_npc_115 | 蜘蛛邪恶王（BOSS） | angler_spider_impact | 免费版 |
| glory_npc_116 | 狂暴甲拉格（BOSS） | berserk_beetle_impact | 免费版 |
| glory_npc_127 | 炽热重甲王（BOSS） | blazing_armor_king_impact | 免费版 |
| glory_npc_128 | 炼狱天灾怒火（BOSS） | **待核实** | 未选择 |
| glory_npc_129 | 电王阿希科瑞尔BOSS | electric_king_impact | 免费版 |
| glory_npc_130 | 撒玛议会咆哮者BOSS | many_legged_impact | 免费版 |

## 防回归与本轮验证

2026-09-18 P4复查：9个缺口仍为水晶变异者/破坏者四种及其四种精英、炼狱天灾怒火。
`OnNpcmyattack`/`OnNpcattack` 的效果索引来自服务端参数；现有NPC表的 `hit_effect`
仍不足以证明这个索引，部分值实际上指向身体动画。故本期不更改这9项映射。
另已找到怪物的 `COnAddMagicEff`/`COnClearMagicEff` 原版入口，发生器三类持续状态的
动画已接通，详见[P4装置台账](pve_devices.md)；持续状态和普通弹体命中分别处理。

- `GloryMonsterPresentationCatalog` 不再沿用npcinfo的旧hit_effect字段，只有显式配置可以提供普通爆炸。
- `monster_hit_presentation_test.gd` 通过真实快照入口逐怪播放103种效果，检查位置、层级、逐帧推进、
  终结弹体、单次播放、重放去重、晚到开始、落空、切图清理，以及9种未核实项/7种腐蚀排除。
  119种每项都必须有映射、独立腐蚀或未核实记录，新增怪物漏配会使回归失败。已纳入客户端总门禁。
- 本轮通过：命中1174项、原攻击表现66项、死亡表现12项；正式入口零警告，客户端架构门禁通过。
- `python -X utf8 tools/import_monster_hit_effects.py --check` 对22段动画逐像素、原点、时序与来源哈希校验通过。
- 使用真实Godot OpenGL渲染确认甲壳奥姆虫爆炸覆盖在当前战车脚点上，原图合集也完成视觉检查。
- 未运行整套游戏回归，未改动存档、权威伤害或掉落逻辑。
- 全仓函数注释检查存在商城、背包、循环任务及其测试的既存失败；本次修改的两个GDScript单独检查通过，
  未将全仓注释门禁记为通过，也没有在这次素材修复中修改无关模块。
