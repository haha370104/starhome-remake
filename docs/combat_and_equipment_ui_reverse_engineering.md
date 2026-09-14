# 战斗状态条与角色/背包/战车面板逆向实现方案

本文以荣耀版 `starhome_lz_ry` 的 FCC 客户端脚本和已解析 ALE 为依据，说明首批复刻所需的四块界面：战斗地图中的战车生命/即时能量条、人物面板、背包面板、战车装备面板。

本文描述的是荣耀版业务界面。`free_hud_rendering.md` 中“免费版素材豁免”只适用于顶部栏、底部栏和小地图外框；点击按钮后打开的三个面板仍必须使用荣耀版素材。

## 1. 结论摘要

| 模块 | 原客户端的核心实现 | 复刻结论 |
|---|---|---|
| 战车生命条 | 跟随战车的 `50×4` 红色窗口，宽度按当前生命/有效生命上限裁切 | 现有 `WorldCombatStatusBar` 的方向正确，但传入的上限必须包含附加生命 |
| 战车即时能量条 | 本地战车专有的 `50×4` 蓝条，紧贴生命条下方；分母是车体 `m_nenergy` | 使用 `working_energy / working_energy_capacity`，不要误用输出功率或底部储备能量 |
| 人物面板 | 固定背景 + 男/女裸体底图 + 所穿服装按层级叠加 + 右侧文字属性 + 底部增益图标 | 人像必须做成可组合的分层预览，不能导出成单张“当前人物图” |
| 背包面板 | 物品对象直接挂在容器内，保存像素坐标；客户端检查边界和重叠，服务端确认移动 | 数据模型要保留 `position` 与 `footprint`；不能一开始就简化成只存槽号 |
| 战车装备面板 | 槽位装备数据 + 中央整车叠层预览 + 右侧聚合属性三者联动 | 槽位、预览图层、属性计算必须拆成三个组件，由同一 loadout 状态驱动 |

三个面板在启动时各创建一个单例，平时只隐藏；工具栏按钮负责切换 `show`、鼠标钩子和置顶。冻结/干扰状态下不允许打开。依据见 `face.fcc:1222-1224` 与 `menupart_main_common_dzl.fcc:1250-1297`。

## 2. 证据与可信度

### 2.1 主要源码入口

| 内容 | 位置 |
|---|---|
| `healthbar`、`energybar` 类 | `outputs/starhome_lz_ry_fcc_source/menupart_main.fcc:1415-1539` |
| 地面战车创建两条状态条 | `outputs/starhome_lz_ry_fcc_source/cltobj/equipclt.fcc:1792-1813` |
| 其他玩家只创建生命条 | `outputs/starhome_lz_ry_fcc_source/cltobj/equipclt.fcc:1949-1968` |
| 生命/即时能量回调 | `outputs/starhome_lz_ry_fcc_source/mainclient_char.fcc:1123-1151,1205-1214` |
| 武器本地检查并扣即时能量 | `outputs/starhome_lz_ry_fcc_source/cltobj/equipclt.fcc:2773-2778` |
| 人物面板、人物预览、增益图标 | `outputs/starhome_lz_ry_fcc_source/menupart_main_style.fcc:3743-4065,5650-5785,8060-8160` |
| 服装在人物面板内的叠加 | `outputs/starhome_lz_ry_fcc_source/cltobj/clothclt.fcc:266-295` |
| 背包窗口和主容器 | `outputs/starhome_lz_ry_fcc_source/menupart_main.fcc:8301-8798` |
| 背包移动协议 | `outputs/starhome_lz_ry_fcc_source/cltplayer/moveaction.fcc:32-72,360-443,844-848` |
| 战车装备窗口和属性汇总 | `outputs/starhome_lz_ry_fcc_source/menupart_main.fcc:8964-10715` |
| 战车装备类别及槽位 | `outputs/starhome_lz_ry_fcc_source/cltobj/equipclt.fcc`、`cltobj/appendequipclt.fcc` |

本文把结论分为两级：

- **客户端确认**：源码直接给出尺寸、公式、位置、素材、调用关系或协议方向。
- **复刻设计**：为了适配 Godot、多人服务端权威和现有工程结构而作的实现选择，不声称是旧服务端原算法。

## 3. 战斗地图中的战车生命条与即时能量条

### 3.1 原客户端渲染

【客户端确认】地面战车装备完成且 `m_nMapKind == 2` 时，在战车对象上创建：

- 生命条：`healthbar(25, 45, player)`。
- 即时能量条：`energybar(25, 49)`。
- 两者原始宽度均为 `50`，高度均为 `4`。
- 两条均为世界对象跟随窗口，`zorder=ZTOP`，不显示数字。
- 红条起始色为 `#EE0000`，旧客户端还会给 RGB 加少量随机量，使不同生命条的红色略有区别。复刻不必保留随机色。
- 蓝条创建时先隐藏，通过 `timer(30, "delayshow")` 延后显示。旧引擎的 timer 单位尚未完全确认；复刻只需在车体和初始快照准备好之后一起显示，避免首帧满条闪烁。

生命条公式为：

```text
effective_max_health = base_health + added_health
clamped_health       = clamp(current_health, 0, effective_max_health)
health_width         = 50 * clamped_health / effective_max_health
```

源码中的三段分支最终都化简为同一个比例公式。`added_health` 由 `AddHealthValue(...)` 计算，包含扩容/附加生命；不能只用车体基础生命。

即时能量条公式为：

```text
energy_width = 50 * current_energy / energy_capacity
```

这里的 `current_energy`、`energy_capacity` 分别是车体的 `m_ncurenergy`、`m_nenergy`。`m_noutpower` 是另一项装备属性，虽然在创建蓝条前一同初始化，但不参与蓝条宽度公式。

### 3.2 谁能看到哪一条

【客户端确认】本地地面战车创建红条和蓝条；其他玩家的 `OtherEquip` 只创建红条，蓝条代码被注释。因此首批应遵循：

- 本地战车：红条 + 蓝条。
- 其他玩家战车：红条，不泄露即时能量。
- 怪物：只显示生命条，宽度和偏移由怪物视图配置，不套用战车的 `50/45`。
- 非战斗地图中的人物：不创建这套战车条。

### 3.3 更新链与联网职责

【客户端确认】生命由 `OnHealthChange(health)` 更新：客户端先限制到 `[0, effective_max_health]`，再刷新红条。武器发动前会在本地检查并扣除即时能量；恢复由 `OnAddEnergy(delta)` 增加并限制到 `m_nenergy`。

【复刻设计】多人版采用以下权威关系：

```text
服务端装备快照
  -> 计算 effective_max_health、working_energy_capacity
  -> 下发 VehicleCombatSnapshot
  -> 客户端状态条 presenter

本地发动武器
  -> 客户端预测扣 working_energy
  -> 发送 UseAbilityIntent
  -> 服务端校验并返回权威快照
  -> 客户端校正蓝条
```

服务端仍是生命、能量、装备和命中结果的最终权威。客户端预测只用于让蓝条立即响应，不允许客户端自行确认伤害。原客户端只证明“动作前本地扣能 + 后续回调补能”，不能证明旧服务端的恢复周期；现有 `VehicleCombatState.regenerate_working_energy()` 中恢复率仍属于可调复刻规则。

### 3.4 Godot 节点方案

沿用现有 `scripts/client/presentation/combat/world_combat_status_bar.gd`，但把职责固定为纯显示：

```text
VehicleWorldView (Node2D)
└── CombatStatusBar (WorldCombatStatusBar, Node2D)
    ├── health ratio
    └── local vehicle only: working-energy ratio
```

要求：

- 地面战车配置 `width=50`、`offset=(0,45)`、能量 Y 偏移 `4`。
- `set_health(current, maximum)` 的 `maximum` 必须是有效生命上限。
- `set_energy` 只接收 `working_energy`，不得接收 `reserve_energy`、`power_output` 或 `available_power_output`。
- presenter 订阅状态快照，不从节点树反查领域对象。
- 状态条绑定战车脚点；窗口变大只扩大地图视野，不改变条宽。
- 比例输入必须防零、限制在 `[0,1]`；无有效车体数据时隐藏整组条。

## 4. 人物面板

### 4.1 固定布局与素材

【客户端确认】`HumanEquip` 初始逻辑尺寸为 `328×450`，创建后宽度增加 28，荣耀版背景实际解析为 `355×450`：

```text
assets source: pic3/interface/HumanEquipBk.ale
parsed size:   355×450
```

主要区域：

| 区域 | 原位置/尺寸 | 内容 |
|---|---:|---|
| 人物预览 | `(17,44)`, `173×259` | 人物底图、所穿衣服、外观背景/变形 |
| 人物资料 | `(193,55)`, `142×250` | 姓名、综合等级、称号/昵称、组织等 |
| 自我介绍 | 约 `(30,310)`, `290×60` | `m_sHumanDesc` |
| 增益区 | `(15,373)`, `310×60` | 两行图标及翻页按钮 |
| 关闭按钮 | `(327,39)` | `form/closebuttom.ale` 三态按钮 |

裸体底图：

- 男：`pic3/interface/char/manindlg.ale`，解析帧 `59×228`。
- 女：`pic3/interface/char/womanindlg.ale`，解析帧 `65×219`。
- `humanequipwnd` 自身位于窗口 `(17,44)`，裸体底图锚点 `(74,231)` 是该子窗口的局部坐标。
- 男体 ALE origin 为 `(-35,-211)`，最终窗口坐标为 `(56,64)`；女体 origin 为
  `(-39,-202)`，最终窗口坐标为 `(52,73)`。不得漏掉子窗口偏移或只按图片左上角摆放。
- 预览背景为 `pic3/interface/char/manbackground.jpg`，原脚本在子窗口局部 `(-4,4)` 创建，
  因此最终坐标为 `(13,48)`，保持图片原始 `180×260`，不缩放到命中区的 `173×259`。

### 4.2 人像合成

【客户端确认】衣服不是预烘焙到人物图里。每件已穿服装使用自己的 `m_sdlgsrc`，其
`WearInDlg()` 直接在人物面板窗口坐标 `(91,274)` 创建，并以 `m_nLayer` 决定 Z 顺序。
例如无袖衫（男）的 ALE origin 为 `(-37,-181)`，最终左上角为 `(54,93)`。不同性别可能切换
衣服子图；人物变形时会隐藏普通服装层。

【复刻设计】建立 `CharacterPortraitComposer`：

```text
PortraitViewport (Control, clip_contents=true)
├── PortraitBackground (TextureRect)
├── BaseBody (Sprite2D)
├── ClothingLayers (Node2D)
│   ├── layer 100 ...
│   ├── layer 200 ...
│   └── layer N ...
└── CosmeticOverlay (Node2D, 首批可空)
```

服装定义至少包含：

```text
item_definition_id
wear_location
dialog_texture
dialog_origin
dialog_anchor
layer
sex_variant
```

不能直接复用世界行走动画作为面板图；原客户端明确区分 `m_sdlgsrc` 与世界素材。

### 4.3 资料与增益

【客户端确认】右侧资料区至少读取：玩家名、综合等级、昵称/称号、组织名、组织职务、属性/阵营、饥饿、威望、信用/声望、居所、击杀数、房屋信息。昵称在打开面板时通过 `GetNickname()` 异步请求，回调后刷新。

资料容器位于 `(193,55)`。旧代码使用 `BaseText`，字段相对 X 为 `2`、首行 Y 为 `5`，后续
基础资料按 18 像素递增。`BaseText` 没有覆盖字体，只继承旧引擎默认 UI 字体；结合同客户端
显式 UI 字体定义，旧版使用宋体；复刻现按用户要求统一为微软雅黑 12 像素、常规字重，默认正文颜色
`#FAF0C8`。因此首行最终坐标为 `(195,60)`，不能用一个多行 Label 依赖现代字体行高自动排版。

旧客户端在资料容器局部 `(2,225)` 创建 `String342` 对应的“查看技能”按钮，即窗口坐标
`(195,280)`。按钮打开独立技能窗口；首批快照固定下发能量炮、维修、驾驶、采矿、烹饪、
裁缝、提炼、制造、火箭、导弹、隐身和雷达 12 项技能及基础等级/装备加成。

服装悬浮说明来自 `ClothClt` 的说明与属性拼接逻辑。服务端安全快照至少提供名称、说明、
购买/出售值、服装等级、受击耐久损耗、技能修正以及当前/最大耐久；客户端只格式化并展示，
不得从素材名推断装备效果。

增益区规则：

- 每行 8 个、共 2 行，图标尺寸 `21×21`。
- 按 `priority` 从高到低排列。
- 上下箭头按“行”翻页。
- 悬停“增益”汇总附加生命、能量炮攻击、导弹攻击、防御。

【复刻设计】首批人物面板不要逐字段发 RPC。登录/状态变化时下发 `CharacterPanelSnapshot`，包含资料、穿着和 buffs；打开面板只读取缓存。只有服务端尚未包含的低频字段才单独请求。

推荐数据结构：

```text
CharacterPanelSnapshot
  identity: player_id, name, sex, comprehensive_level
  social: title, nickname, organization, organization_rank, faction
  progression: hunger, prestige, credit, kill_count
  residence: dwelling, house
  description
  worn_items[]
  buffs[]: icon_id, priority, tooltip, stat_modifiers
```

### 4.4 交互

- 工具栏按钮再次点击关闭；打开时置顶。
- 面板可拖动，窗口缩放时限制在 viewport 内。
- 从背包拖服装到预览区会发出 `EquipClothingIntent(item_instance_id, wear_location)`。
- 客户端先显示拖动幽灵，不立即改权威穿着；服务端确认后同时刷新人物面板和世界人物外观。
- 冻结/干扰状态沿用原作，拒绝打开或操作，并显示原因。

## 5. 背包面板

### 5.1 固定布局与扩展包

【客户端确认】荣耀版 `BagBk.ale` 实际为 `338×469`。`Bag` 根窗口逻辑宽度写为 `667`，用于容纳主背包以及右侧可能打开的旅行包；这不代表背景图应横向拉伸到 667。

主窗口内容：

- 主物品容器 `pbag`。荣耀条件分支下为 `276×295`，每隔 15 像素画辅助网格；另一历史分支为 `298×330`。
- 底部物品数：`(28,410)`。
- 底部星际币：`(28,425)`。
- 整理按钮：`Bag_Arrange.ale`，约 `(259,374)`。
- 关闭按钮：约 `(302,40)`。
- 4 个旅行包入口：X 为 `169/205/241/277`，Y 为 `404`；打开一个附加容器时显示在主包右侧。
- 打开窗口后每 2000 个旧引擎计时单位刷新物品数和货币，并自动打开至少一个已激活旅行包。

【复刻设计】货币和物品数改为信号驱动，不保留 2 秒轮询；表现保持一致即可。

### 5.2 它不是普通定长格子背包

【客户端确认】主包中的物品是容器子对象，各自保留 `x/y`。拖放时 `CheckPos(..., Rect_Bag)` 检查边界与占位冲突，然后由服务端回调决定最终 `pid` 和 `pos`。源码多处以 `>39` 判断主包已满，即首批可以把 40 件作为数量上限，但几何布局仍不是“只存 0..39 槽号”。

【复刻设计】领域模型保留：

```text
InventoryItemPlacement
  instance_id
  definition_id
  amount
  container_id       # main / travel_1..4
  position_px        # 原作兼容坐标
  footprint_px       # 占位矩形
  locked
  bound
  durability
```

UI 可以将位置吸附到 15 像素网格，但存档/协议仍传 `position_px`。以后若确认所有首批物品都只占单格，可以在表现层增加“自动槽位视图”，不要破坏底层兼容模型。

### 5.3 拖放事务

```text
按下物品
  -> 建立 drag ghost，原物品保持权威位置
  -> 本地检查目标容器、边界、重叠、锁定状态
  -> 发送 MoveInventoryItemIntent(instance_id, target_container, target_position, revision)
  -> 服务端检查所有权、容量、占位与当前 revision
     -> accepted: 广播 InventoryDelta，提交位置
     -> rejected: 删除 ghost，恢复原位置并显示原因
```

整理背包同样是服务端命令 `ArrangeInventoryIntent`；结果应返回完整新布局或带新 revision 的批量 delta。不要在每个客户端各自运行整理算法，否则多人/重连后坐标会分叉。

### 5.4 Godot 节点方案

```text
InventoryPanel (Control)
├── Background (TextureRect, 338×469)
├── MainInventoryCanvas (Control)
│   └── ItemViews...
├── TravelBagDock (Control)
├── ItemCountLabel
├── CurrencyLabel
├── ArrangeButton
├── CloseButton
└── TooltipLayer
```

`InventoryPanelPresenter` 只做 snapshot/delta 到视图的映射；边界/重叠的共享规则放在 `domain/inventory`，服务端再执行一次同一规则。ItemView 只负责图标、数量、耐久、锁定角标和拖动手势。

## 6. 战车装备面板

### 6.1 固定布局

【客户端确认】荣耀版背景 `EquipWndBk.ale` 解析为 `604×460`。界面本身已经画出上、下及右侧装备槽外框，中央留给整车预览，最右侧是属性区。

| 区域 | 原位置/尺寸 | 内容 |
|---|---:|---|
| 装备与预览区 | `(3,47)`, `405×391` | 槽位、中央战车合成预览、拖放命中区 |
| 属性区 | `(452,57)`, `140×390` | 聚合属性文本 |
| 关闭按钮 | `(570,40)` | 三态关闭按钮 |
| 背景 | `604×460` | `pic3/interface/EquipWndBk.ale` |

打开面板时依次执行 `EquipCapability()`、`UpdateEquipShow()`、`Refresh()`，然后显示、开启鼠标并置顶。关闭时隐藏并取消临时外观预览。

### 6.2 槽位语义

【客户端确认】旧客户端以 `m_nLocation` 作为权威槽位下标。首批需要明确支持：

| location | 语义 | 说明 |
|---:|---|---|
| 0 | 车体/战车 | 整车基础、生命、即时能量容量等来源 |
| 1 | 主作业位 | 能量炮、维修臂、采集臂等互斥主工具 |
| 2 | 防护装置 | 独立防护设备 |
| 3 | 推进器 | 推进力来源 |
| 5 | 前护甲 | 方向护甲 |
| 6 | 后护甲 | 方向护甲 |
| 7 | 左护甲 | 方向护甲 |
| 8 | 右护甲 | 方向护甲 |
| 13 | 战术设备 | 隐身、雷达、导弹等旧客户端共享位置 |
| 14 | 副武器/发生器 | 补丁设备共用位置 |
| 16 | 联接/控制类 | 后期扩展槽 |
| 17 | 增幅类 | 后期扩展槽 |
| 18 | 原子/能源类 | 后期扩展槽 |

旧源码还明确使用 `19..31`：`19..22` 是撒玛四件、`23` 是防御力场装甲、`24..27` 是奥斯格兰四件、`28..31` 是晶源体四件。三组四件使用不同逻辑位置但复用右侧四行视觉区域；客户端没有跨系列互斥检查，不能凭四格外观简化成四个互斥槽。详细映射、文字及属性公式见 `glory_special_vehicle_equipment.md`。

`m_nEquipKind2` 是装备大类提示：0 战车、1 炮、2 引擎、3 维修、4 挖掘、5 护甲、6 隐身、7 雷达、8 导弹、9 火箭。它适合做“该物品可投到哪些槽”的校验，不能替代 location。

### 6.3 中央预览的合成

【客户端确认】`tankequipwnd` 的 `(3,47)` 只是拖放命中区域；装备类 `EquipInDlg()` 写入的是
整个 `TankEquip` 面板坐标，不能再叠加 `(3,47)`。荣耀版公共偏移为
`RY_EQUIP_OFFSET_X=20`、`RY_EQUIP_OFFSET_Y=30`。首批新兵装备的锚点及 ALE origin 为：

| 装备 | location | 锚点 | ALE origin | 最终左上角 |
|---|---:|---:|---:|---:|
| 新兵战车 | 0 | `(170,200)` | `(-77,8)` | `(93,208)` |
| 新兵能量炮 | 1 | `(170,200)` | `(-32,-16)` | `(138,184)` |
| 初级引擎 | 3 | `(130,385)` | `(-33,-15)` | `(97,370)` |

基础四向护甲的锚点分别为前 `(50,80)`、后 `(330,385)`、左 `(210,385)`、右 `(270,385)`；
最终坐标仍需加各自 ALE origin。不同装备还会调整 Z 顺序，故必须消费配置中的 `z_layer`。

【复刻设计】不要把这些坐标继续散落在装备类脚本里。导出为数据：

```text
VehicleEquipmentVisualDefinition
  definition_id
  slot_location
  dialog_texture
  dialog_origin
  anchor
  z_layer
  body_variant_overrides
```

节点拆分：

```text
VehicleEquipmentPanel
├── Background
├── SlotLayer
│   └── EquipmentSlotView[location]
├── VehiclePreviewComposer
│   ├── PreviewBackground/Shadow
│   └── EquipmentVisualLayers...
├── AttributeList
├── CloseButton
└── TooltipLayer
```

槽里的“物品图标”和中央的“场景/对话框装备图”是不同资产关系；前者使用背包/装备栏图标，后者使用 `m_sDlgSrc` 一类整车叠层素材。详见 `asset_relationships.md`。

### 6.4 右侧属性区

【客户端确认】地面战车属性依次显示：

1. 极限生命/最大生命。
2. 当前生命。
3. 防御力。
4. 前/后/左/右护甲，显示为 `F/B/L/R` 四值。
5. 速度。
6. 能量炮攻击力。
7. 导弹攻击力。
8. 火箭攻击力。
9. 推进力。
10. 输出功率。
11. 重量。
12. 自维修力。
13. 额外自维修力。
14. 额外维修力。
15. 剩余储备能量。

属性容器位于 `(452,57)`，上述行的局部 Y 依次为 `5,25,45,...,305`，字体与人物资料一样
继承旧版 `BaseText`（宋体 12 像素语义；复刻现使用共享微软雅黑）。前/后/左/右护甲只读取 location 5/6/7/8，
未安装方向护甲时应为 `0/0/0/0`，不能把车体的通用防御力复制四次。复刻额外在局部 Y=325
显示工作能量，明确区分旧客户端的储备能量。

原客户端在打开窗口时本地调用一组 `GetUser*` 聚合函数；附加生命、附加防御和三种武器附加攻击在悬停时可显示“基础 + 附加”的拆分。剩余储备能量不是直接读战斗蓝条，而是 `ShowCE()` 向服务端请求，回调 `OnShowCE(ce)` 后填文字。

【复刻设计】服务器的 `VehicleAssemblyCalculator` 产出统一 `VehicleAssemblySnapshot`：

```text
loadout_revision
equipped_items[location]
max_health: base, bonus, total
current_health
defense: base, bonus, total
directional_armor: front, back, left, right
speed
weapon_attack: energy_cannon, missile, rocket
thrust
power_output
weight
self_repair: base, bonus, total
external_repair_bonus
reserve_energy
reserve_energy_capacity
working_energy
working_energy_capacity
```

面板和战斗状态条必须消费同一快照中的生命/能量语义，避免出现面板最大生命与红条分母不一致。客户端可以为 tooltip 保留 base/bonus 分解，但不能自己重算决定战斗结果。

### 6.5 换装事务与联动刷新

```text
从背包拖到装备槽
  -> 本地检查 item category 与 accepted_locations
  -> 发送 EquipVehicleItemIntent(item_instance_id, location, loadout_revision)
  -> 服务端检查等级、驾驶惩罚、互斥槽、重量/功率等约束
  -> 返回新的 InventoryDelta + VehicleAssemblySnapshot
  -> 同一帧刷新：背包、槽位、中央预览、右侧属性、世界战车外观、战斗状态条
```

卸下装备执行反向事务，并先由服务端确认背包可容纳。任何失败都不能只改中央预览而未改装备状态。

## 7. 公共窗口层与数据流

### 7.1 推荐模块边界

```text
scripts/client/ui/windows/
  game_window_manager.gd
  character/character_panel_presenter.gd
  inventory/inventory_panel_presenter.gd
  vehicle/vehicle_equipment_presenter.gd

scripts/client/ui/components/
  draggable_game_window.gd
  item_view.gd
  item_tooltip_presenter.gd
  character_portrait_composer.gd
  vehicle_preview_composer.gd

scripts/domain/inventory/
  inventory_layout.gd
  inventory_transaction.gd

scripts/domain/equipment/
  equipment_slot_registry.gd
  vehicle_loadout.gd

scenes/ui/windows/
  character_panel.tscn
  inventory_panel.tscn
  vehicle_equipment_panel.tscn
```

`game_window_manager` 负责打开/关闭、置顶、窗口边界，以及持有 `CurrentPlayerState` 这一客户端
只读状态投影。它不计算人物或战车属性；每次只原子应用同一个 `transaction_revision` 下的人物、
背包、战车快照。三个面板从该投影的一致快照刷新，不能互相直接改节点，更不能绕过服务器
确认本地换装。

### 7.2 推荐信号

```text
character_panel_snapshot_changed(snapshot)
inventory_snapshot_changed(snapshot, revision)
vehicle_assembly_changed(snapshot, revision)
combat_resource_changed(entity_id, health, working_energy)
window_open_rejected(window_id, reason)
transaction_rejected(transaction_id, reason)
```

装备成功会同时产生 inventory 与 vehicle 两类变化。用同一个服务端 transaction/revision 将它们成组应用，避免一帧内出现物品既在背包又在装备槽、或两边都不在的视觉状态。

## 8. 素材导入清单

首批按需从荣耀版导入：

| 用途 | 荣耀版资源 |
|---|---|
| 人物面板背景 | `pic3/interface/HumanEquipBk.ale`，`355×450` |
| 人物底图 | `pic3/interface/char/manindlg.ale`、`womanindlg.ale` |
| 人物预览底板 | `pic3/interface/char/manbackground.jpg` |
| 增益翻页 | `pic3/interface/LeftBtnOff/On.ale`、`RightBtnOff/On.ale` |
| 背包背景 | `pic3/interface/BagBk.ale`，`338×469` |
| 背包整理 | `pic3/interface/Bag_Arrange.ale` |
| 旅行包 | `pic3/interface/mbag1_Bk.ale` 至 `mbag4_Bk.ale` 及对应按钮 |
| 战车装备背景 | `pic3/interface/EquipWndBk.ale`，`604×460` |
| 通用关闭按钮 | `pic3/interface/form/closebuttom.ale` |
| 人物穿着预览 | 每件衣服的荣耀版 dialog 素材及 layer/origin 元数据 |
| 战车预览 | 每件战车装备的荣耀版 dialog 素材及 anchor/z-layer 元数据 |
| 物品图标 | 对应物品的背包图标，不用场景内多向动画代替 |

导入后的运行时路径必须使用业务名，例如 `assets/ui/windows/inventory/background.png`，不能把 `pic3`、ALE 时间戳或 FCC 类名泄漏到业务代码。原文件名和出处写入 manifest 的 `source` 字段。

## 9. 分模块提交计划

遵守项目约束：每完成一个模块立即提交，每次不超过 20 个文件、总变更不超过 2000 行。建议顺序：

1. **战车状态条校准**：状态快照字段、有效生命上限、蓝条可见性、测试。
2. **公共窗口层 + 人物面板**：窗口管理、人物快照、预览合成、增益区、测试。
3. **背包领域模型**：位置/占位/revision、服务端事务、纯领域测试。
4. **背包面板**：背景、ItemView、拖放幽灵、整理按钮、UI 测试。
5. **战车装备领域模型**：location 注册表、loadout 与聚合快照、测试。
6. **战车装备面板**：槽位、中央预览、属性区、换装联动、UI/集成测试。

每个模块的素材提交应和第一次消费该素材的代码放在同一个提交；若某模块素材数量导致超过 20 文件，先提交一个“素材导入批次”，再提交逻辑，但单个提交仍必须保持可验证。

## 10. 验收标准

### 10.1 战斗条

- 本地战车显示 `50×4` 红条和其下方 `50×4` 蓝条；远端战车只显示红条。
- 附加生命改变后，面板最大生命与红条分母一致。
- 发炮后蓝条立即预测下降，服务端快照能平滑校正。
- 底部储备能量改变不会被误画到战车蓝条。

### 10.2 人物面板

- 男/女底图正确，衣服按 layer 叠加且 ALE origin 对齐。
- 更换衣服后，人物面板与世界角色同时更新。
- 资料字段和增益图标来自 snapshot；增益按优先级分页。
- 面板可拖动、置顶、关闭，缩放窗口后不会丢到屏幕外。

### 10.3 背包

- 主包最多 40 件；位置和占位在重连后保持。
- 非法重叠、越界、锁定物品移动会被拒绝并回滚。
- 堆叠数量、物品数、货币通过状态变更立即刷新。
- 装备/卸装事务不会造成重复物品或短暂丢失。

### 10.4 战车装备

- location 0/1/2/3/5/6/7/8/13/14 正确限制装备大类。
- 中央预览使用场景装备图分层，不使用背包小图放大。
- 右侧属性与服务端 assembly snapshot 一致，并可显示基础/附加拆分。
- 换装后背包、装备槽、预览、属性、世界战车和战斗条原子刷新。

## 11. 尚未由客户端单独证明的部分

- 旧引擎 `timer(30)` 的精确现实时间单位；不影响按“数据就绪后显示”复刻。
- 旧服务端即时能量恢复的精确频率和输出功率换算系数；当前值仍应作为可调服务端规则。
- 编译时 `dzl_IFLZSERVER_DEFINE` 是否对最终荣耀客户端启用；主包的两套几何分支都已记录，实际背景尺寸与当前荣耀资源已确认。
- 后期 location 19..23、28..31 的全部业务名和首批必要性；首批只要求协议兼容未知槽，不要求显示这些活动槽。
- 外观背景、人物变形、装备皮肤、晶石和大量后期活动 buff 属于后续功能，不应阻塞首批四块界面。
