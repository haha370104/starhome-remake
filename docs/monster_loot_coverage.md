# 怪物物品掉落覆盖审计

2026-09-16，使用初始化后的权威目录（含新手覆盖及材料补充表）。

启用刷新物种 47 种，其中 17 种没有物品掉落表；
另外 65 种未投放物种也没有掉落表。外观变体共享物种掉落。

原客户端 `source_drop_candidates` 仅是来源证据，不等于实际运行的 `drops`。
本次列出缺口，没有擅自把未知原始权重换算成掉率，也没有用金币奖励冒充物品掉落。

## D03 与隐形掉落修复

低温毒胶掉中级类胶、低温感光质掉中级能量催化剂，均为 75% 概率、1～3 个。
两者过去只有掉落规则，没有地面表现，导致客户端拒绝创建视图。
本次补齐全部 8 种中高级生物材料与接合器升级碎片的荣耀原图、调色板、地面及背包映射。
仍保留原来的掉率；有掉落表不等于每次击杀必掉。

## 已投放但无物品掉落（17 种普通怪物）

| 物种 | 名称 | 原客户端候选条数 |
| --- | --- | ---: |
| glory_monster_018 | 残酷的撒玛卫士 | 6 |
| glory_monster_020 | 警觉的撒玛近卫军 | 6 |
| glory_monster_028 | 撒玛士兵 | 7 |
| glory_monster_029 | 自走车 | 7 |
| glory_monster_030 | 鱼鳞战车 | 7 |
| glory_monster_031 | 韦德战车 | 13 |
| glory_monster_032 | 撒玛卫士 | 12 |
| glory_monster_034 | 撒玛近卫军 | 12 |
| glory_monster_035 | 冷酷的撒玛士兵 | 13 |
| glory_monster_038 | 警觉的鱼鳞战车 | 13 |
| glory_monster_039 | 血腥的撒玛士兵 | 13 |
| glory_monster_041 | 暴戾的鱼鳞战车 | 11 |
| glory_monster_042 | 嗜血的撒玛卫士 | 12 |
| glory_monster_043 | 暴戾的撒玛近卫军 | 11 |
| glory_monster_044 | 钢锁 | 51 |
| glory_monster_045 | 猛犸战车 | 50 |
| glory_monster_047 | 安格列蛛 | 50 |

## 未投放且无物品掉落

| 物种 | 名称 | 原客户端候选条数 |
| --- | --- | ---: |
| glory_monster_054 | 威猛的水晶吞噬者 | 60 |
| glory_monster_055 | 凶恶的水晶吞噬者 | 60 |
| glory_monster_056 | 嗜血的水晶变异者 | 60 |
| glory_monster_057 | 残忍的水晶变异者 | 60 |
| glory_monster_058 | 狂暴的水晶破坏者 | 60 |
| glory_monster_059 | 冷酷的水晶破坏者 | 60 |
| glory_monster_060 | 威猛的水晶吞噬者(精英) | 60 |
| glory_monster_061 | 凶恶的水晶吞噬者(精英) | 60 |
| glory_monster_062 | 嗜血的水晶变异者(精英) | 60 |
| glory_monster_063 | 残忍的水晶变异者(精英) | 60 |
| glory_monster_064 | 狂暴的水晶破坏者(精英) | 60 |
| glory_monster_065 | 冷酷的水晶破坏者(精英) | 60 |
| glory_monster_067 | 仿生毒胶 | 1 |
| glory_monster_068 | 仿生感光质 | 1 |
| glory_monster_069 | 仿生奥姆虫 | 1 |
| glory_monster_070 | 变异毒胶 | 0 |
| glory_monster_071 | 变异感光质 | 0 |
| glory_monster_072 | 变异奥姆幼虫 | 0 |
| glory_monster_073 | 变异奥姆虫 | 0 |
| glory_monster_074 | 变异低温毒胶 | 0 |
| glory_monster_075 | 变异低温感光质 | 0 |
| glory_monster_076 | 变异毒性奥姆幼虫 | 0 |
| glory_monster_077 | 变异毒性奥姆虫 | 0 |
| glory_monster_078 | 变异恶性毒胶 | 0 |
| glory_monster_079 | 变异恶性感光质 | 0 |
| glory_monster_080 | 变异血腥奥姆幼虫 | 0 |
| glory_monster_081 | 变异胶虫 | 0 |
| glory_monster_082 | 变异罗格当虫 | 0 |
| glory_monster_083 | 变异甲壳奥姆虫 | 0 |
| glory_monster_084 | 变异艾格丝虫 | 0 |
| glory_monster_085 | 变异恶性胶虫 | 0 |
| glory_monster_086 | 变异毒性罗格当虫 | 0 |
| glory_monster_087 | 变异冷酷甲壳奥姆虫 | 0 |
| glory_monster_088 | 变异毒性艾格丝虫 | 0 |
| glory_monster_089 | 变异熔岩 | 0 |
| glory_monster_090 | 变异撒玛近卫军 | 0 |
| glory_monster_091 | 变异撒玛士兵 | 0 |
| glory_monster_092 | 变异骷髅龙 | 0 |
| glory_monster_093 | 变异鱼鳞战车 | 0 |
| glory_monster_094 | 变异撒玛卫士 | 0 |
| glory_monster_095 | 变异韦德战车 | 0 |
| glory_monster_096 | 变异沙蝎 | 0 |
| glory_monster_097 | 恐怖的奥姆幼虫(精英) | 0 |
| glory_monster_098 | 凶猛的奥姆虫(精英) | 0 |
| glory_monster_099 | 狂热的胶虫(精英) | 0 |
| glory_monster_100 | 残暴的罗格当虫(精英) | 0 |
| glory_monster_101 | 暴怒甲壳奥姆虫(精英) | 0 |
| glory_monster_102 | 疯狂的艾格丝虫(精英) | 0 |
| glory_monster_103 | 残忍的熔岩(精英) | 0 |
| glory_monster_104 | 残忍撒玛近卫军(精英) | 0 |
| glory_monster_105 | 残忍的撒玛士兵(精英) | 0 |
| glory_monster_106 | 残忍的骷髅龙(精英) | 0 |
| glory_monster_107 | 残忍的鱼鳞战车(精英) | 0 |
| glory_monster_108 | 残忍的撒玛卫士(精英) | 0 |
| glory_monster_109 | 残忍的韦德战车(精英) | 0 |
| glory_monster_110 | 残忍的沙蝎(精英) | 0 |
| glory_monster_111 | 堕落的毒心虫（BOSS） | 0 |
| glory_monster_112 | 暴走邪恶机甲（BOSS） | 0 |
| glory_monster_113 | 漂浮机甲兵（BOSS） | 0 |
| glory_monster_115 | 蜘蛛邪恶王（BOSS） | 0 |
| glory_monster_116 | 狂暴甲拉格（BOSS） | 0 |
| glory_monster_127 | 炽热重甲王（BOSS） | 0 |
| glory_monster_128 | 炼狱天灾怒火（BOSS） | 0 |
| glory_monster_129 | 电王阿希科瑞尔BOSS | 0 |
| glory_monster_130 | 撒玛议会咆哮者BOSS | 0 |

## 表现完整性

当前 14 种实际掉落物中，缺地面纹理 0 种。

复核命令：先运行 `tools/export_content_supply_audit.gd`，再运行 `python -X utf8 tools/audit_monster_loot_coverage.py`。
