# 装备三种表现模式与面板叠图

## 素材契约

荣耀版装备定义已经记录三条独立引用，不能用缩放同一张图片代替。

| 使用场景 | 原客户端字段 | 典型素材路径 | 复刻读取方式 |
| --- | --- | --- | --- |
| 背包、物品栏 | `m_sBaseSrc` | `pic3/equip/bag/*.ale` | `presentation_for("inventory")` |
| 装备面板 | `m_sDlgSrc` | `pic3/equip/dlg/*.ale` | `presentation_for("dialog")` |
| 野外战车 | `m_sMoveSrc` | `pic3/equip/body/*.ale` | 世界组件目录、方向和动画帧 |

并非每件装备都需要在野外额外绘制一层；是否参与整车合成由世界组件配置决定，不能把装备窗大图放进野外。

证据位置：

- `data/gameplay/glory/glory_items_v1.json`：原始装备字段与三个表现模式的对应引用。
- `assets/ui/windows/source_manifest.json`：已导出的荣耀版 PNG 来源、尺寸、ALE 原点。
- `assets/equipment_world/source_manifest.json`、`combat_visual_manifest.json`：野外八向素材来源与组件绑定。

新兵装备的实际图像尺寸如下（单位：像素）：

| 装备 | 背包图 | 装备窗图 | 装备窗原点 |
| --- | --- | --- | --- |
| 新兵战车 `tank1` | 67 × 46 | 199 × 104 | (-77, 8) |
| 新兵能量炮 `gun1` | 40 × 21 | 112 × 43 | (-32, -16) |
| 初级引擎 `engine1` | 36 × 32 | 64 × 57 | (-33, -15) |

## 本次修正

旧初始装备的 `player_equipment_v1.json` 是平铺结构，同时含有 `icon`、背包 `native_size` 和 `dialog_texture`。此前模式读取原样返回整个字典，贴图加载器优先选 `icon`，导致装备窗误用背包图。再把底盘强制放大到 199 × 104，只改变了控件尺寸，没有解决原图模糊；炮仍然只有背包图那么大。

现在由 `GameItem.presentation_for()` 在兼容边界隔离模式：dialog 不返回背包 icon/native_size，inventory 不返回 dialog_texture。新版嵌套配置直接取自己的模式；缺失模式不回退到整个配置，也不拿背包图冒充大图。调用方拿到的仍是防御性副本，不改变物品领域状态。

底盘和炮按 `位置 = 安装锚点 + dialog ALE 原点`、`尺寸 = dialog 原生尺寸` 绘制。新兵两者的安装锚点均为 (170, 200)，因此底盘左上角为 (93, 208)，炮为 (138, 184)。不再强制其他底盘使用新兵战车的矩形大小，避免不同底盘与武器错位。

推进器是槽内独立展示项：在面板局部矩形 `(96, 360, 68, 68)` 内保比居中，较上次下移 31 像素，位于「推进器」标题下方。该槽位调整是本次复刻 UI 决策，不声称是原客户端的像素坐标。

背包继续使用小图，以 5 × 8 虚拟格子对应的统一尺寸保比显示并保留 5px 内边距。按后续确认的自由摆放规则，平时按各物品自己的坐标显示且允许重叠；只有点击整理时才对齐到这些格子，详见 `inventory_free_position.md`。野外仍使用原来的八向动画组件。

## 验证方式

- `tests/domain/item_presentation_modes_test.gd`：旧/新格式隔离、缺失模式、深拷贝。
- `tests/domain/glory_item_runtime_catalog_test.gd`：荣耀新兵战车、撒玛王战车、新兵炮、引擎分别解析 bag/dlg/body。
- `tests/ui/runtime/player_panels_runtime_test.gd`：校验实际源贴图而不只校验控件尺寸；校验推进器位置，以及两种底盘各自的原点与原生尺寸。
- 运行面板测试时附加 `-- --capture-equipment`（非 headless）可保存 `.godot/equipment_panel_regression.png`，供实际渲染核对。
- `tests/integration/d04_player_vehicle_presentation_test.gd`：野外八向移动、瞄准与战车层切换回归。

仅复用现有荣耀版素材；不引入其他版本装备素材。

## 2026-09-16 装备测试修正

战车面板先按 `z_layer` 排序，再按子节点顺序绘制；装备及特殊装备区不设置跨窗口的正 `z_index`。因此窗口的背景、装备和内容一同置顶或被遮挡，主炮仍绘制在底盘之上。副武器统一显示在左上第二个槽位，并使用自己的 dialog 素材；火箭目录已补齐原版 dialog/world 引用。

HUD 按 `VehicleWeapon.combat_mode()` 判断副武器，所有同类装备共用导弹/火箭按钮。权威装配也只登记实际装在 Location 13 的副武器，使用该装备的攻击、能耗和冷却；空槽不能攻击。战车属性面板包含副武器基础攻击。

长剑导弹售价 36000、回收价 18000；大力神售价 72000、回收价 36000。以毒刺售价 18000 为基准逐档翻倍，属于用户指定的复刻经济调整。

### 实际换装与弹体来源

此前野外只认识少量预先导出的组件，未命中的高级炮会保留上一件外观；攻击控制器也始终使用新兵弹体。
现在世界表现优先读取已有组件，其余装备读取自身的 world ALE；缺失时清除该层，不遗留上一件装备。
副武器最初也曾被加入世界图层；该行为已按下节 2026-09-17 的用户澄清移除。
`CombatAnimationLibrary` 复用现有荣耀内容包，缓存动画并保留每帧原点；没有新增或混用其他版本素材。

弹体关系由 `tools/build_weapon_visual_bindings.py` 离线编译为 `data/presentation/weapon_visual_bindings_v1.json`。
来源是荣耀 `cltobj/equipcltclass.fcc`、`cltobj/appendequipcltclass.fcc`、`cltobj/fireguncltclass.fcc` 等装备类。
其中 `cltobj/equipclt.fcc::ChangeEquipStyle` 会用 `m_szBulletFileChange[0]` 覆盖初始 `m_sbulletfile`；
复刻当前使用与炮身一致的默认风格 0，不能只取类中最初的弹体声明。
`bullet.fcc::laserbullet` 确认弹体从原目录 `pic3/bullet/` 加载、逐帧播放并旋转到飞行方向。

| 主炮 | 默认风格实际弹体（原版溯源名称） |
| --- | --- |
| 新兵能量炮、加强能量炮 | bullet1.ale |
| 突袭能量炮 | bullet2.ale |
| 鳄式能量炮 | bullet3.ale |
| 鳄式加强能量炮 | bullet4.ale |
| 鳄式突袭能量炮 | bullet5.ale |
| 虎式能量炮 | bullet6.ale |
| 虎式加强能量炮 | bullet7.ale |
| 虎式突袭能量炮 | bullet8.ale |
| 天神之怒 | bullet12.ale |

目前在售的五档导弹共用 `missile.ale`，七档火箭共用 `daodan1.ale`，这是原版关联，不能人为每档换一种。
清单共记录 44 件可解析装备，覆盖所有当前在售主炮和副武器；原目录另有 7 件未解析定义/缺失引用记录在
`unavailable_source_assets`，没有为这些未开放条目伪造弹体。炮口和命中效果继续使用现有同类模板；
本轮确认并恢复的是飞行弹体关联，不把模板宣称为已逆向出的每件装备独立爆炸效果。

装备投影、权威快照和已接受的发射事件均携带实际装备身份；网络仅指定身份和弹道参数，不能指定资源路径。
表现侧为在途弹体冻结发射时资源和爆炸配置，换装不改写已发出的炮弹，也不清空发射确认去重记录。
工作能量蓝条读取权威 `working_energy / working_energy_capacity`。客户端提交开火只解析瞄准、限制提交频率；
收到权威接受事件后才播放炮口与弹体，能量不足的拒绝不会再出现假开火。

### 本轮验证

`tests/integration/equipped_weapon_presentation_test.gd` 已纳入客户端总门禁，149 项检查覆盖在售武器世界图、
原版弹体映射、采掘臂切回虎式、在途换装、副武器 HUD 与真实槽位，以及真实服务端拒绝/扣能/客户端播放。
虎式在 20/100 能量时拒绝且无弹体，100/100 时发射后变为 50/100；事件与快照重发只创建一次弹体。
附加 `-- --capture-equipment` 的 OpenGL 运行通过 150 项，增加前景窗口像素遮挡检查，并输出
`.godot/equipment_window_stacking.png` 与 `.godot/equipment_weapon_preview.png`，两张实际渲染均已核对。
测试使用内存聚合和隔离状态，不操作日常存档。

## 2026-09-17 副武器固定槽位与主装置外观

副武器只显示在装备面板的「装置1」位置（显示标签为「副武器」，逻辑 Location 13），以及底部 HUD 的副武器按钮。
野外战车仅合成底盘、主装置和对应阴影；选中或发射导弹/火箭都不会隐藏主炮、替换主炮素材或改变其朝向。
主装置本身的换装、主炮开火瞄准和采掘臂采集动作仍有各自的表现。

移除 HUD 选择到世界外观的信号连接及旧的互斥武器图层 API；默认地图占位 actor 也不再包含两种副武器层。
副武器接受事件只创建其弹体/炮口效果，不触发主装置姿态。这样运行时实际装配、地图初始占位和智脑轮换使用同一规则。

装备场景检查更新为185项，覆盖全部在售副武器的来回选择、确认开火、主炮资源/帧/位置不变与装置1图标；
OpenGL渲染186项通过，已检查选中火箭时野外仍为虎式主炮，面板副武器仍位于独立槽位。
导弹速度换算及客户端/权威计时说明见[弹体速度逆向](monster_projectile_speed_reverse_engineering.md#6-2026-09-17-玩家导弹速度修正)。

## 2026-09-17 征服者行进动画方向修正

荣耀 `cltobj/equipcltclass.fcc:422` 的 `tank8` 为征服者战车，世界素材是 `pic3/equip/body/tank8.ale`，
原版底盘通过 `multisrc(..., 8)` 按八方向组织。解析素材共33帧：0～31为八方向各四帧，
第32帧是204×508的附带拼图，不属于行进动画。已逐帧检查源图及原点，不能把这张附图当作第九个方向。

动态组件此前只在总帧数能整除8时启用八方向，33帧因此被误判为共享动画；移动时连续播放全部方向，表现为车身原地打转。
新兵等其他在售底盘为32帧，未触发该分支。当前根据 `VehicleChassis` 的原版八方向契约分组，
每方向帧数取整除结果，只播放完整方向组；原始ALE缓存保留33帧及每帧原点，不修改素材或弹体动画。
不足八帧的底盘拒绝创建方向组件，避免用残缺帧冒充完整底盘。

`equipped_weapon_presentation_test.gd` 扩展为2900项检查：实际装备八种在售底盘，各方向连续推进4秒，
验证移动不跨方向、停止后回到同方向首帧、征服者附图不进入动画。该测试仍纳入56项客户端总门禁。
附加 `-- --capture-chassis` 可由真实表现器输出 `.godot/conqueror_direction_frames.png`；
本轮已检查OpenGL渲染的八行四帧矩阵，行内车身方向一致，车轮动画正常变化。
