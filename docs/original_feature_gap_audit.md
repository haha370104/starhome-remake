# 原版功能与复刻版缺口清单

核对日期：2026-09-17。复刻代码基线：`415c257`，开始核查时主仓库和素材子模块无未提交改动。
本轮只核对功能并维护文档，不开放新玩法，不修改玩家存档。

## 1. 范围与结论口径

【客户端证据】以本地荣耀版 FCC 为装备、战斗和生产的主要证据；免费版用于现有 HUD、
智脑、佣兵、历练及中枢入口的对照。原档案见[荣耀源码](../../starhome_lz_ry_fcc_source/)
和[免费源码](../../starhome_lz_fr_fcc_source/)，不随主仓库克隆自动获得。

【当前实现】同时检查领域状态、权威服务命令、持久化及 UI 调用；材料、图片、说明文字或
原始配方已导入，不等于相关功能可玩。本轮另用 Godot 只读加载实际日常任务与生产目录。

【待验证】旧客户端存在操作、请求与结果展示，只能确认旧端实现过该功能；不能据此确认
旧服最后是否开放、服务端最终概率、失败损失、奖励公式和所有历史版本的统一规则。
注释掉的旧分支不作为当前版本已开放的证明。

这是按主要功能族整理的差距清单，不是 1220 份 FCC 中所有节日活动、充值礼包和物品的逐项验收。
用户已指定的精简与新增玩法单列，不能把它们自动改回原版。

**最直接的缺口：战车装备开槽/镶嵌确实存在，而复刻目前只接入了柔解剂、晶石的材料链。**
其次是普通装备加工、耐久修理、装置特殊能力，以及多人社交和交易。

## 2. 战车装备开孔、镶嵌、摘取

### 2.1 原客户端已确认的链路

| 环节 | 客户端证据 | 复刻现状 |
| --- | --- | --- |
| 装备能否开槽 | `BaseEquip.m_nExFillister` 标记；NPC 界面还检查具体装备类别和材料 | 没有开槽资格规则和操作 |
| 每个孔的状态 | `m_szflute` 区分未开、已开空孔、已镶嵌；`m_szFlaws` 保存裂纹 | 装备实例、存档和快照没有对应状态 |
| 使用柔解剂开槽 | `EquipFillisterNPC → EquipFillisterWnd → r_EquipFillister`，有材料检查与成功率提示 | 初级/高级柔解剂存在，不能对装备使用 |
| 镶嵌晶石 | 装备菜单/详情的孔槽接收晶石；`OnUpgradeFillister → r_OnUpgradeFillister` | 没有目标选择、扣料、镶嵌和属性计算 |
| 同类属性上限 | 荣耀确认文字明确写“所有装备上，增加同一类属性的晶石只能生效4颗”，瑕疵与明亮同属一类 | 没有这项限制或效果汇总 |
| 摘取与裂纹 | 摘取确认：少于3道裂纹时新增1道；已有3道再摘取会损毁。另有精密锤请求参数 | 没有摘取、裂纹或工具规则 |
| 扩展孔 | 部分装备有第9、10孔的资格与单独窗口/请求 | 没有扩孔系统 |

孔数不能直接定为“所有装备都能开8孔”：基类默认可开数量为8，底层数组容量12，
但具体装备资格、额外第9/10孔和不同开槽材料还有专门分支。数组容量不是玩法上限。
原开槽 NPC 还保留按已开孔数变化的成功率表及特殊装备例外；最终概率需要后续确定复刻规则。

荣耀 `RYRime` 分支目前能直接对应复刻材料链的是六类晶石：

| 属性 | 有瑕疵 | 明亮 |
| --- | ---: | ---: |
| 能量炮攻击 | +3 | +5 |
| 战车生命 | +30 | +50 |
| 战车防御 | +1 | +3 |
| 导弹攻击 | +2 | +4 |
| 能量炮1.5倍暴击几率 | +1% | +2.5% |
| 火箭攻击 | +3 | +6 |

以上为旧端显示值，不是复刻当前有效加成。混用品质时四颗如何取舍、暴击叠加方式、
开槽失败代价和摘取工具的完整规则仍需专门核对，不能仅凭提示文字补出服务端算法。
旧源码还留有其他结晶、升级/组合及特殊装备晶源核分支，不应全部混成同一套晶石规则。

复刻已完成初级柔解剂5→1高级的提炼，以及六类瑕疵晶石5→1明亮的制造，等级均150。
这些是用户确认的配方。**之前新增的人物前缀、特性、1～15级宝石属于服装强化，不能代替战车镶嵌。**

证据入口：

- [装备基类](../../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc)：49～58行状态，332行起菜单，399行起扩孔。
- [加工 NPC](../../starhome_lz_ry_fcc_source/ven/OterNPC_C.fcc)：1231行起开槽资格、预览和请求。
- [开槽窗口](../../starhome_lz_ry_fcc_source/ven/FormClass_ven.fcc)：3317行起 `EquipFillisterWnd`。
- [孔槽与晶石界面](../../starhome_lz_ry_fcc_source/cltobj/stuffclt.fcc)：405行起孔槽，584行起六类数值，705行同类四颗，908行起摘取。
- [晶石请求](../../starhome_lz_ry_fcc_source/mainclient_me.fcc)：2386行起 `OnUpgradeFillister`。
- [摘取请求](../../starhome_lz_ry_fcc_source/ven/MainClient_Me_ven.fcc)：5922行起 `PickOutRime`。
- 当前[战车装备模型](../scripts/domain/items/vehicle_equipment.gd)、[装备存档](../scripts/server/persistence/equipment_slot_record.gd)、[商城/强化路由](../scripts/server/commerce/authoritative_commerce_service.gd)均没有上述流程。
- 已有材料链见[掉落与材料升级](original_monster_drop_balance.md)。

## 3. 装备与战斗：明确未完成的功能

| 功能族 | 原版能确认什么 | 当前边界 | 证据 |
| --- | --- | --- | --- |
| 普通装备属性加工 | 车体生命/输出功率等有独立加工值和上限；其他主装备也有各自升级属性 | 仅普通接合器的逐级强化可执行；不存在通用车、炮、引擎属性加工入口及实例状态 | E1、C1 |
| 萤石、耀石等进阶加工 | `EquipUpgradeNPC`、`EquipProcessNPC` 有装备/材料校验、预览与加工请求 | 不是现有接合器强化的一部分，未接执行链 | E2、C1 |
| 能量石加工/品质与合成 | `EquipStoneNPC`、`EngineStoneNPC` 有相应窗口和请求 | 未接品质变化和相应加工流程 | E2、C1 |
| 护甲精工、额外强化 | `ArmorUpgradeNPC`、`Stren_Master` 有专用装备资格、材料与加工分支 | 护甲可装配和提供当前基础属性，但没有精工/该套强化 | E2、C1 |
| 属性吸取与转移、装备分解 | `ModuleEngineer` 和 `DismemeberNPC` 有实际请求 | 没有吸取/转移模块及分解事务。人物强化自己的转移功能不等于这一套 | E2、C1 |
| 原版服装改良 | `ClothImproveNPC` 有服装/材料加工窗口和请求 | 裁缝制造及原创人物强化已做，仿生纤维等原版改良链未做 | E2、C1 |
| 装备耐久磨损/维护/速修 | 旧端有维护材料、耐久回包和速修箱操作；服装也有维护逻辑 | 当前有耐久保存/展示及 `wear`、`repair` 方法，但生产代码没有调用这两个方法，也没有修理命令。车体生命自维修已经实现，二者不同 | E3、C2 |
| 维修臂对目标维修 | 原端 `Repair(puser)` 校验距离后发 `r_OnRepair` | 点击仅发本地意图并提示尚未开放；没有权威治疗 | E3、C3 |
| 隐身器/雷达与侦测 | `HermitBase`、`RadarBase` 与旧端装置/状态逻辑 | 没有隐身、侦测、反隐战斗链；侦测接合器因此缺少实际用途 | E4、C4 |
| 发生器特殊攻击 | `SubGunBase` 等有发生器类别与特殊作用分支 | 两件发生器的装配规则已做，特殊攻击结算未做；怪物毒胶腐蚀不代表玩家发生器已实现 | E4、C4 |
| 撒玛装备完整能力 | 四件成长属性、聚能穿透、脉冲、核变、吸收等说明/公式 | 保留槽位和表现基础，未接完整品质成长和技能效果 | E5、C5 |
| 奥斯格兰装备 | 成长、祝福、被动、专属符文，以及四件八符文的套装条件 | 未接完整成长/符文镶嵌/套装触发链 | E5、C5 |
| 晶源体装备 | 品质、成长、晶源核镶嵌及加工上限 | 未接完整成长与晶源核流程；不是普通六类晶石开槽 | E5、C5 |
| 中枢控制器 | 免费版有桥接芯片、中枢装备界面、升级请求及效果展示 | HUD 仍提示未开放；将来改成技能点只是用户的可能方向，尚未实现 | E6、C6 |
| 召唤守卫 | 原免费版 HUD 调用 `CreateOneNpc` | 保留原图标，点击提示未开放；这里与用户删掉的“护卫系统”分开统计 | E6、C6 |

## 4. 多人、经济及扩展世界

| 功能族 | 原客户端证据 | 复刻现状 |
| --- | --- | --- |
| 组队 | 邀请、申请、队员操作、队伍信息和服务端请求（E7） | 队伍按钮占位；没有队伍聚合和分配规则 |
| 好友、聊天、私聊 | 好友/仇人页、聊天输入与 `r_OnChat`（E8） | 有当前场景玩家名单；好友、玩家社交操作未开放，缺少聊天通讯链 |
| 玩家间交易 | 双方邀请、放入/移除物品、金币、就绪/确认/取消（E9） | 商人买卖已经有，玩家对玩家交易没有 |
| 银行/仓库 | 存取物品、位置、密码、扩容等请求（E10） | 只有背包，没有独立仓库和存取事务 |
| 信件/留言 | 信件、留言窗口和客户端发送/读取逻辑（E11） | 系统菜单对应入口均为未实现提示 |
| 组织/公会 | 创建、解散、申请、成员权限、职位、敌对关系等请求（E12） | 没有组织状态和权威服务 |
| 城市经营/建设相关 | 城市权限、能源转换、设施/凭证和城市传送管理（E13） | 城区地图可走，不等于城市经营系统已实现；这套管理链未接 |
| PVP、竞技房间 | 原端竞技房间模式、报名/站队、开始/退出、观战状态（E14） | 当前玩家攻击结算针对怪物，没有玩家互伤、PVP模式和竞技赛程。已有 ENet 联机不能等同多人玩法齐全 |
| 原版活动、副本和世界 BOSS 排名 | 历练引用撒玛飞船、机械部队、陨石带BOSS、队长、星际战场；免费版另有副本信息（E15） | 尚无这些完整活动/排名链。现在投放的变异怪/BOSS是用户确认的复刻布怪规则 |
| 太空/飞船玩法 | 独立 `spaceplayer`、飞船装备和操控分支（E16） | 当前以地面战车为可玩范围，未接独立太空战斗与装备成长；不把整套原档案导入当作已完成 |
| 婚姻等关系玩法 | 登记、婚礼服务与牧师 NPC 客户端流程（E17） | 没有对应关系与服务；属于低优先级扩展，不建议因有旧代码就恢复 |

这些多人功能的缺口通过当前服务命令、玩家模型/存档和窗口调用交叉核对；并非仅因找不到同名文件。
本表不把只有名字的拍卖、摆摊等猜测列为已证实功能，也不把旧注释里的 PK 开关当成有效入口。

## 5. 已经有，但范围未覆盖原版

| 功能 | 当前已接 | 未接或不同之处 |
| --- | --- | --- |
| 佣兵任务 | 本轮只读目录加载：495条原始定义中208条可接，73击杀/115物品收集/20金币捐赠；八档、领取/取消/交付、积分累计均有 | 287条未入当前可接池，不代表287种独立功能；原因包括未投放目标、没有完整原料链、活动或排名条件。积分晋升/用途和原帮助里的特定次数额外积分未接 |
| 人物历练 | 10项定义中2项开放：完成10次、20次佣兵后的奖励 | 其余8项依赖指定队长、BOSS排名、星系探索或战场；星系探索入口此前已明确删掉 |
| 智脑 | 自动攻击、近距离拾取、低血自维修、炮导模式 | 自动补给、死亡记录、快捷换装及炮隐/炮雷等原版高级设置未接；需要先有隐身/雷达等基础能力 |
| 生产 | 本轮加载198条可执行目录规则：裁缝65、烹饪31、提炼43、主装备12、附属10、合金22、维护包15 | 单次即时生产，没有原版批量/投入倍率/加工等待。除烹饪外采用门槛达标后100%产出，不能说还原了原服概率；目录可执行不代表每种原料都有可玩获取链 |
| 装备/物品覆盖 | 已接大量原物品、恢复图像、掉落与生产材料 | 柔解剂/晶石、维护包及一些特殊材料没有最终使用流程；注册、能掉落和能消费要分别验收 |
| 系统菜单 | 原版九项菜单图片和点击区域 | 字体/颜色/热键设置、留言、音乐音效设置、帮助、网速测试、信件，甚至该菜单的“退出”目前都调用 `unavailable`。游戏统一字体已做，不等于自定义设置已做 |
| 战斗表现 | 普通弹体、死亡、腐蚀与大部分命中特效已接 | 上轮119怪审计仍有9种命中特效缺可靠对应：4类水晶怪及对应精英、炼狱天灾怒火BOSS；见[专门清单](monster_hit_effect_audit.md) |

生产数字来自当前配方书，不能继续将早期工业说明中的“83条”当成今天的总量。
以上目录查询不启动服务器，不访问日常玩家存档，也不是一次完整游戏流程回归。

## 6. 不计作误漏的用户决定

- 已移除的 HUD 入口：系统消息、系统帮助、VR、护卫系统、场景积分、星系探索、钛晶商城。
  移除的是这些入口；不能因此推断所有相关历史玩法已逐项评审或应重新开放。
- 基地大厅仅保留卖矿商人和战斗训练师；缺少原版加工流程不构成自动恢复其余 NPC 的授权。
- 成就称号、人物前缀/特性/宝石、变异/BOSS投放、矿点补齐、紫晶奖励、每日领取200/完成100、
  新旧接合器各两件及发生器两件、导航小地图等按已确认的复刻设计保留。
- 原版收费许可、充值和历史运营活动不自动纳入本轮待办。

正式身份认证、生产 SQLite 和更完整的经济流水也仍有工程缺口，但属于上线基础设施，
不与上面的原版玩法缺失混为一谈；现有进程内服务器和 ENet 权威链已存在。

## 7. 建议补齐顺序（尚未实施）

用户随后明确暂缓多人交互，当前执行范围和顺序以[非多人玩法补齐计划](pve_completion_plan.md)为准；
下方保留本轮核查时的总体建议。额外追踪确认召唤守卫调用
`dcz/npcclt/npcmeclt.fcc:54 CallRedNameNpc → r_PlayerSoS`，属于反红名救援，随PVP延期。

1. **战车开槽/镶嵌/摘取**：优先让现有柔解剂和晶石有用途；独立于人物强化，包含存档、
   属性计算和卸装恢复，不能只画孔槽窗口。
2. **普通车炮引擎属性加工、耐久维护**：补齐核心成长和维护包消费链；原版成功率、失败损失、
   耐久代价需逐项选定，不能套用接合器价格/升级规则。
3. **维修臂、发生器、隐身/雷达**：先补已装配装备的实际能力，再扩展智脑模式。
4. **中枢与三组特殊装备**：按领域分别建模；它们不是一组通用数值加成。
5. **仓库、队伍、聊天/好友、玩家交易**：根据多人测试需要推进，再接组织、PVP和大型活动。

## 8. 证据索引与复核入口

`E` 为原客户端，`C` 为复刻当前代码；下列行号基于本地2026-09-17档案。

| 编号 | 定位 |
| --- | --- |
| E1 | [equipclt.fcc](../../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc)：2314行 `Upgrade`，2356行输出功率，2525行上限 |
| E2 | [OterNPC_C.fcc](../../starhome_lz_ry_fcc_source/ven/OterNPC_C.fcc)：464萤石加工、584加工、701能量石、1028能量石合成、1373护甲精工、1537强化、1809服装、2173吸取/转移、6351分解 |
| E3 | [client_include.fcc](../../starhome_lz_ry_fcc_source/client_include.fcc)：2383行起目标维修、2492行维护请求；免费版[mainclient_me_ven.fcc](../../starhome_lz_fr_fcc_source/ven/mainclient_me_ven.fcc)：130行起速修及回包；荣耀[mainclient_me.fcc](../../starhome_lz_ry_fcc_source/mainclient_me.fcc)：3541、3667行起服装修复 |
| E4 | [appendequipclt.fcc](../../starhome_lz_ry_fcc_source/cltobj/appendequipclt.fcc)：4行隐身、419行雷达、1540行发生器基类；[当前装配边界](attachments_and_premium_shop.md) |
| E5 | [特殊战车装备证据](glory_special_vehicle_equipment.md)：逐类源文件、公式、符文、技能和套装条件；该文不是完成清单 |
| E6 | 免费版[HUD](../../starhome_lz_fr_fcc_source/dzl/face_addmain_common_dzl.fcc)：116行起召唤守卫、370行起中枢；[FormClass_ven.fcc](../../starhome_lz_fr_fcc_source/ven/FormClass_ven.fcc)：26260行 `PivotControlWnd`；[mainclient_me.fcc](../../starhome_lz_fr_fcc_source/mainclient_me.fcc)：9554行升级请求 |
| E7 | [team_com_c.fcc](../../starhome_lz_ry_fcc_source/jackson/team_com_c.fcc)：245行队伍管理请求、277行邀请、314行回复；[teaminterface.fcc](../../starhome_lz_ry_fcc_source/dl/team/teaminterface.fcc) |
| E8 | [FriendWnd.fcc](../../starhome_lz_ry_fcc_source/ven/FriendWnd.fcc)：好友/仇人及增删窗口；[talkclient.fcc](../../starhome_lz_ry_fcc_source/cltplayer/talkclient.fcc)：315/350行聊天、769行 `TalkTo` |
| E9 | [tradeclt.fcc](../../starhome_lz_ry_fcc_source/cltplayer/tradeclt.fcc)：36行邀请、196～221行回应/取消、360/397行增删物品、421/555行确认、670行金币 |
| E10 | [bank_userclt.fcc](../../starhome_lz_ry_fcc_source/dzl/bank/bank_userclt.fcc)：35行存入、58行取出、149行密码、277行扩容 |
| E11 | [letter.fcc](../../starhome_lz_ry_fcc_source/dl/leaveword/letter.fcc)、[leavewordclt.fcc](../../starhome_lz_ry_fcc_source/lz/leavewordclt/leavewordclt.fcc) |
| E12 | [organize_userctl.fcc](../../starhome_lz_ry_fcc_source/dzl/organize_new/organize_userctl.fcc)：264行起创建/解散/成员/权限请求 |
| E13 | [war_user.fcc](../../starhome_lz_ry_fcc_source/war_city/war_user.fcc)：79、235、699、800、874、950、1203行管理请求 |
| E14 | [spk_com_c.fcc](../../starhome_lz_ry_fcc_source/jackson/pk/spk_com_c.fcc)：260/382行模式、407行规则、425行传送、469～486行参加/开始/退出 |
| E15 | [免费版日常证据](free_experience_and_mercenary_audit.md)、免费版[shortcuttoolbar.fcc](../../starhome_lz_fr_fcc_source/ven/shortcuttoolbar.fcc)：3590行起副本信息 |
| E16 | [spaceplayer](../../starhome_lz_ry_fcc_source/spaceplayer/)、[space_airship_clt.fcc](../../starhome_lz_ry_fcc_source/cltobj/space_airship_clt.fcc) |
| E17 | [OterNPC_C.fcc](../../starhome_lz_ry_fcc_source/ven/OterNPC_C.fcc)：125登记、254婚礼服务、317牧师；[mate_me.fcc](../../starhome_lz_ry_fcc_source/dzl/mate/mate_me.fcc) |
| C1 | [VehicleEquipment](../scripts/domain/items/vehicle_equipment.gd)、[商务路由](../scripts/server/commerce/authoritative_commerce_service.gd)、[生产路由](../scripts/server/manufacturing/authoritative_manufacturing_service.gd)、[玩家操作](../scripts/server/player_panels/authoritative_player_panel_service.gd) |
| C2 | [Equipment](../scripts/domain/items/equipment.gd)：32行 `wear`、38行 `repair`；对全部生产 `scripts/*.gd` 检索没有调用点；耐久赋值只有初始化/映射和这两个方法 |
| C3 | [CombatInteractionController](../scripts/client/gameplay/combat_interaction_controller.gd)：181行起维修臂占位；[权威战斗](../scripts/server/modules/combat/authoritative_combat_module.gd)已有自维修 |
| C4 | [装配规则与未实现效果](attachments_and_premium_shop.md)、[Vehicle](../scripts/domain/players/vehicle.gd)、[权威战斗](../scripts/server/modules/combat/authoritative_combat_module.gd) |
| C5 | [Vehicle](../scripts/domain/players/vehicle.gd)、[VehicleEquipment](../scripts/domain/items/vehicle_equipment.gd)、[EquipmentSlotRecord](../scripts/server/persistence/equipment_slot_record.gd)：无三组特殊成长/符文实例模型和对应技能事务 |
| C6 | [WorldInteractionController](../scripts/client/gameplay/world_interaction_controller.gd)：227行起好友、240行起队伍/守卫/中枢占位；[SystemMenuPanel](../scripts/client/ui/windows/navigation/system_menu_panel.gd)九项均未实现；[场景玩家面板](../scripts/client/ui/windows/navigation/scene_players_panel.gd)社交占位 |
| C7 | [DailyActivityCatalog](../scripts/domain/quests/daily_activity_catalog.gd)、[日常配置](../data/gameplay/quests/daily_activities_v1.json)、[ManufacturingRecipeBook](../scripts/domain/manufacturing/manufacturing_recipe_book.gd)、[ManufacturingRecipe](../scripts/domain/manufacturing/manufacturing_recipe.gd) |

本轮验证：Godot 4.7.2 无头只读加载 ItemCatalog、DailyActivityCatalog、ManufacturingRecipeBook
成功退出，输出208条佣兵、历练2/10及上述7类配方计数。日志在本地缓存
`.godot/feature_gap_audit.log`；运行环境有系统根证书读取提示，目录查询不依赖网络。
未执行完整游戏回归，也未验证原服线上状态。文档本地链接与导航覆盖另由文档门禁检查。
