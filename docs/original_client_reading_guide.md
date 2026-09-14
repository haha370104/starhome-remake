# 原客户端代码阅读与证据追踪

更新：2026-09-14。目标：从用户说的一个名字、一张图或一个现象，找到原端真实调用链，
再落实到复刻模型，而不是凭文件名猜用途。解密步骤另见 [FCC 恢复](fcc_resource_recovery.md)。

## 1. 输入层级和边界

| 层 | 本工作区入口 | 阅读原则 |
| --- | --- | --- |
| 启动脚本 | [荣耀启动解密目录](../../ourgamestart_ry_decrypted/) | 看版本、更新根、DefLocMaping、CtrlFilesDir，不把启动脚本当全资源表 |
| 可读客户端源码 | [荣耀 FCC](../../starhome_lz_ry_fcc_source/)、[免费 FCC](../../starhome_lz_fr_fcc_source/) | 原件只读，文本通常已有 UTF-8 副本；先确认版本及生效分支 |
| 解包的表/配置 | [FTC 资源](../../starhome_lz_ry_full_parsed/ftc_resources/)、[catalogs](../../starhome_lz_ry_full_parsed/catalogs/) | 汇总是工具结果；缺字段/奇怪值要回到 decoded 和 expanded 原表 |
| 图像与帧 | [ALE 图集](../../starhome_lz_ry_full_parsed/ale_sprites/) | sheet 必须连同 frames.json、ACT、原始 ALE 阅读 |
| 引擎容器 | 本机 `D:/Program Files/FancyBoxII Games/newsystem*` 的 exe/dll | 包含动画、坐标、渲染、解包等引擎语义，不是可以忽略的空壳 |
| 新工程 | `scripts/domain`、`scripts/server`、`scripts/client`、`data`、`tools` | 将来源字段在目录边界转换为业务语义；不把原客户端当可直接移植的可信服务端 |

1220 份可读 FCC、8 份 XY20 是保存的恢复报告口径，不代表拿到原服全源码。
`0003` 是历史静态定位后只读内存确认的 companyid；不是暴力破解出的账号密码。
DLL 偏移与调用约定绑定版本，后续批解不需登录；不要把历史进程地址写死到新进程。

## 2. 推荐的逆向阅读顺序

### A. 先定位中文字符串与资源身份

在仓库根执行（只读）：

```powershell
rg -n '新兵能量炮|奥姆|感光质|毒胶|任务日志' ../starhome_lz_ry_fcc_source -g '*.fcc'
rg -n 'String6832|class repair|class Repair' ../starhome_lz_ry_fcc_source/cltobj -g '*.fcc'
rg -n 'm_sBaseSrc|m_sDlgSrc|m_sMoveSrc|m_sEquipFaceFile' ../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc
```

中文可能只出现在 `StringNNNN` 的定义文件，实体引用的是符号；先找符号再反查使用者。
合成的名字、别名和继承来的默认属性可能不在当前文件。图集目录名只能定位引用，不证明怪物种类。
JSON 可能单行数 MB，先读结构/筛选 ID，不用无截断 `rg` 打印整份目录。

### B. 沿继承链读“定义”和“行为”

例：`BaseEquip → Repair → repair`；`equipcltclass.fcc` 多为实例类型参数，
`equipclt.fcc` 定义公共行为。只读叶子类会漏 Location、装备类别、HUD 图标及事件回调。

每次至少记录：

1. 叶类、基类及生效版本/分支。
2. 初始化默认值、OnInit/OnCreate 参数覆盖。
3. OnEquip/穿脱/状态切换引起的属性和图像变化。
4. 发送给服务器的字段，与服务器回调覆盖的字段。
5. 资源路径拼接、相对 `$` 基准目录、source class 与原始行号。

### C. 分开配置、客户端预测和服务器结果

`Send`/对象远程调用表示意图；伤害/生命/经验更新回调才说明客户端如何消费结果。
客户端先显示爆炸或减少能量可能只是预测。怪物 `npcinfo`、编辑器刷怪表只能证明客户端保存了这些值，
不能当作原服最终动态状态或完整掉落概率。

配置要查 decoded 和 expanded 两层：例如炎帝制造线索在
`MainEquip/mainequip.txt.cab`，早期仅查汇总表会漏掉；`AbstractList` 的数量另在 `NeedAmount` 列。
原表名字也可能写错，优先用产物类和稳定 ID 解析，不按中文显示名强行配对。

### D. 最后追图像组合与引擎语义

图像左上角 = 逻辑锚点 + 每帧 origin；宽高/alpha bbox 不等于脚点或装备槽中心。
动作帧是否八向分块、同一层是否有独立站立/走动/攻击、换色是否 ACT/另一套 ALE，需要逐项确认。
武器 HUD、背包、世界、面板图是不同字段，不能用一张图到处缩放。

遇到 `PlayAni(...,60,...)` 先查所有调用、变量命名和引擎实现；当前采掘臂按 60 ms 帧间隔解释，
证据强度见 [采矿说明](mining_equipment_and_player_messages.md)，不能把语义推断写成已验证机器码计时。

## 3. 按问题选择源码入口

下列路径相对荣耀 FCC 源码根；免费例外显式说明。源码行号会随物化方式变化，优先检索符号。

| 问题 | 原版阅读入口 / 关键字 | 复刻专题 |
| --- | --- | --- |
| 装备数值、三个展示模式 | `cltobj/equipcltclass.fcc`、`cltobj/equipclt.fcc`，BaseEquip、ChangeEquipStyle、m_sBaseSrc/m_sDlgSrc/m_sMoveSrc | [素材关系](asset_relationships.md)、[装备显示](equipment_presentation_modes.md) |
| 人物服装叠加 | `cltobj/clothclt.fcc`、`clothcltclass.fcc`，Wear、m_nLayer；`menupart_main_style.fcc` | [面板逆向](combat_and_equipment_ui_reverse_engineering.md) |
| 战车/怪物血条、能量条 | `menupart_main.fcc` 的 healthbar/energybar；`cltobj/equipclt.fcc`；`mainclient_char.fcc` 回调 | [状态条与面板](combat_and_equipment_ui_reverse_engineering.md) |
| 维修/采矿/主槽图标 | `cltobj/equipclt.fcc` 的 Repair、CollecTor、PlayCollectAle、m_sEquipFaceFile；`cltplayer/repair.fcc` | [采矿](mining_equipment_and_player_messages.md)、[特殊装备](glory_special_vehicle_equipment.md) |
| 怪物动作、调色板、阴影 | `npcbasecltmain.fcc`、`npcclt1.fcc`，沿具体物种引用回查动作类、ACT | [素材关系](asset_relationships.md)、[怪物检查](monster_overlay_shadow_check.md) |
| 地图与出口 | 地图 FCC 的 AddImg/AddImgEx/PKH/SetGoFlag；`transport.fcc` 的 transport/transport2/ChangeSvr | [地图管线](map_resource_pipeline.md) |
| HUD | 免费版 `menupart_main_common_dzl.fcc`；TopMenu、base_ctrlpad、WeaponImg | [免费 HUD](free_hud_rendering.md) |
| 用户列表/任务日志/商城 | 荣耀 `chatctrl_main.fcc`；免费 `bool/role/userrolewnd.fcc`、`hp/adorn/adorn_ui.fcc` | [底栏窗口](bottom_menu_windows.md) |
| 商店、生产与任务 | NPC 调用入口→原表产品类/材料列→发送命令；不要从机器图片猜配方权限 | [商店](weapon_merchant_ui_reverse.md)、[工业](industrial_manufacturing.md)、[任务](repeatable_quests.md) |
| 子弹/受击/死亡 | 发射器→本地弹体→网络消息→生命回调→死亡/阴影清理 | [弹道证据](projectile_hit_and_monster_state_reverse_engineering.md)、[日志](combat_diagnostics.md) |

免费版只能用于获准 UI 或只读研究；研究找到相似素材不等于授权跨版本导入。

## 4. 缺失资源如何查

1. 从生效 FCC 引用得到精确逻辑路径，确认注释和分支，不猜文件名。
2. 查荣耀 raw、parsed、official_lazy_cache；注意大小写、相对路径、GBK 字节与 UTF-8 的区别。
3. 本地确缺时，离线地图工具才向荣耀同路径更新地址尝试一次，校验文件头及实际可解析性。
4. 成败均留审计；无清单哈希的补抓只能证明取到该内容，不能声称与历史版本相同。
5. 已知缺失保留在人工标记图里，不找相似资源填洞，不将 files_dir 全下载称为历史官网全集。

使用 [official_asset_recovery.py](../tools/map_pipeline/official_asset_recovery.py)，参数和缓存策略见
[FCC 恢复](fcc_resource_recovery.md) 与 [地图解析](map_resource_pipeline.md)。本轮未联网重探这些旧地址。

## 5. 何时需要原引擎/动态分析

先穷尽文本的定义、继承、调用点、数据表和图集元数据。仍无法解释坐标、通行位、时基或混色时，
对匹配 DLL 做只读静态分析；记录文件 SHA-256、位数、导出名和偏移，不复用不同版本绝对地址。
动态调试仅在该轮任务授权范围内进行；优先用户自己的原客户端与可复现本地动作，
不上传内存，不提取无关凭据，不为了读脚本绕过登录/账号权限。
若荣耀原服不能登录，报告限制，使用可验证资源和静态证据，不能声称动态对齐已完成。

## 6. 写回文档的最小证据卡

```text
问题/实体/版本：
原文件与类/函数：
有效分支及继承链：
相关字段/参数、原始数值：
ALE/ACT/frames 原点与帧规则：
客户端预测与服务器回调边界：
证据等级（客户端/用户确认/复刻规则/待验证）：
复刻配置 ID、领域类、权威用例、视图入口：
测试和实际结果；未覆盖内容：
```

原文档/用户截图保留不覆盖；修正旧结论加日期和理由。行号、历史日志和截图只能是证据引用，
不能成为唯一知识载体或运行时硬编码。
