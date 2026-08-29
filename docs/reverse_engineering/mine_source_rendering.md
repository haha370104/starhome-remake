# 荣耀版矿源网络数据与客户端渲染链路

## 1. 结论

荣耀版的矿源是服务端权威的远程场景对象，不是客户端读取地图文件后自行生成的静态装饰。

客户端收到矿源对象后，整体流程是：

```text
服务端创建远程矿源对象
  │  对象类型：铁矿源 / 铜矿源 / 硅矿源……
  │  创建参数：(x, y, curcontent, content)
  ▼
客户端实例化相同名称的矿源子类
  ▼
BaseMineSource.OnRemoteCreate(...)
  ├─ 子类决定 ALE、调色板和悬浮说明
  ├─ 设置随机初始帧与透明度
  ├─ 设置世界坐标并参加 Y 轴深度排序
  ├─ 保存当前储量与最大储量
  └─ 显示矿源、启用鼠标交互
```

最重要的实现结论如下：

1. 网络创建参数只有 `x`、`y`、`curcontent` 和 `content`；矿种不在这四个参数里，而是由远程对象的类名决定。
2. `curcontent/content` 不参与图片、帧、透明度、尺寸或调色板选择。原客户端没有“矿越挖越小”的视觉阶段。
3. 大多数早期矿源共用同一套 7 帧岩石 ALE，通过 `.act` 调色板区别矿种；后期矿物有独立 ALE。
4. 普通矿源会随机选一个外形帧并随机设置少量透明度，以避免同屏矿石完全一致。
5. 荣耀版没有把矿源写进本地寻路阻挡；激战版曾启用九点阻挡，两版逻辑不同。
6. 服务端控制矿源的身份、坐标、储量变化和消失；客户端控制图片表现、悬浮提示、点击预检和收到服务端许可后的挖掘动画。

## 2. 证据范围

主要依据：

- `starhome_lz_ry_fcc_source/mineclt.fcc:5-268`
- `starhome_lz_ry_fcc_source/client_include.fcc:91-171`
- `starhome_lz_ry_fcc_source/cltplayer/collector.fcc:4-69`
- `starhome_lz_ry_fcc_source/cltobj/equipclt.fcc:4931-4999`
- `starhome_lz_ry_fcc_source/great/code_string.fcc:342-353`
- `starhome_lz_ry_full_parsed/catalogs/mines/glory_ore_catalog.json`
- 对照版本：`starhome_jznp_full_parsed/ftc_resources/expanded/mineclt/mineclt.fcc.cab`

地图内能看到类似下面的记录：

```text
//AddImgEx('NewMinePosition', ..., 2256,2736, ..., '硅矿源 3 2 1200 20 100');
```

但这些行已经被注释，例如 `NFT_BL/map/c07.fcc:605`。它们可用于恢复策划曾配置过的矿种和大致点位，不能视为运行时客户端创建指令。运行中的矿源由远程对象创建链路提供。

本地没有服务端矿源类及底层远程对象协议实现，因此不能从 FCC 直接恢复字节级包格式。本文所说的“服务端数据契约”是由客户端远程入口签名及后续使用方式确认的语义契约。

## 3. 客户端类如何进入地图环境

`client_include.fcc` 是客户端主地图类的组成部分。根据 `_GF.m_nIncludeKind`，部分地图模式会执行：

```text
Run($+"mineclt.fcc");
```

荣耀版至少在 `IncludeKind=-1、0、5` 时加载矿源类。因此，服务端创建“铁矿源”等远程对象之前，客户端地图环境已经注册了对应类。

`BaseMineSource` 继承自引擎的 `img`：

```text
class BaseMineSource:img
```

具体矿源类只继承该基类，并覆盖资源、调色板或提示文字。远程对象框架根据服务端对象类型创建正确的客户端子类，再调用该类继承到的 `OnRemoteCreate`。

## 4. 创建数据契约

荣耀版入口为：

```text
void OnRemoteCreate(int x, int y, int curcontent, int content)
```

字段语义：

| 字段 | 客户端用途 | 是否影响画面 |
|---|---|---|
| 远程对象类型 | 选择矿源子类，进而决定 ALE、调色板和提示文字 | 是 |
| 远程对象 ID | 后续采矿请求和更新时标识同一个矿源 | 不直接影响 |
| `x` | 世界锚点 X | 是 |
| `y` | 世界锚点 Y，也是自动深度排序依据 | 是 |
| `curcontent` | 当前剩余储量，保存到 `m_ncurcontent` | 否 |
| `content` | 总储量，保存到 `m_ncontent` | 否 |

建议复刻协议不要继续依赖中文类名，使用稳定业务 ID：

```json
{
  "event": "mine_spawned",
  "entity_id": "mine.10482",
  "mine_type": "iron_ore",
  "position": [2256, 2736],
  "current_content": 50,
  "capacity": 50
}
```

这和原版语义等价，只是把隐含在远程类身份中的矿种显式化。

## 5. `OnRemoteCreate` 的逐步渲染行为

原逻辑等价于：

```text
texture      = subclass.base_source
frame        = random(7)
position     = (x, y)
current      = curcontent
capacity     = content
palette      = subclass.palette
visible      = true
after 1000ms = force map redraw
```

### 5.1 图片与帧

基类默认图片是：

```text
pic3/mine/CHN_2005_06_28_18_53_17_960.ale
```

该 ALE 有 7 帧。这里的帧不是“剩余量阶段”，而是七种岩石外形变体。创建时执行 `frame=rand(7)`，让同种矿源随机呈现不同形状。

后期独立 ALE 可能只有 4 帧或多达 32 帧。代码仍在基类写入随机帧；越界后的具体取模或钳制属于旧引擎行为，FCC 中没有实现。复刻时应按实际帧数随机：

```gdscript
sprite.frame = rng.randi_range(0, sprite_frames.get_frame_count("idle") - 1)
```

不要把固定的 `7` 原样搬进新引擎。

### 5.2 调色板

基类在设置 ALE 后执行：

```text
linkpalette = m_pPalette
```

早期矿物因此能共用同一份索引色图片，只替换 `.act` 调色板。矿种到素材的主要映射为：

| 矿种 | 世界 ALE | 调色板 |
|---|---|---|
| 金、铁、铜、银、硅、石墨、能量、宝石 | `CHN_2005_06_28_18_53_17_960.ale` | 各自 `.act`；铁和宝石在荣耀代码中复用同一调色板 |
| 铬、镍、锌、镭 | `KL_mine.ale` | `gek/niek/xink/leik.act` |
| 藏宝矿 | `gem.ale` | 无 |
| 神秘宝藏 | `SecretMine.ale` | 无 |
| 镁、钡 | `meikuang/beikuang.ale` | 无 |
| 钒、钴、钼、钽 | `fankuang/gukuang/mukuang/tankuang.ale` | 无 |
| 紫、红、蓝、绿水晶矿 | 各自 `*shuijingkuang.ale` | 无 |

Godot 中有两种可行消费方式：

- 简单方案：导入阶段把 ALE 与 ACT 合成为每种矿独立的 PNG/SpriteFrames。
- 保真方案：保留索引纹理，在 shader 中用调色板纹理查色。适合以后做换色，但工程复杂度更高。

第一批复刻没有动态换矿色的玩法，推荐预烘焙；运行时仍应保留 `mine_type -> presentation` 注册表，不要把图片路径放进网络消息。

### 5.3 透明度与空间排序

基类初始化：

```text
alpha = 200 + rand(55)
autozorder = 1
fixshow = 0
```

含义是：

- 每个矿点透明度约为 `200..254 / 255`，制造轻微个体差异。
- `autozorder=1` 让矿源按世界 Y 坐标参与场景深度排序；玩家从矿源后方经过时应被矿源遮挡，从前方经过时应遮住矿源。
- `fixshow=0` 表示它属于世界空间，不是固定在屏幕上的 HUD。

Godot 对应实现应把矿源放入与玩家、NPC、场景遮挡物相同的 YSort 世界层。不要把矿源贴进地图背景图片，否则无法形成正确的前后遮挡。

### 5.4 动画

基类先后写入 `playdelay=1` 和 `playdelay=0`，最终普通矿源表现为静态随机帧。

四色水晶矿子类把 `playdelay` 覆盖为 `38`，其 ALE 各有 32 帧，显然是持续动画矿源。`38` 是旧引擎播放延时单位，FCC 未证明它等于毫秒；复刻前应以原客户端录像测量实际 FPS，不应直接写成 `1000/38 FPS`。

### 5.5 一秒后的强制重绘

荣耀版创建后调用：

```text
TimerCall(1000, "CheckShow")
```

`CheckShow` 会把 X 坐标减 1、再次设为显示，并将地图 `invalid=1`。这是旧渲染器的失效刷新补丁，不是玩法规则。

Godot 的节点属性更新会自动触发重绘，因此不应复刻这次一像素位移。服务端给出的 `(x,y)` 应作为最终逻辑锚点。

## 6. 悬浮、点击与小地图表现

基类属性及鼠标回调为：

```text
pointmode=1
mapshowmode=0
OnMouseIn  -> showmode=1
OnMouseOut -> showmode=0
```

据同引擎其他对象的使用方式：

- `pointmode=1` 使矿源参与鼠标命中。
- `showmode` 在鼠标进入时打开引擎的高亮/提示模式，离开时关闭。
- 子类 `tooltips` 提供“铁矿，需要采矿等级10级”一类文本。
- `mapshowmode=0` 表示矿源不生成小地图点。矿源只能通过小地图底图或玩家记忆发现。

荣耀版提示文字直接写要求等级，不根据当前玩家等级改颜色。激战版后来的 `showtips()` 会读取玩家采矿等级并生成“可采集/不可采集”差异提示，这是补丁版行为，不属于荣耀版基线。

右键点击矿源不执行矿物操作，而是转发给地图视图的右键移动逻辑。左键点击时：

1. 客户端检查当前选中的装备对象是否存在。
2. 若装备的 `m_sname == "collector"`，进入 `MainPlayer.Collect(this)`。
3. 否则把点击继续交给地图视图。

## 7. 采矿请求和表现反馈

普通矿源没有 `IfCanCollect`，所以 `Collect` 在客户端先检查玩家到矿源的距离必须在 `20..70` 之间。随后检查冻结/干扰状态及其他禁止状态，再发送：

```text
r_OnCollect(mineobj.ClientID(), m_ncurequip)
```

这说明采矿请求携带：

- 被采矿源的远程对象 ID；
- 当前使用的装备槽编号。

距离检查只是客户端即时反馈，不能替代服务端校验。

服务端接受后回调玩家的 `OnBeginCollect(eqno,idnum)`。客户端再次：

1. 用 `ClientID2Obj(idnum)` 解析矿源；
2. 确认车体和指定装备仍存在；
3. 确认装备仍是 `collector`；
4. 设置 `m_nIfCollectting=1`；
5. 让挖掘臂朝向矿源；
6. 循环播放挖掘臂 `move` 动画和声音。

因此挖掘动画不是点击瞬间无条件播放，而是在服务端确认开始后播放。停止时服务端或客户端调用 `OnStopCollect`，复位状态并停止动画/循环音效。

## 8. 储量变化和矿源消失

客户端暴露两个远程更新入口：

```text
OnChangeContent(curcontent) -> m_ncurcontent = curcontent
OnDie()                     -> show = 0
```

全量客户端源码中没有本地调用 `OnChangeContent`，因此它应是服务端对远程矿源的状态推送入口。

需要特别注意：

- `OnChangeContent` 只修改整数，不刷新帧、图片、动画速度、透明度或 tooltip。
- `curcontent == 0` 时是否立即调用 `OnDie` 由服务端决定；客户端没有自行判断。
- `OnDie` 只隐藏表现，远程对象的最终销毁仍由网络对象生命周期管理。

复刻协议建议拆成：

```text
mine_spawned
mine_content_changed
mine_depleted / entity_removed
```

客户端收到 `mine_content_changed` 后只更新领域快照；除非新设计明确要求，否则不要创造原版不存在的矿量视觉阶段。

## 9. 矿源是否阻挡移动

荣耀版 `OnRemoteCreate` 中的 `SetNoGo()` 已被注释，`OnDestroy` 中恢复通行的代码也整体被注释。因此荣耀版矿源不动态修改地图寻路网格。

被保留但未执行的九点阻挡算法覆盖：

```text
(x, y)
(x±50, y)
(x, y±25)
(x±25, y±13)
```

激战版重新启用了 `SetNoGo()`，并在销毁时恢复九个点。这是明确的版本差异，不应把激战版行为误套到荣耀版复刻。

首批复刻按荣耀版处理：矿源有鼠标命中区域，但不进入导航障碍层。如果实际体验证明战车不能从矿石图像上穿过，再把碰撞作为可配置地图规则，而不是修改全局矿源基类。

## 10. 推荐的 Godot 分层

```text
服务端
  MineAggregate
    - entity_id
    - mine_type
    - position
    - current_content
    - capacity
    - authoritative collection validation

客户端领域投影
  MineSnapshotStore
    - 只接受权威 spawn/update/remove

客户端表现
  MineWorldController
    - entity_id -> MineWorldView
  MinePresentationCatalog
    - mine_type -> SpriteFrames / palette / tooltip / animation policy
  MineWorldView (YSort world node)
    - sprite
    - hover hit area
    - tooltip
    - optional selection highlight
```

推荐处理顺序：

1. 网络层把远程事件转换为纯 DTO，不接受服务端资源路径。
2. `MineSnapshotStore` 按 `entity_id` 更新权威状态。
3. `MineWorldController` 创建、更新或删除表现节点。
4. `MinePresentationCatalog` 用 `mine_type` 选择本地荣耀版素材。
5. 创建时随机静态变体和透明度；四色水晶启动循环动画。
6. 数量更新不重建节点。
7. 点击只上报矿源 ID；距离、装备、等级、储量和奖励均由服务端最终判定。

## 11. 确认度边界

| 结论 | 确认度 | 依据 |
|---|---|---|
| 创建参数为位置、当前量、总量 | 已确认 | `OnRemoteCreate` 签名及赋值 |
| 矿种由远程类身份决定 | 已确认 | 每个矿源子类覆盖表现，参数中无矿种 |
| 剩余量不改变画面 | 已确认 | `OnChangeContent` 仅赋值，字段无其他读取 |
| 服务端确认后才播放挖掘动画 | 已确认 | `r_OnCollect` 与 `OnBeginCollect` 调用链 |
| 荣耀矿源不写寻路阻挡 | 已确认 | `SetNoGo` 和恢复代码均被注释 |
| `mapshowmode=0` 表示不画小地图点 | 高可信 | 与同引擎 `mapshowmode=1 + mapshowcolor` 对照 |
| 旧引擎对 4 帧 ALE 接收 `frame=rand(7)` 的精确行为 | 未确认 | 行为位于闭源运行容器 |
| `playdelay=38` 的真实时间单位 | 未确认 | FCC 只有配置值，没有引擎计时实现 |
| 服务端远程对象的字节级网络格式 | 未确认 | 服务端源码和引擎网络实现缺失 |
