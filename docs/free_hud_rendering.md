# 免费版 HUD/UI 渲染结构

本文记录免费版客户端的顶部栏、底部栏、快捷栏和小地图 HUD，并作为 `starhome_remake` 的 HUD 外观实现依据。玩法、地图、角色和其他业务素材仍以荣耀版为基线。

2026-09-15 用户指定精简顶部工具栏：当前实现已改为 326×82 的两行四列代码按钮。
下面的原版布局与素材记录保留为历史证据，当前入口与功能见[日常活动与智脑](daily_activities_and_smart_assistant.md)。

## 1. 素材版本豁免

> **项目级例外：HUD 外观允许使用免费版 `starhome_lz_fr` 素材；2026-09-07 用户另指定任务日志、商城，并允许用户列表免费版回退。**

本例外只覆盖：

- 顶部工具栏背景、收展按钮及工具栏按钮状态图。
- 底部主控制栏背景、武器模式格、储备能量条和底部菜单按钮。
- 底部物品/技能快捷栏背景、翻页按钮和快捷格 UI。
- 小地图边框、坐标/地图名区域及大小、收展等控制按钮。
- 底栏系统设置菜单、免费版任务日志和商城 UI；用户列表逻辑已在荣耀脚本找到，通用窗口边框因荣耀本地素材缺失采用免费版回退。细节见 [底栏窗口实现](bottom_menu_windows.md)。

本例外明确**不覆盖**：

- 小地图实际显示的地图 JPG、地图数据和标记业务数据。
- 地图、角色、NPC、怪物、战车、装备、物品、特效和音频。
- 点击 HUD 后打开的人物、背包、战车装备、普通 NPC 商店等未单独获准的弹窗内容。
- 其他免费版活动、VR、运营界面素材；商城例外不包括商品素材及支付业务。

上述内容继续只能从荣耀版 `starhome_lz_ry` 导入。免费版 HUD 素材也必须进入业务化目录并登记 `source_release: starhome_lz_fr`；运行时代码不得出现 `pic`、`pic2`、ALE 原名或免费版目录结构。

## 2. 总体布局

【免费版客户端确认】免费版 HUD 由四个互相配合的区域组成：

| 区域 | 客户端对象 | 锚点 | 主要职责 |
|---|---|---|---|
| 顶部工具栏 | `TopMenu` | 右上，小地图左侧 | 系统消息、帮助、组队、返回基地、自修等按钮 |
| 底部主控制栏 | `base_ctrlpad` | 底边水平居中 | 武器模式、总能量、人物/背包/装备/任务等菜单 |
| 底部快捷栏 | `VGeneralShortcutBar` | 主控制栏上方，默认居中 | 物品与技能快捷格，可收起和拖动 |
| 小地图 | `sdmap` | 右上 | 专用地图 JPG、角色居中视口、坐标、地图名与缩放 |

这套布局不是整张不可交互截图：底部主背景和顶部背景负责连续外框，各按钮仍是独立三态 ALE；快捷栏和小地图也有独立子控件。

窗口放大时，HUD 继续使用固定像素尺寸并吸附屏幕边缘，地图摄像机扩大可视范围。不要随窗口拉伸 `mainctrlpad_1024.png`、按钮或小地图框。

## 3. 顶部工具栏

### 3.1 创建与锚定

主要逻辑位于：

```text
outputs/starhome_lz_fr_fcc_source/dzl/face_addmain_common_dzl.fcc
```

`dzl/face_addmain.fcc` 会直接调用 `ShowTopMenu()`，后者实际创建 `TopMenu`。这与荣耀版恢复脚本中默认隐藏、入口不明确的旧栏不同：免费版顶部栏是活跃 HUD。

展开状态使用：

```text
pic2/topmenu/topmenuback_0.ale
```

解析结果为 `327×54` 单帧背景。展开后的控件尺寸约 `330×54`，紧贴窗口顶部；其右边缘根据当前小地图宽度动态放在小地图左侧：

```text
top_menu_right = viewport_width - minimap_width
```

小地图切换大小或收起时会再次调用 `OnSethalign`，因此顶部栏不会和小地图重叠。

### 3.2 双行按钮网格

按钮采用约 38–39 像素横向间隔，两行的 Y 坐标分别为 0 和 26。绝大多数按钮 ALE 含三帧：

| 帧 | 状态 |
|---:|---|
| 0 | 正常 |
| 1 | 悬停/释放 |
| 2 | 按下 |

第一行已确认位置：

| X | 素材 | 原功能 |
|---:|---|---|
| 18 | `btn_systemmsg.ale` | 系统消息 |
| 56 | `btn_help.ale` | 帮助 |
| 94 | `btn_looktem.ale` | 队伍 |
| 133 | `btn_backhome.ale` | 返回基地 |
| 172 | `btn_repaireself.ale` | 自我维修 |
| 211 | `btn_CreatNpc.ale` | 召唤/相关 NPC 功能 |
| 250 | `btn_ng.ale` | 内挂/战斗辅助 |
| 289 | `VR_Room.ale` | VR 竞技场 |

第二行已确认素材包括 `btn_Guard.ale`、`YSHXCountBtn.ale`、`PivotControlWnd.ale`、`Explore.ale`、`MercenaryMissionWnd.ale`、`btn_UserExperienceMission.ale`、`TJ_Shop.ale` 和 `FBBtn.ale`。它们主要是免费版后期系统与运营入口。

【重建规则】首批只导入蓝色背景、收展按钮，以及确实进入首批玩法的系统消息、帮助、队伍、返回基地和自修按钮。VR、商城、异兽幻星、副本、佣兵任务等暂不导入；将来启用功能时再按需添加。

### 3.3 收起与展开

- 收起按钮：`btn_topmenuso.ale`。
- 展开按钮：`btn_topmenufa.ale`。
- 展开尺寸约 `330×54`。
- 收起后尺寸约 `12×26`，只留下展开按钮。
- 状态写入免费版 `SaveSetting_fr.ini` 的 `topTools`。

复刻中将该状态保存为 `top_menu_expanded`，不沿用旧 INI 文件名。

## 4. 底部主控制栏

### 4.1 背景和锚点

核心类 `base_ctrlpad` 位于：

```text
outputs/starhome_lz_fr_fcc_source/menupart_main_common_dzl.fcc
```

主背景为：

```text
pic2/ctrlpad/mainctrlpad_1024.png
```

原图尺寸为 `1024×29`。客户端控制对象预留 `1024×100`，但可见主条贴近窗口底部，水平中心锚定；额外高度用于挂接聊天输入、菜单和快捷栏，不应把背景拉成 100 像素高。

【重建规则】Godot 使用一个底部全宽停靠容器承载原始 `1024×29` 中央背景：

- 宽度不满 1024 时按最低分辨率策略裁切两端。
- 宽度大于 1024 时保持中央图 1:1，不横向拉伸；两侧用背景端部或纯色延伸到窗口边缘。
- 所有按钮以 1024 宽设计坐标相对中央背景定位。

### 4.2 左半区：储备能量和武器模式

储备能量条素材为：

```text
pic2/ctrlpad/EnergyBar.ale
```

它有两帧，单帧约 `323×3`，位于主条 `(125, 3)`。显示宽度按下式裁切：

```text
显示宽度 = 323 × 当前储备能量 / 储备能量上限
```

充满或低于约 10% 时会在两帧之间闪烁，并显示当前值/上限提示。

武器/动作格的设计位置为：

```text
主序列 X = 178, 206, 234, 262, 290, 318
附属序列 X = 346, 384, 406, 428
Y = 8
```

装备以自身按钮 ALE 动态注册；选中帧为 1，未选中帧为 0，弹药数量用独立红色文字叠加。部分主序列格可拖动换位，当前选择原保存在 `CtrlPadConfig_fr.ini` 的 `CurWeapon`。

【客户端确认】能量炮使用独立固定按钮。火箭炮、导弹、隐身器和雷达都声明为装备 `Location=13`，四者互斥；它们在 `EquipInDlg` 时调用控制栏 `AddWeapon`，卸装时由 `RemoveWeapon` 删除。因此第二格是一个由实际装备动态创建的战术槽，没有安装对应装备时必须为空，不能把导弹图标或数量写死在 HUD 中。弹量等数量文字是按钮上方的独立红色文本层。

【素材对应】免费版战术按钮依次使用 `pic/equipface/firegun.ale`、`missile.ale`、`tank_hermit.ale`、`tank_radar.ale` 的普通/选中两帧。运行时清单只暴露 `rocket_launcher`、`missile`、`stealth`、`radar` 四个业务标识。

### 4.3 右半区：菜单按钮

免费版底栏按钮一般为三态 ALE，高度约 29 像素。已确认位置如下：

| X | 素材 | 原功能 |
|---:|---|---|
| 519 | `btn_humanwnd.ale` | 人物 |
| 557 | `btn_humanbag.ale` | 背包 |
| 598 | `btn_humanequip.ale` | 战车装备 |
| 635 | `btn_skysource.ale` | 天阵系统 |
| 673 | `btn_pizza.ale` | 命运星盘 |
| 711 | `btn_playerfriend.ale` | 好友 |
| 753 | `btn_look.ale` | 当前场景玩家 |
| 790 | `btn_playertask.ale` | 任务 |
| 827 | `btn_spacemap.ale` | 星图 |
| 865 | `btn_askgm.ale` | GM 反馈 |
| 903 | `btn_system.ale` | 系统 |
| 945 | `shopping.ale` | 商城 |

聊天框收展按钮位于约 `(449, 0)`，在 `showmsgwnd.ale` 与 `closemsgwnd.ale` 之间切换。

【重建规则】首批导入人物、背包、战车装备、好友、当前场景玩家、任务、星图和系统。天阵、命运星盘、GM 反馈及商城不导入；对应位置可以空置，背景仍保持原免费版观感。

## 5. 底部物品/技能快捷栏

`VGeneralShortcutBar` 位于 `ven/shortcuttoolbar.fcc`，背景为：

```text
pic/shortcutbar/generalbar.ale
```

素材尺寸为 `415×40`。默认跟随主控制栏，位于其上方并以主栏中心为参考；用户可以拖动，偏移量原写入用户 INI，也可整体隐藏。

快捷栏内部不是一张死图：

- 物品区为 5 列、2 页，共 10 个数字热键格；可拖入物品，右键清除。
- `PageUpBtn.ale`、`PageDownBtn.ale` 控制页切换。
- 物品数量用独立红字绘制并周期刷新。
- 技能区有独立页和冷却遮罩。
- 隐藏/显示按钮使用 `shortcutbtn.ale`、`shortcutbtn1.ale`。

【重建规则】首批只实现一页物品格和一页战斗/工具快捷格，但数据模型保留分页；快捷栏默认底部居中，可拖动功能以后再开放。

## 6. 右上小地图

### 6.1 地图内容来源

小地图由 `NewOneSmap` 延迟创建，加载：

```text
LOCAL_SMAP_PATH + mapsn + ".jpg"
```

若 `mapsn` 为空，则使用服务器地图名。小地图显示的是专门制作的地图 JPG，不是运行时缩放完整场景。

> 免费版素材豁免只涵盖小地图 HUD 外框和控制按钮。实际地图 JPG 必须继续使用荣耀版当前地图对应资源；免费版地图 JPG 不得导入。

### 6.2 小模式

【免费版客户端确认】小模式参数：

- 总控件约 `125×165`，贴右上角。
- 地图视口约 `120×120`，位置 `(1, 1)`。
- `viewcenter=1`，始终以玩家为中心。
- 地图透明度约 200，点标记模式开启。
- 底部控制区从 Y≈120/122 开始。
- `pic2/smap/ditu.ale` 提供控制区背景。
- 坐标显示在约 `(10, 4)`，地图名在约 `(0, 24)`，地图名使用绿色。
- 大小切换按钮约位于 `(90, 5)`，收展按钮约位于 `(105, 5)`。

原版还在 `(74, 7)` 放置“屏蔽其他玩家特效”开关；它与地图导航无关，首批不导入。

### 6.3 大模式与收起状态

- 小模式状态值为 1，大模式为 3。
- 大模式直接使用专用 JPG 的原始宽高，而不是固定放大倍率。
- 收起后只保留约 `125×41` 的坐标/控制区，地图视口隐藏。
- 大小状态原写入 `SaveSetting_fr.ini` 的 `smap_type`。
- 每次大小或收展变化后，都重新计算顶部工具栏的右侧锚点。

复刻中把专用地图图、玩家标记、队友/NPC 标记、地图名、坐标和控制框分层绘制。小地图底图不应包含运行时标记。

## 7. 双能量显示与数据边界

HUD 外观改用免费版，不改变已经确认的能量模型。统一术语如下：

| 中文名 | 复刻字段 | 原客户端字段 | UI |
|---|---|---|---|
| 储备能量 | `reserve_energy` | 玩家 `m_nCurEnergyBox` | 免费版底部 `323×3` 总能量条 |
| 储备能量上限 | `reserve_energy_capacity` | 车体 `m_nmaxenergy` | 总能量条满值 |
| 工作能量 | `working_energy` | 车体 `m_ncurenergy` | 战斗地图中红色耐久条下方的蓝条 |
| 工作能量容量 | `working_energy_capacity` | 车体 `m_nenergy` | 蓝条满值 |
| 输出功率 | `power_output` | 车体 `m_noutpower` | 设备负载预算，不等同于任一能量池 |

【客户端确认】进入战斗地图并装配车体时，工作能量初始化为容量上限。能量炮、导弹、火箭炮、雷达和引擎等会检查并扣工作能量。

`OnAddEnergy(amount)` 接收远端增量并恢复工作能量；`OnEnergyChange(energy, curenergybox)` 用服务端绝对值同时覆盖工作能量和储备能量。现有客户端没有提供输出功率到蓝条恢复量的服务端公式。

【重建规则】首批暂用：

```text
工作能量恢复率 = 有效输出功率 × working_energy_regen_factor
默认 working_energy_regen_factor = 1.0
恢复 1 点工作能量消耗 1 点储备能量
储备能量为 0 时停止恢复
```

容量、恢复率和并发功率预算必须保持三个独立字段，便于以后替换原服公式。

## 8. Godot 目标结构

```text
CanvasLayer (HudLayer)
└── Control (HudRoot, Full Rect)
    ├── Control (TopMenu, Top Right, beside MinimapDock)
    ├── Control (MinimapDock, Top Right)
    ├── Control (BottomMainBar, Bottom Center)
    │   ├── TextureRect (1024×29 background)
    │   ├── TextureProgressBar (reserve energy)
    │   ├── Control (weapon/action slots)
    │   └── Control (individual menu buttons)
    ├── Control (GeneralShortcutBar, above BottomMainBar)
    └── Control (WorldStatusOverlay)
        └── vehicle health/working-energy bars
```

实现约束：

- HUD 保持固定像素尺寸；窗口变化只扩大世界视口。
- 顶栏和小地图吸顶，底栏吸底。
- 顶栏右边缘跟随小地图宽度。
- 每个三态 ALE 都转换为独立按钮状态，不把整栏背景当按钮。
- 储备能量条使用裁切而非缩放，保持 3 像素高度。
- 战车红/蓝条跟随世界对象，但不参与场景 Y 排序。
- UI 只订阅权威状态，不在控件脚本中自行结算能量。

建议持久化：

```text
hud_visible
top_menu_expanded
minimap_size
minimap_collapsed
selected_action_slot
shortcut_page
shortcut_visible
item_shortcuts[10]
```

## 9. 工程迁移状态

免费版 HUD 迁移已经完成：

1. `data/ui/free_hud_assets.json` 只登记本文第 1 节允许的 30 个免费版 HUD 来源，
   `source_release` 明确为 `starhome_lz_fr`。
2. 顶部菜单、底部主栏、通用快捷栏和小地图控制区均已按业务语义拆为独立控件与按钮；
   运行时代码不含原版 `pic/pic2` 或 ALE 名称。
3. 小地图内容仍使用当前荣耀版地图 JPG，双能量数据模型和全部非 HUD 资源保持荣耀版来源。
4. 旧 `glory_hud_assets.json`、荣耀 HUD 专用脚本、导入器、测试和运行资产已删除，不保留双实现。
5. `tests/ui/runtime/hud_runtime_smoke_test.gd` 覆盖 1280×720、1600×900、大小地图、
   收展联动、能量裁剪和武器选中，共 43 条断言。

## 10. 主要证据位置

| 内容 | 恢复源码/资源 |
|---|---|
| 顶部栏及创建入口 | `outputs/starhome_lz_fr_fcc_source/dzl/face_addmain_common_dzl.fcc`、`dzl/face_addmain.fcc` |
| 底部主栏、武器槽、总能量条、小地图创建 | `outputs/starhome_lz_fr_fcc_source/menupart_main_common_dzl.fcc` |
| 小地图样式和状态切换 | `outputs/starhome_lz_fr_fcc_source/menupart_main_style.fcc` |
| 物品/技能快捷栏 | `outputs/starhome_lz_fr_fcc_source/ven/shortcuttoolbar.fcc` |
| 免费版解析 HUD 素材 | `outputs/starhome_lz_fr_full_parsed/ale_sprites/pic2/topmenu/`、`pic2/ctrlpad/`、`pic/shortcutbar/` |
| 底部 1024 背景 | `outputs/starhome_lz_fr_full/raw/pic2/ctrlpad/mainctrlpad_1024.png` |
| 双能量同步与装备扣能 | `outputs/starhome_lz_ry_fcc_source/mainclient_char.fcc`、`cltobj/equipclt.fcc`、`cltobj/appendequipclt.fcc` |
