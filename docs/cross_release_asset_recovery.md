# 历史缺失素材的跨版本检索与恢复

日期：2026-09-17。用户授权使用已预览的四套免费版战车素材，随后指定纳米护甲、帝王能量炮、帝王战车的差异图也均采用免费版。

## 初始已接入范围（后续扩展见下节）

- 贪狼千级的普通/赠送/新版、千级帝王、圣诞、龙腾新兵：6个装备定义，4套世界动画及各自背包、装备面板图，共12个来源素材。
- 纳米前护甲的背包和面板图、帝王能量炮的面板图：另3个来源素材。
- 合计15个来源素材、8个装备定义、21个展示位。均为 `starhome_lz_fr`，保留原始帧和原点，没有重绘。
- 免费版圣诞战车是 `pic2`；荣耀原引用为 `pic3`。龙腾新兵33帧中的第32帧附图保留，但不进入八方向移动循环。

`tools/import_approved_equipment_assets.py` 可再生成本轮素材和配置；运行图集放在
`assets/recovered/vehicles/` 与 `assets/recovered/equipment/` 下按实体、动作命名。
每个实体的 `source_manifest.json` 记录授权、原路径、发布版、SHA-256；帧描述为可再生成的紧凑JSON。
`data/content/recovered_sprite_runtime_index_v1.json` 只声明已批准的精确映射，不覆盖任何已有荣耀索引。
`AleSpriteRepository` 按需加载，并返回真实 `source_release`；物品展示状态通过独立覆盖表更新，原始荣耀目录保留原版缺失证据。

## 全部候选接入（用户追加授权）

2026-09-17 用户明确要求“有候选的全部接入”。新增173条原引用，累计188条：185条免费版、3条激战版。
覆盖180个物品定义、430个展示位；武器可用弹体映射从44个提升到50个。
保留原始帧、尺寸、像素、原点；没有新增属性、出售项或获取规则。

- 剩余装备、发生器、装甲、配组器、服装等通过统一物品目录展示覆盖表接入。
- 加工石恢复免费版原图，商店/背包改用ALE解析；此前补绘图作为历史素材保留。
- 奔雷导弹及其赠送/变体、两种圣诞炮、纪念炮的6个装备绑定补齐4种弹体。
- 8个方向箭头与现有荣耀共享动画逐字节相同，补入精确来源映射，继续复用已连接的传送表现，避免重复叠图。
- 交易中心缺失的绿色屏幕恢复3处，按原坐标、全部12帧、100毫秒/帧循环；纳入活动世界的暂存、失败隔离和切图清理。

新增素材放入 `assets/content_packs/recovered_equipment_and_scenery.zip`（约3.3MB）。包内按业务实体命名，
`assets/recovered/source_manifest.json` 记录全部来源、哈希、官网请求证据与批准范围；没有引入原始客户端档案。
通过 `RuntimeContentBootstrap` 挂载，以原有 `RuntimeTextureLoader` 解码包内PNG，无需生成散落的 `.import`。
`data/import/recovered_asset_selections_v1.json` 固定173项选择；运行 `python -X utf8 tools/import_remaining_recovered_assets.py`
重建内容包、索引、物品覆盖和场景声明，再运行 `tools/build_weapon_visual_bindings.py` 与 `tools/build_attachment_upgrade_shop.py`
同步弹体及加工石。初始导入器已保留后续恢复项，重复生成不会清掉新映射。

同名候选核对：服装30组的pic/pic2文件哈希一致，且免费版 `cltobj/clothcltclass.fcc` 明确引用pic2路径，行号逐项记录。
旧式后/左/右护甲的缺失源于原目录生成时未求值路径变量，荣耀 `cltobj/equipclt.fcc` 的风格表明确指定同名body图，
据此固定激战版的对应引用；不把同名回退加入运行时。奔雷弹体沿用荣耀武器声明的文件名，固定免费版唯一同名弹体。

验证：新增包逐页与来源PNG字节一致，全部帧描述与原点一致；188条实际Godot加载检查；180个定义经实际物品解析器检查；
6个绑定验证真实发射节点；3处交易中心屏幕验证帧进度、原点、切图释放和失败提交隔离。
`tests/content/glory_ale_sprite_repository_test.gd` 与 `tests/integration/recovered_assets_runtime_test.gd` 已纳入完整客户端门禁。

## 全量检索口径

汇总物品目录463个缺失展示位（199条唯一原路径）、弹体缺失表、历史地图AddImg报告、最新场景缺失报告、
官网失败缓存、运行素材manifest和4个缺包地图注册，共495条独立路径。
其中253条现在可从荣耀原始档案/恢复缓存找到，属于已过期的缺失记录；剩余242条参与本次跨版本结果统计。
未声明路径的330个展示位、1条为空的弹体引用不伪造文件名，也不混入242条可检索路径。
地图完整包仍须恢复地图定义、导航及场景关系，找到同名资源不等于地图已开放。

| 本轮检索结果 | 独立原引用数 |
| --- | ---: |
| 仅免费版有候选 | 150 |
| 仅新激战版有候选 | 3 |
| 两版逐字节相同 | 31 |
| 两版图像不同，用户已选免费版 | 4 |
| 两版均未找到 | 54 |

“有候选”包括精确路径、仅版本pic目录前缀不同、同名且展示角色相符的匹配；本次追加授权后已全部接入。
免费版精确路径134条、版本前缀候选20条、其他同名候选31条；新激战版前缀候选23条、其他同名候选15条。
仅激战版的3条是前期生成目录中路径不完整的后/左/右护甲引用，已按原类风格表核实用途。
对当地档案未命中的一方，再向其官网精确原路径发起270次请求：261次404，9个免费版ALE成功下载、解析。
9个远程找回文件为8方向箭头及交易中心绿色屏幕，现已接入；54条两版均缺失的引用仍未恢复（40条ALE及14条地图脚本路径）。

## 比较方法与产物

先比原文件SHA-256；字节不同则比较每一帧的RGBA像素、尺寸、帧顺序和原点，不只比较首帧。
不会把游戏代码规定的播放间隔当作ALE内的属性。异路径同名候选保留匹配类型与原版关联核对记录。
四处差异：A310/A311纳米前护甲面板/背包、A370帝王能量炮面板、A371千级帝王战车面板，均已由用户选择免费版。

- [可筛选的完整检索表与对照图](../../cross_release_asset_review/index.html)
- [机器审计结果](../../cross_release_asset_review/audit.json)
- [官网逐项请求记录](../../cross_release_asset_review/remote_checks.json)：URL、状态、字节数、MD5、SHA-256、解码状态。
- 原始下载与解析存于 `outputs/cross_release_asset_review/remote_cache/`，属于本地原档案，不进入素材子模块。
- 运行 `python -X utf8 tools/audit_cross_release_assets.py` 重建本地比较报告；
  `tools/probe_cross_release_assets.py` 只查询尚未记录过的精确路径，成功/失败均缓存，不重复探测。

## 当前242条逐项结果

“已接入”按本轮恢复索引判断。素材引用可被多个装备、多个地图共用，数量不能等同于物品或地图数量。
完整候选路径、所有用途、匹配类型和源报告均见上面的JSON/HTML；下表保留可追踪的独立原引用及状态。

| 编号 | 原始引用 | 用途示例 | 检索结果 | 运行接入 |
| --- | --- | --- | --- | --- |
| A001 | `equip/body/backarmor1.ale` | String9127+"（赠）" / inventory | 仅激战版候选 | starhome_jznp |
| A002 | `equip/body/leftarmor1.ale` | String9128+"（赠）" / inventory | 仅激战版候选 | starhome_jznp |
| A003 | `equip/body/rightarmor1.ale` | String9129+"（赠）" / inventory | 仅激战版候选 | starhome_jznp |
| A004 | `map/ag/kuangdong/media/house/shumu/dx_shuijing_1.ale` | AG_SYMX_1 / shenyanmixue | 两版未找到 | 未接入 |
| A005 | `map/ag/kuangdong/media/house/shumu/dx_shuijing_2.ale` | AG_SYMX_1 / shenyanmixue | 两版未找到 | 未接入 |
| A006 | `map/ag/kuangdong/media/house/shumu/dx_shuijing_3.ale` | AG_SYMX_1 / shenyanmixue | 两版未找到 | 未接入 |
| A007 | `map/ag/kuangdong/media/house/shumu/dx_shuijing_4.ale` | AG_SYMX_1 / shenyanmixue | 两版未找到 | 未接入 |
| A044 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/d..ale` | 交易中心 / TradeRoom1 | 仅免费版候选 | starhome_lz_fr |
| A045 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-01..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A046 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-02..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A047 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-03..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A048 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-04..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A049 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-05..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A050 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-06..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A051 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-07..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A052 | `map/mapimg/ani/chn_2005_06_28_19_32_06_50/jt-08..ale` | D04区域 / d04 | 仅免费版候选 | starhome_lz_fr |
| A092 | `map/mapimg/house/chn_2005_06_28_19_27_41_7/猜拳机21.ale` | 废弃的基地 / RedHouse1 | 两版未找到 | 未接入 |
| A093 | `map/mapimg/house/chn_2005_06_28_19_27_41_7/色子机.ale` | 废弃的基地 / RedHouse1 | 两版未找到 | 未接入 |
| A144 | `map/mapimg/house/chn_2005_06_28_19_29_30_24/太空棉.ale` | 裁缝店 / 2clothshop1 | 两版未找到 | 未接入 |
| A208 | `map/mapimg/house/chn_2005_06_28_19_30_29_34/能量.ale` | D08区域 / d08 | 两版未找到 | 未接入 |
| A241 | `map/mapimg/house/jianzhu/yhzx.ale` | 宇航中心 / NASA1 | 两版未找到 | 未接入 |
| A242 | `map/mapimg/house/npc/机甲01a.ale` | C08区域 / c08 | 两版未找到 | 未接入 |
| A243 | `map/mapimg/house/npc/机甲01b.ale` | G08区域 / g08 | 两版未找到 | 未接入 |
| A244 | `map/mapimg/house/npc/机甲01c.ale` | G08区域 / g08 | 两版未找到 | 未接入 |
| A245 | `map/mapimg/house/npc/机甲02a.ale` | G06区域 / g06 | 两版未找到 | 未接入 |
| A246 | `map/mapimg/house/npc/机甲02b.ale` | D08区域 / d08 | 两版未找到 | 未接入 |
| A247 | `map/mapimg/house/npc/机甲02c.ale` | D08区域 / d08 | 两版未找到 | 未接入 |
| A248 | `map/mapimg/house/宇航中心/能量机.ale` | 宇航中心 / NASA1 | 两版未找到 | 未接入 |
| A281 | `nft_bt/map/blackroom/blackroom.fcc.cab` | 安全屋 | 两版未找到 | 未接入 |
| A282 | `nft_bt/map/yzzl_1/yzzl_1.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A283 | `nft_bt/map/yzzl_2/yzzl_2.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A284 | `nft_bt/map/yzzl_3/yzzl_3.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A285 | `nft_bt/map/yzzl_4/yzzl_4.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A286 | `nft_bt/map/yzzl_5/yzzl_5.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A287 | `nft_bt/map/yzzl_6/yzzl_6.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A288 | `nft_ds/map/roomsvr3/roomsvr3.fcc.cab` | 孟多拉城基地大厅三层 | 两版未找到 | 未接入 |
| A289 | `nft_sk/map/yzzl_1/yzzl_1.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A290 | `nft_sk/map/yzzl_2/yzzl_2.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A291 | `nft_sk/map/yzzl_3/yzzl_3.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A292 | `nft_sk/map/yzzl_4/yzzl_4.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A293 | `nft_sk/map/yzzl_5/yzzl_5.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A294 | `nft_sk/map/yzzl_6/yzzl_6.fcc.cab` | 勇者之路 | 两版未找到 | 未接入 |
| A295 | `pic/chn_2005_06_28_19_33_57_68/chn_2005_06_28_18_32_09_749.ale` | 隐身装置X-1型 / inventory | 两版相同 | starhome_lz_fr |
| A296 | `pic/chn_2005_06_28_19_34_03_69/radar.ale` | 雷达装置Y-1型 / inventory | 两版相同 | starhome_lz_fr |
| A297 | `pic2/equip/armor/backarmor01-a.ale` | Month090514 + ZHOUJ_STRING0002 / inventory | 两版相同 | starhome_lz_fr |
| A298 | `pic2/equip/armor/backarmor01-b.ale` | Month090514 + ZHOUJ_STRING0002 / dialog | 两版相同 | starhome_lz_fr |
| A299 | `pic2/equip/armor/backarmor10-a.ale` | "\#FFFF00壁垒级后护甲"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A300 | `pic2/equip/armor/backarmor8.ale` | 纳米后护甲 / dialog | 两版相同 | starhome_lz_fr |
| A301 | `pic2/equip/armor/backarmor8b.ale` | 纳米后护甲 / inventory | 仅免费版候选 | starhome_lz_fr |
| A302 | `pic2/equip/armor/backarmor9.ale` | \#FFFF00帝王级后护甲 / inventory | 两版相同 | starhome_lz_fr |
| A303 | `pic2/equip/armor/defensearmor_bag.ale` | \#18fb0b防御力场装甲\#FFFF00 / inventory | 仅免费版候选 | starhome_lz_fr |
| A304 | `pic2/equip/armor/defensearmor_d_bag.ale` | \#ff00ff帝王级防御力场装甲\#FFFF00 / inventory | 仅免费版候选 | starhome_lz_fr |
| A305 | `pic2/equip/armor/defensearmor_d_dlg.ale` | \#ff00ff帝王级防御力场装甲\#FFFF00 / dialog | 仅免费版候选 | starhome_lz_fr |
| A306 | `pic2/equip/armor/defensearmor_dlg.ale` | \#18fb0b防御力场装甲\#FFFF00 / dialog | 仅免费版候选 | starhome_lz_fr |
| A307 | `pic2/equip/armor/frontarmor01-a.ale` | Month090513 + ZHOUJ_STRING0002 / inventory | 两版相同 | starhome_lz_fr |
| A308 | `pic2/equip/armor/frontarmor01-b.ale` | Month090513 + ZHOUJ_STRING0002 / dialog | 两版相同 | starhome_lz_fr |
| A309 | `pic2/equip/armor/frontarmor10-a.ale` | "\#FFFF00壁垒级前护甲"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A310 | `pic2/equip/armor/frontarmor8.ale` | 纳米前护甲 / dialog | 两版不同→已选免费版 | starhome_lz_fr |
| A311 | `pic2/equip/armor/frontarmor8b.ale` | 纳米前护甲 / inventory | 两版不同→已选免费版 | starhome_lz_fr |
| A312 | `pic2/equip/armor/frontarmor9.ale` | \#FFFF00帝王级前护甲 / inventory | 两版相同 | starhome_lz_fr |
| A313 | `pic2/equip/armor/leftarmor01-a.ale` | Month090515 + ZHOUJ_STRING0002 / inventory | 两版相同 | starhome_lz_fr |
| A314 | `pic2/equip/armor/leftarmor01-b.ale` | Month090515 + ZHOUJ_STRING0002 / dialog | 两版相同 | starhome_lz_fr |
| A315 | `pic2/equip/armor/leftarmor10-a.ale` | "\#FFFF00壁垒级左护甲"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A316 | `pic2/equip/armor/leftarmor8.ale` | 纳米左护甲 / dialog | 两版相同 | starhome_lz_fr |
| A317 | `pic2/equip/armor/leftarmor8b.ale` | 纳米左护甲 / inventory | 仅免费版候选 | starhome_lz_fr |
| A318 | `pic2/equip/armor/leftarmor9.ale` | \#FFFF00帝王级左护甲 / inventory | 两版相同 | starhome_lz_fr |
| A319 | `pic2/equip/armor/rightarmor01-a.ale` | Month090516 + ZHOUJ_STRING0002 / inventory | 两版相同 | starhome_lz_fr |
| A320 | `pic2/equip/armor/rightarmor01-b.ale` | Month090516 + ZHOUJ_STRING0002 / dialog | 两版相同 | starhome_lz_fr |
| A321 | `pic2/equip/armor/rightarmor10-a.ale` | "\#FFFF00壁垒级右护甲"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A322 | `pic2/equip/armor/rightarmor8.ale` | 纳米右护甲 / dialog | 两版相同 | starhome_lz_fr |
| A323 | `pic2/equip/armor/rightarmor8b.ale` | 纳米右护甲 / inventory | 仅免费版候选 | starhome_lz_fr |
| A324 | `pic2/equip/armor/rightarmor9.ale` | \#FFFF00帝王级右护甲 / inventory | 两版相同 | starhome_lz_fr |
| A325 | `pic2/equip/bag/benginedragon.ale` | 龙腾新兵引擎 / inventory | 仅免费版候选 | starhome_lz_fr |
| A326 | `pic2/equip/bag/bgundragon.ale` | 龙腾新兵能量炮 / inventory | 仅免费版候选 | starhome_lz_fr |
| A327 | `pic2/equip/bag/btankdragon.ale` | 龙腾新兵战车 / inventory | 仅免费版候选 | starhome_lz_fr |
| A328 | `pic2/equip/bag/engine1.ale` | 机甲初级引擎1 / inventory | 两版相同 | starhome_lz_fr |
| A329 | `pic2/equip/bag/engine_shadow_bag.ale` | 幻影推进器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A330 | `pic2/equip/bag/finalcollector.ale` | 千级挖掘臂 / inventory | 仅免费版候选 | starhome_lz_fr |
| A331 | `pic2/equip/bag/finalengine.ale` | VEN_FINAL_EQUIP_1 + VEN_FINAL_EQUIP_0 + VEN_FINAL_EQUIP… | 仅免费版候选 | starhome_lz_fr |
| A332 | `pic2/equip/bag/finalgun.ale` | m_sObjName / inventory | 仅免费版候选 | starhome_lz_fr |
| A333 | `pic2/equip/bag/finalrepair.ale` | 千级维修臂 / inventory | 仅免费版候选 | starhome_lz_fr |
| A334 | `pic2/equip/bag/finaltank.ale` | VEN_FINAL_EQUIP_1 + VEN_FINAL_EQUIP_0 + VEN_FINAL_EQUIP… | 仅免费版候选 | starhome_lz_fr |
| A335 | `pic2/equip/bag/gslzjszz_bag.ale` | \#18fb0b高斯粒子加速装置\#FFFF00 / inventory | 仅免费版候选 | starhome_lz_fr |
| A336 | `pic2/equip/bag/gun_shadow_bag.ale` | 幻影波动炮 / inventory | 仅免费版候选 | starhome_lz_fr |
| A337 | `pic2/equip/bag/monarchengine.ale` | 千级帝王引擎 / inventory | 两版相同 | starhome_lz_fr |
| A338 | `pic2/equip/bag/monarchgun.ale` | m_sObjName / inventory | 两版相同 | starhome_lz_fr |
| A339 | `pic2/equip/bag/monarchtank.ale` | 千级帝王战车 / inventory | 两版相同 | starhome_lz_fr |
| A340 | `pic2/equip/bag/superdcksq_bag.ale` | \#18fb0b超电磁扩散器\#FFFF00 / inventory | 仅免费版候选 | starhome_lz_fr |
| A341 | `pic2/equip/bag/tank_shadow_bag.ale` | 幻影战甲 / inventory | 仅免费版候选 | starhome_lz_fr |
| A342 | `pic2/equip/body/engine1.ale` | 机甲初级引擎1 / world | 两版相同 | starhome_lz_fr |
| A343 | `pic2/equip/body/engine2.ale` | VEN_FINAL_EQUIP_1 + VEN_FINAL_EQUIP_0 + VEN_FINAL_EQUIP… | 两版相同 | starhome_lz_fr |
| A344 | `pic2/equip/body/engine_shadow.ale` | 幻影推进器 / world | 两版未找到 | 未接入 |
| A345 | `pic2/equip/body/finalcollector.ale` | 千级挖掘臂 / world | 仅免费版候选 | starhome_lz_fr |
| A346 | `pic2/equip/body/finalgun.ale` | m_sObjName / world | 仅免费版候选 | starhome_lz_fr |
| A347 | `pic2/equip/body/finalrepair.ale` | 千级维修臂 / world | 仅免费版候选 | starhome_lz_fr |
| A348 | `pic2/equip/body/finaltank.ale` | VEN_FINAL_EQUIP_1 + VEN_FINAL_EQUIP_0 + VEN_FINAL_EQUIP… | 仅免费版候选 | starhome_lz_fr |
| A349 | `pic2/equip/body/gun_shadow.ale` | 幻影波动炮 / world | 仅免费版候选 | starhome_lz_fr |
| A350 | `pic2/equip/body/menginedragon.ale` | 龙腾新兵引擎 / world | 仅免费版候选 | starhome_lz_fr |
| A351 | `pic2/equip/body/mgundragon.ale` | 龙腾新兵能量炮 / world | 仅免费版候选 | starhome_lz_fr |
| A352 | `pic2/equip/body/monarchengine.ale` | 千级帝王引擎 / world | 两版相同 | starhome_lz_fr |
| A353 | `pic2/equip/body/monarchgun.ale` | m_sObjName / world | 两版相同 | starhome_lz_fr |
| A354 | `pic2/equip/body/monarchtank.ale` | 千级帝王战车 / world | 两版相同 | starhome_lz_fr |
| A355 | `pic2/equip/body/mtankdragon.ale` | 龙腾新兵战车 / world | 仅免费版候选 | starhome_lz_fr |
| A356 | `pic2/equip/body/tank_shadow_walk.ale` | 幻影战甲 / world | 仅免费版候选 | starhome_lz_fr |
| A357 | `pic2/equip/dlg/denginedragon.ale` | 龙腾新兵引擎 / dialog | 仅免费版候选 | starhome_lz_fr |
| A358 | `pic2/equip/dlg/dgundragon.ale` | 龙腾新兵能量炮 / dialog | 仅免费版候选 | starhome_lz_fr |
| A359 | `pic2/equip/dlg/dtankdragon.ale` | 龙腾新兵战车 / dialog | 仅免费版候选 | starhome_lz_fr |
| A360 | `pic2/equip/dlg/engine1.ale` | 机甲初级引擎1 / dialog | 两版相同 | starhome_lz_fr |
| A361 | `pic2/equip/dlg/engine_shadow_dlg.ale` | 幻影推进器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A362 | `pic2/equip/dlg/finalcollector.ale` | 千级挖掘臂 / dialog | 仅免费版候选 | starhome_lz_fr |
| A363 | `pic2/equip/dlg/finalengine.ale` | VEN_FINAL_EQUIP_1 + VEN_FINAL_EQUIP_0 + VEN_FINAL_EQUIP… | 仅免费版候选 | starhome_lz_fr |
| A364 | `pic2/equip/dlg/finalgun.ale` | m_sObjName / dialog | 仅免费版候选 | starhome_lz_fr |
| A365 | `pic2/equip/dlg/finalrepair.ale` | 千级维修臂 / dialog | 仅免费版候选 | starhome_lz_fr |
| A366 | `pic2/equip/dlg/finaltank.ale` | VEN_FINAL_EQUIP_1 + VEN_FINAL_EQUIP_0 + VEN_FINAL_EQUIP… | 仅免费版候选 | starhome_lz_fr |
| A367 | `pic2/equip/dlg/gslzjszz_dlg.ale` | \#18fb0b高斯粒子加速装置\#FFFF00 / dialog | 仅免费版候选 | starhome_lz_fr |
| A368 | `pic2/equip/dlg/gun_shadow_dlg.ale` | 幻影波动炮 / dialog | 仅免费版候选 | starhome_lz_fr |
| A369 | `pic2/equip/dlg/monarchengine.ale` | 千级帝王引擎 / dialog | 两版相同 | starhome_lz_fr |
| A370 | `pic2/equip/dlg/monarchgun.ale` | m_sObjName / dialog | 两版不同→已选免费版 | starhome_lz_fr |
| A371 | `pic2/equip/dlg/monarchtank.ale` | 千级帝王战车 / dialog | 两版不同→已选免费版 | starhome_lz_fr |
| A372 | `pic2/equip/dlg/superdcksq_dlg.ale` | \#18fb0b超电磁扩散器\#FFFF00 / dialog | 仅免费版候选 | starhome_lz_fr |
| A373 | `pic2/equip/dlg/tank_shadow_dlg.ale` | 幻影战甲 / dialog | 仅免费版候选 | starhome_lz_fr |
| A374 | `pic2/equip/samahbqequip.ale` | 撒玛核变器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A375 | `pic2/equip/samahbqinbag.ale` | 撒玛核变器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A376 | `pic2/equip/samajnqequip.ale` | 撒玛聚能器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A377 | `pic2/equip/samajnqinbag.ale` | 撒玛聚能器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A378 | `pic2/equip/samamcqequip.ale` | 撒玛脉冲器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A379 | `pic2/equip/samamcqinbag.ale` | 撒玛脉冲器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A380 | `pic2/equip/samarlqequip.ale` | 撒玛扰流器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A381 | `pic2/equip/samarlqinbag.ale` | 撒玛扰流器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A382 | `pic2/equip/subgun/monarchsubgun_1.ale` | \#339900帝王级发生器(2级) / inventory | 仅免费版候选 | starhome_lz_fr |
| A383 | `pic2/equip/subgun/monarchsubgun_12.ale` | \#00FF00帝王级紫电发生器（2级） / inventory | 仅免费版候选 | starhome_lz_fr |
| A384 | `pic2/equip/subgun/monarchsubgun_12_dlg.ale` | \#00FF00帝王级紫电发生器（2级） / dialog | 仅免费版候选 | starhome_lz_fr |
| A385 | `pic2/equip/subgun/monarchsubgun_16.ale` | WKFR1112056+"（赠）" / inventory | 仅免费版候选 | starhome_lz_fr |
| A386 | `pic2/equip/subgun/monarchsubgun_16_dlg.ale` | WKFR1112056+"（赠）" / dialog | 仅免费版候选 | starhome_lz_fr |
| A387 | `pic2/equip/subgun/monarchsubgun_1_dlg.ale` | \#339900帝王级发生器(2级) / dialog | 仅免费版候选 | starhome_lz_fr |
| A388 | `pic2/equip/subgun/monarchsubgun_5.ale` | \#00FF00灼热发生器赠（2级）\#FFFFFF / inventory | 仅免费版候选 | starhome_lz_fr |
| A389 | `pic2/equip/subgun/monarchsubgun_5_dlg.ale` | \#00FF00灼热发生器赠（2级）\#FFFFFF / dialog | 仅免费版候选 | starhome_lz_fr |
| A390 | `pic2/equip/subgun/monarchsubgun_6.ale` | \#00FF00蚀甲发生器赠（2级）\#FFFFFF / inventory | 仅免费版候选 | starhome_lz_fr |
| A391 | `pic2/equip/subgun/monarchsubgun_6_dlg.ale` | \#00FF00蚀甲发生器赠（2级）\#FFFFFF / dialog | 仅免费版候选 | starhome_lz_fr |
| A392 | `pic2/equip/subgun/monarchsubgun_7.ale` | \#00FF00泯灭发生器赠（2级）\#FFFFFF / inventory | 仅免费版候选 | starhome_lz_fr |
| A393 | `pic2/equip/subgun/monarchsubgun_7_dlg.ale` | \#00FF00泯灭发生器赠（2级）\#FFFFFF / dialog | 仅免费版候选 | starhome_lz_fr |
| A394 | `pic2/stuff/barmorshining.ale` | 闪灵防御配组器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A395 | `pic2/stuff/benginegunshining.ale` | 闪灵能量炮配组器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A396 | `pic2/stuff/bhealthshining.ale` | 闪灵生命配组器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A397 | `pic2/stuff/bhurtarmor1.ale` | 急速磁力场配组器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A398 | `pic2/stuff/brocketmissileshining.ale` | 闪灵火导配组器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A399 | `pic2/stuff/bspecialshining.ale` | 闪灵特殊配组器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A400 | `pic2/stuff/jieheqi/hongatomic01.ale` | 宏原子强化装置(赠) / inventory | 两版相同 | starhome_lz_fr |
| A401 | `pic2/stuff/jieheqi/hongatomic02.ale` | 宏原子强化装置(赠) / dialog | 两版相同 | starhome_lz_fr |
| A402 | `pic2/stuff/jieheqi/huokong_a-1.ale` | "A型火控仓"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A403 | `pic2/stuff/jieheqi/huokong_a-2.ale` | "A型火控仓"+FrMonth090903 / dialog | 仅免费版候选 | starhome_lz_fr |
| A404 | `pic2/stuff/jieheqi/huokong_c-1.ale` | "C型火控仓"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A405 | `pic2/stuff/jieheqi/huokong_c-2.ale` | "C型火控仓"+FrMonth090903 / dialog | 仅免费版候选 | starhome_lz_fr |
| A406 | `pic2/stuff/jieheqi/huokong_d-1.ale` | 狂战型火控仓 / inventory | 仅免费版候选 | starhome_lz_fr |
| A407 | `pic2/stuff/jieheqi/huokong_d-2.ale` | 狂战型火控仓 / dialog | 仅免费版候选 | starhome_lz_fr |
| A408 | `pic2/stuff/jieheqi/huokongincrease_a-1.ale` | "A型火控仓增幅器"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A409 | `pic2/stuff/jieheqi/huokongincrease_a-2.ale` | "A型火控仓增幅器"+FrMonth090903 / dialog | 仅免费版候选 | starhome_lz_fr |
| A410 | `pic2/stuff/jieheqi/huokongincrease_c-1.ale` | "C型火控仓增幅器"+FrMonth090903 / inventory | 仅免费版候选 | starhome_lz_fr |
| A411 | `pic2/stuff/jieheqi/huokongincrease_c-2.ale` | "C型火控仓增幅器"+FrMonth090903 / dialog | 仅免费版候选 | starhome_lz_fr |
| A412 | `pic2/stuff/jieheqi/huokongincrease_d-1.ale` | 狂战型火控仓增幅器 / inventory | 仅免费版候选 | starhome_lz_fr |
| A413 | `pic2/stuff/jieheqi/huokongincrease_d-2.ale` | 狂战型火控仓增幅器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A414 | `pic2/stuff/processstone.ale` | not_found | 仅免费版候选 | starhome_lz_fr |
| A415 | `pic2/stuff/zarmorshining.ale` | 闪灵防御配组器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A416 | `pic2/stuff/zenginegunshining.ale` | 闪灵能量炮配组器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A417 | `pic2/stuff/zhealthshining.ale` | 闪灵生命配组器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A418 | `pic2/stuff/zhurtarmor1.ale` | 急速磁力场配组器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A419 | `pic2/stuff/zrocketmissileshining.ale` | 闪灵火导配组器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A420 | `pic2/stuff/zspecialshining.ale` | 闪灵特殊配组器 / dialog | 仅免费版候选 | starhome_lz_fr |
| A421 | `pic3/bianpao/chn_2005_06_28_19_32_31_54/dong_duihua.ale` | 便便娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A422 | `pic3/bianpao/chn_2005_06_28_19_32_31_54/dong_zoulu.ale` | 便便娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A423 | `pic3/bianpao/chn_2005_06_28_19_32_37_55/guan_dui.ale` | 小狗娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A424 | `pic3/bianpao/chn_2005_06_28_19_32_37_55/guan_zoulu.ale` | 小狗娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A425 | `pic3/bianpao/chn_2005_06_28_19_32_42_56/hou_dui.ale` | 芝麻官娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A426 | `pic3/bianpao/chn_2005_06_28_19_32_42_56/hou_zoulu.ale` | 芝麻官娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A427 | `pic3/bianpao/chn_2005_06_28_19_32_49_57/chn_2005_06_28_18_23_01_655.ale` | 猴头娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A428 | `pic3/bianpao/chn_2005_06_28_19_32_49_57/chn_2005_06_28_18_23_13_657.ale` | 猴头娃娃头 / world | 两版未找到 | 未接入 |
| A429 | `pic3/bianpao/chn_2005_06_28_19_32_55_58/chn_2005_06_28_18_23_24_659.ale` | 宝宝娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A430 | `pic3/bianpao/chn_2005_06_28_19_32_55_58/chn_2005_06_28_18_23_36_661.ale` | 宝宝娃娃头 / world | 两版未找到 | 未接入 |
| A431 | `pic3/bianpao/chn_2005_06_28_19_33_01_59/nv_dui.ale` | 猫咪娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A432 | `pic3/bianpao/chn_2005_06_28_19_33_01_59/nv_zoulu.ale` | 猫咪娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A433 | `pic3/bianpao/chn_2005_06_28_19_33_13_61/chn_2005_06_28_18_24_40_672.ale` | 蘑菇娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A434 | `pic3/bianpao/chn_2005_06_28_19_33_13_61/chn_2005_06_28_18_24_52_674.ale` | 蘑菇娃娃头 / world | 两版未找到 | 未接入 |
| A435 | `pic3/bianpao/chn_2005_06_28_19_33_20_62/mi_duihua.ale` | 小男孩娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A436 | `pic3/bianpao/chn_2005_06_28_19_33_20_62/mi_zoulu.ale` | 小男孩娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A437 | `pic3/bianpao/chn_2005_06_28_19_33_26_63/chn_2005_06_28_18_25_03_676.ale` | 南瓜娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A438 | `pic3/bianpao/chn_2005_06_28_19_33_26_63/chn_2005_06_28_18_25_15_678.ale` | 南瓜娃娃头 / world | 两版未找到 | 未接入 |
| A439 | `pic3/bianpao/chn_2005_06_28_19_33_32_64/chn_2005_06_28_18_26_13_688.ale` | 小女孩娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A440 | `pic3/bianpao/chn_2005_06_28_19_33_32_64/chn_2005_06_28_18_26_19_689.ale` | 小女孩娃娃头 / world | 两版未找到 | 未接入 |
| A441 | `pic3/bianpao/chn_2005_06_28_19_33_39_65/chn_2005_06_28_18_26_37_692.ale` | 茵茵娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A442 | `pic3/bianpao/chn_2005_06_28_19_33_39_65/chn_2005_06_28_18_26_49_694.ale` | 茵茵娃娃头 / world | 两版未找到 | 未接入 |
| A443 | `pic3/bianpao/chn_2005_06_28_19_33_45_66/chn_2005_06_28_18_27_00_696.ale` | 小猪娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A444 | `pic3/bianpao/chn_2005_06_28_19_33_45_66/chn_2005_06_28_18_27_06_697.ale` | 小猪娃娃头 / world | 两版未找到 | 未接入 |
| A445 | `pic3/bianpao/chn_2005_06_28_19_33_51_67/chn_2005_06_28_18_27_24_700.ale` | 妞妞娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A446 | `pic3/bianpao/chn_2005_06_28_19_33_51_67/chn_2005_06_28_18_27_29_701.ale` | 妞妞娃娃头 / world | 两版未找到 | 未接入 |
| A447 | `pic3/bianpao/cong/cong_dui.ale` | 桃子娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A448 | `pic3/bianpao/cong/cong_zou.ale` | 桃子娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A449 | `pic3/bianpao/girl1/chn_2005_06_28_18_25_26_680.ale` | 小兔娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A450 | `pic3/bianpao/girl1/chn_2005_06_28_18_25_44_683.ale` | 小兔娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A451 | `pic3/bianpao/girl2/chn_2005_06_28_18_25_50_684.ale` | 小精灵娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A452 | `pic3/bianpao/girl2/chn_2005_06_28_18_26_07_687.ale` | 小精灵娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A453 | `pic3/bianpao/tao/tao_dui.ale` | 小羊娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A454 | `pic3/bianpao/tao/tao_zou.ale` | 小羊娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A455 | `pic3/bianpao/xiong/mao_dui.ale` | 熊猫娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A456 | `pic3/bianpao/xiong/mao_zou.ale` | 熊猫娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A457 | `pic3/bianpao/yang/yang_dui.ale` | 洋葱娃娃头 / inventory | 仅免费版候选 | starhome_lz_fr |
| A458 | `pic3/bianpao/yang/yang_zou.ale` | 洋葱娃娃头 / world | 仅免费版候选 | starhome_lz_fr |
| A459 | `pic3/bullet/bullet01.ale` | glory_equipment_memory_gun1_4df55354ab | 仅免费版候选 | starhome_lz_fr |
| A460 | `pic3/bullet/gun14_bullet14.ale` | glory_equipment_xmasgun_9d72e95d33 | 仅免费版候选 | starhome_lz_fr |
| A461 | `pic3/bullet/gun_xmas_bullet.ale` | glory_equipment_gun_xmas_9475063eaa | 两版相同 | starhome_lz_fr |
| A462 | `pic3/bullet/missile_thunder_pd.ale` | glory_equipment_missile_thunder_c5ee4fe533 | 仅免费版候选 | starhome_lz_fr |
| A463 | `pic3/clothing/bag/woman/womancloth13a.ale` | 短袍（女） / inventory | 两版未找到 | 未接入 |
| A464 | `pic3/clothing/bag/woman/womancloth13b.ale` | 短袍（女） / inventory | 两版未找到 | 未接入 |
| A465 | `pic3/clothing/bag/woman/womancloth13c.ale` | 短袍（女） / inventory | 两版未找到 | 未接入 |
| A466 | `pic3/clothing/body/woman/womancloth13a.ale` | 短袍（女） / world | 两版未找到 | 未接入 |
| A467 | `pic3/clothing/body/woman/womancloth13b.ale` | 短袍（女） / world | 两版未找到 | 未接入 |
| A468 | `pic3/clothing/body/woman/womancloth13c.ale` | 短袍（女） / world | 两版未找到 | 未接入 |
| A470 | `pic3/clothing/dlg/woman/womancloth13a.ale` | 短袍（女） / dialog | 两版未找到 | 未接入 |
| A471 | `pic3/clothing/dlg/woman/womancloth13b.ale` | 短袍（女） / dialog | 两版未找到 | 未接入 |
| A472 | `pic3/clothing/dlg/woman/womancloth13c.ale` | 短袍（女） / dialog | 两版未找到 | 未接入 |
| A473 | `pic3/equip/bag/gun14.ale` | Yl_09String090 + ZHOUJ_STRING0002 / inventory | 仅免费版候选 | starhome_lz_fr |
| A474 | `pic3/equip/bag/repair12.ale` | 铁十字量子维修臂 / inventory | 仅免费版候选 | starhome_lz_fr |
| A475 | `pic3/equip/bag/repair13.ale` | 量子微控维修臂 / inventory | 仅免费版候选 | starhome_lz_fr |
| A476 | `pic3/equip/bag/xmasengine.ale` | m_sObjName / inventory | 仅免费版候选 | starhome_lz_fr |
| A477 | `pic3/equip/bag/xmasgun.ale` | m_sObjName / inventory | 仅免费版候选 | starhome_lz_fr |
| A478 | `pic3/equip/bag/xmastank.ale` | m_sObjName / inventory | 仅免费版候选 | starhome_lz_fr |
| A479 | `pic3/equip/body/engineg91.ale` | G91引擎 / world | 两版未找到 | 未接入 |
| A480 | `pic3/equip/body/enginexxx.ale` | 神秘引擎 / world | 两版未找到 | 未接入 |
| A481 | `pic3/equip/body/gun14.ale` | Yl_09String090 + ZHOUJ_STRING0002 / world | 仅免费版候选 | starhome_lz_fr |
| A482 | `pic3/equip/body/missile_thunder-1.ale` | ZC_COLOR_0001+ZC_1011MONTH_005 / inventory | 两版未找到 | 未接入 |
| A483 | `pic3/equip/body/missile_thunder-2.ale` | ZC_COLOR_0001+ZC_1011MONTH_005 / dialog | 两版未找到 | 未接入 |
| A484 | `pic3/equip/body/repair12.ale` | 铁十字量子维修臂 / world | 仅免费版候选 | starhome_lz_fr |
| A485 | `pic3/equip/body/repair13.ale` | 量子微控维修臂 / world | 仅免费版候选 | starhome_lz_fr |
| A486 | `pic3/equip/body/xmasengine.ale` | m_sObjName / world | 两版未找到 | 未接入 |
| A487 | `pic3/equip/body/xmasgun.ale` | m_sObjName / world | 仅免费版候选 | starhome_lz_fr |
| A488 | `pic3/equip/body/xmastank.ale` | m_sObjName / world | 仅免费版候选 | starhome_lz_fr |
| A489 | `pic3/equip/bodyplayer_airship_4.ale` | 达飞德型 / world | 两版未找到 | 未接入 |
| A490 | `pic3/equip/dlg/gun14.ale` | Yl_09String090 + ZHOUJ_STRING0002 / dialog | 仅免费版候选 | starhome_lz_fr |
| A491 | `pic3/equip/dlg/repair12.ale` | 铁十字量子维修臂 / dialog | 仅免费版候选 | starhome_lz_fr |
| A492 | `pic3/equip/dlg/repair13.ale` | 量子微控维修臂 / dialog | 仅免费版候选 | starhome_lz_fr |
| A493 | `pic3/equip/dlg/xmasengine.ale` | m_sObjName / dialog | 仅免费版候选 | starhome_lz_fr |
| A494 | `pic3/equip/dlg/xmasgun.ale` | m_sObjName / dialog | 仅免费版候选 | starhome_lz_fr |
| A495 | `pic3/equip/dlg/xmastank.ale` | m_sObjName / dialog | 仅免费版候选 | starhome_lz_fr |
