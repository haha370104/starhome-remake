# 地图资源离线解析与运行时消费

阶段 2 已提升到运行时目录的真实地图链路、出生点证据等级、G08 五出口门禁与当前素材缺口，
见[阶段 2：荣耀版地图图谱种子](./stage2_map_graph_seed.md)。

本文记录 FancyBoxII 老客户端地图资源的来源、离线解析方式，以及
`starhome_remake` 在 Godot 中的消费约定。结论来自客户端文件、引擎 DLL
导出的 PKH 解压函数和实际数据交叉验证；没有抓游戏内存，也不依赖登录器或服务器。

## 1. 现在的大厅地图来自哪里

当前工程中的“易安港基地大厅一层”已经完整切换为荣耀版 `RoomSvr1` 的
`variant_02_nft_bt`（脚本分支 `NFT_BT/NFT_SK`）：

- 地图脚本与结构化结果：`starhome_lz_ry_maps_parsed/maps/roomsvr1/variant_02_nft_bt`
- 小地图、底图、导航：同一荣耀版地图变体的解析结果
- 场景构件：荣耀版 FCC 的 `AddImg/AddImgEx` 引用及荣耀版 ALE 帧
- 运行时导入器：`tools/import_glory_base_hall.py`

运行时结果是 1944×1920 画布、41×320 导航网格和 205 条 FCC 摆放指令。重新读取原始
FCC 的行注释状态后，其中 189 条有效指令全部能从荣耀版解析；其余 16 条是 `//` 或
`////` 明确禁用的旧指令，保留在 `map_manifest.json` 中供审计但绝不参与渲染。旧提取器
报告的 4 个“缺失构件”也都属于这些禁用指令，因此正式运行依赖目前为零，不从免费版或
激战版借图。旧免费版大厅底图、碰撞、四块立牌和参考截图均已从正式运行目录删除。

场景静态绘制顺序和角色遮挡是两个不同问题，不能给一整张大图只设一条 Y 排序线，也不能
把大图按屏幕 Y 切成细条。导入器严格按 FCC 顺序 alpha 合成所有有效 `AddImg/AddImgEx`，
同时记录每个最终可见像素的最后 owner。最终像素先归入 106 个业务基线，再按 256×256
空间块裁成 303 个 alpha bbox，紧凑装入一张 1024×2386 的共享 atlas；manifest 的每个
`semantic_layers` 条目同时保存世界 `region` 和 `atlas_region`。离线将这些裁剪层重新合成，
必须与 `scene_color.png` 和 `static_composite.png` 逐像素一致并记录 SHA-256。运行时节点从
旧方案的 458 个降至 303 个，GPU RGBA 像素从 1944×1920 降至 1024×2386，也不再加载
104 份稀疏大矩形或任何全地图副本。

普通构件的业务基线默认是 FCC 锚点 Y。楼梯是一个可穿行的复合资产，不能让整张 276×241
图片共用一条线：`industrial_stairway_traversable` depth profile 在资产局部坐标中将它拆成
`tread_underlay` 和 `handrail_occluder`。踏板固定在所有角色之下，扶手按“锚点 Y + 237”
参与排序；角色在楼梯上不会再被整张楼梯吞掉，但处于扶手后方时仍会受到局部遮挡。蒙版由
profile 中留存的局部多边形与源 alpha 相交生成，同一套规则复用于大厅两处楼梯，不含任何
世界坐标特判；ALE 没有提供语义蒙版时，这种可视、可复核的资产 profile 是正式扩展点。

地图并不是从截图描边，也不是从 PNG 透明度推测可走区域。视觉层、前景物件、导航层和
小地图都由各自的原始数据重建，Godot 仅消费业务化重命名后的产物。

## 2. 一张地图的组成

### 2.1 FCC：地图的装配清单

解包后的地图 FCC 是核心入口，常见字段包括：

- `size=W*H` 或 `size=W x H`：地图画布像素尺寸。两个写法都存在于荣耀版 FCC。
- `loadtle=...; tilesize=GW,GH`：地图图块资源，以及引擎网格的宽和高。
- `oversrc=...ale`：底图/覆盖图所用的 ALE 帧资源。
- `overdata=$HEX{...}`：底图帧的摆放记录。
- `AddImg(...)`、`AddImgEx(...)`：立牌、门、传送点等独立场景物件。
- `bktile.indexdata=$PKH{...}`：压缩后的本地导航网格。
- `SetGoFlag(...)`：运行时对局部格子追加或修改通行状态。

FCC 字符串通常应先尝试 GBK/GB18030 解码。解析结构时应以 ASCII 关键字和二进制
字段为准，避免地图中文名乱码影响提取。

### 2.2 底图：ALE 帧加摆放记录

地图的固定视觉层应按以下顺序重建：

1. `addkind` 引用的 JPG 每行切成 4 张 48×24 菱形图块；接近黑色的像素是旧引擎色键透明。
2. `link` 用 `maskimg` 的 14 行 × 4 列蒙版生成两种地面之间的 56 张过渡图块。
3. `indexdata` 每项前两个字节选择上述 TLE 图块，按旧引擎坐标放入画布。
4. `overdata` 引用的 ALE 帧覆盖在图块层之上。
5. 只把未被行注释禁用的 `AddImg`/`AddImgEx` 按 FCC 顺序叠加；同时记录最终像素 owner，
   正式运行时消费 owner 语义层。注释指令仍保留完整元数据，但不得渲染。

由 `nengine.dll` 的 `enginebktile.cpp` 路径及实际指令确认的图块左上角公式为：

```text
x = cell_x * 48 + (cell_y 为奇数时取 24，否则取 0) - 24
y = cell_y * 12
```

这套流程已用商店、基地大厅、H09 野外区和秘境地图与原版 `smap` 小地图交叉检查。
只有 `overdata` 而没有图块层时，地面会变成黑色，因此不能把 `overdata` 误认为完整底图。
图块索引 `60000`（`0xEA60`）是旧引擎明确跳过的“空图块”哨兵，不代表 TLE 越界或资源缺失。

已验证的 `overdata` 记录每项为 5 字节：

```text
uint16_le anchor_x
uint16_le anchor_y
uint8     frame_index
```

ALE 每帧除了像素还带原点（pivot/origin）。最终左上角不是锚点本身，而是：

```text
top_left_x = anchor_x + frame.origin_x
top_left_y = anchor_y + frame.origin_y
```

将各帧按记录顺序 alpha 合成到 `size` 指定的透明画布，就能得到固定地面背景。
原点不可丢弃，否则拼接会整体错位。

### 2.3 独立物件与遮挡

`AddImg`/`AddImgEx` 引用的 ALE 不应全烘焙进底图。它们的锚点通常代表物件与地面
接触的位置。普通物件的基本关系仍然是：

```text
物件纹理左上角 = 物件地面锚点 + ALE 帧原点
排序值          = 物件地面锚点.y
角色排序值      = 角色脚底.y
```

这样角色站在立牌后面时会被遮挡，走到前面时又会盖住立牌。实际产物不是把 189 个原图
简单重新叠一遍，而是输出互不重叠的最终 owner 像素层：这既保留 FCC 静态画家顺序，也让
动态角色只和 owner 的语义基线比较，避免透明物件重叠后重新排序改变静态颜色。

`AddImgEx` 必须额外保存 handler、两个独立数值参数、payload、payload 原始字节、行注释
前缀和 `comment_state`。`//`、`////` 都是禁用状态；禁用记录可以用于传送关系或旧业务审计，
但不能因此创建视觉节点。门、传送点、NPC 触发器等有效 `AddImgEx` 也不能只当装饰图处理。

### 2.4 小地图

客户端通常在 `map/smap/` 下保存专用小图。它不是大地图实时缩小的结果；优先使用
原图，并在工程内按业务语义命名。角色/NPC 标记由运行时按世界坐标到小地图矩形的
比例换算叠加。

## 3. PKH 碰撞网格

`indexdata` 的十六进制内容先还原为 PKH 字节，再调用对应版本 `fkernel.dll` 中的
`FTGameOS::nzip::lzw_img_unpack` 解压。仓库工具不复制原游戏 DLL，而是由调用者显式
传入 DLL 和 `pkh_unpack.exe`，确保解析版本可追溯。

解压后的每个网格单元固定为 3 字节：

```text
offset + 0: uint16_le tile_kind
offset + 2: uint8 flags
```

通行判定已经由反汇编和多张实际地图共同确认：

```text
walkable = (flags & 0x80) != 0
```

`tile_kind` 不是通行布尔值；不要把某个固定 kind 硬编码成墙。运行时可把每格压缩成
一个字节（`1` 可走、`0` 阻挡），原始三字节记录和统计信息则保留在分析产物中。

荣耀版 `RoomSvr1` 的一次全新离线复核结果是：

| 项目 | 结果 |
| --- | ---: |
| 地图画布 | 1944 × 1920 px |
| 引擎网格 | 41 × 320 |
| PKH 压缩数据 | 7,698 bytes |
| 解压数据 | 39,360 bytes（13,120 格） |
| 可走 | 10,160 格 |
| 阻挡 | 2,960 格 |

标志统计也与规则完全吻合：`0x90`、`0xD0` 可走，`0x10`、`0x50` 阻挡。

注意：FCC 的静态网格只是初始状态。脚本出现 `SetGoFlag` 时，还必须在加载地图后按
脚本语义叠加动态阻挡；否则门、活动物件或传送设施附近可能与原游戏不一致。

## 4. Godot 坐标系

当前引擎网格是按行存储的一维数组：

```text
index = cell_y * grid_width + cell_x
```

它是交错的菱形格。当前复刻所用、与旧引擎 `enginebktile.cpp` 行为一致的转换为：

```text
doubled_y        = world_y * 2 + 24
positive_diagonal = floor((doubled_y + world_x) / 48)
negative_diagonal = floor((doubled_y - world_x) / 48)

cell_x = floor((positive_diagonal - negative_diagonal) / 2)
cell_y = positive_diagonal + negative_diagonal
```

网格中心还原为世界坐标：

```text
world_x = cell_x * 48 + (cell_y 为奇数时取 24，否则取 0)
world_y = cell_y * 12
```

这里的中心间距是 48×12，不要把 FCC 中图形图块的 48×24 直接当作导航数组行距。
Godot 的 `DiamondNavigation` 对菱形边邻居建图，再在不穿墙角的前提下补角邻居，以
支持八向移动；A* 后用密集视线采样拉直路径，使每段无遮挡路线只播放一个最接近的
八向动画。

## 5. 荣耀版是否还能解析

可以。对当前完整荣耀版展开目录重新扫描的结果：

- 含 `indexdata=$PKH` 的地图 FCC：828 份。
- 去除六个 NFT 内容分支的同名重复后，叶子脚本名约 261 种。
- 六个分支计数：`NFT_BT` 184、`NFT_SK` 171、`NFT_BL` 125、`NFT_DS` 124、
  `NFT_PL` 122、`NFT_BTB` 102。
- 随机选取荣耀版 `NFT_BT/map/RoomSvr1/roomsvr1.fcc.cab`，使用荣耀版
  `fkernel.dll` 重新提取，解压成功且网格尺寸、记录数、标志分布全部自洽。

早期“只有 21 张地图”的记录来自尚未下载完整时的旧缓存分析，不能代表现在的
`starhome_lz_ry_full`。登录服务器失效不会影响已经落在本地全量包里的 FCC、ALE、
小地图和碰撞数据。但 `files_dir.dz` 只是更新/校验目录，不是官网物理目录的完整枚举：
全局依赖审计发现 294 种脚本引用的 ALE 未在清单资源库命中，其中 269 种仍能按 FCC
精确路径从荣耀官网取得并成功解析，25 种返回 404。

因此地图解析顺序固定为：清单内荣耀资源 → 已验证的荣耀官网惰性缓存 → 官网同版本精确
路径请求一次 → 保留缺失。不得用模糊同名或免费版/激战版资源自动补洞。成功和失败结果都
写入 `starhome_lz_ry_full_parsed/official_lazy_cache/official_recovery_manifest.json`；正常运行
不会重复请求同一路径，只有 `--retry-official-failures` 才会重试失败记录。

同名地图在不同 NFT 分支可能是版本变体，不能仅按文件名覆盖。选择正式地图时需要
比较 FCC 哈希、地图尺寸、引用资源和场景内容，再为 remake 赋予唯一业务名。

地图显示名直接来自 FCC 的 `m_sMapName`，内部代码来自 `m_sNameForCheck`，字符串按
GB18030 解码。形如 `A02`、`H09` 的值是合法野外编号，不是乱码或缺失名称。地图系统
界面通常把它们显示为 `A02区`、`H09区`；批量目录同时保存原始名称、内部代码和这个
系统标签。当前荣耀包实际出现 A02–J09 的 76 个编号，包内没有 H10，但解析器接受同样
格式的 H10。

## 6. 可复现提取

项目提供 `tools/map_pipeline/extract_navigation.py` 和
`tools/map_pipeline/extract_all_maps.py`。以下命令只生成分析产物，不会写入 `assets/`：

```powershell
python tools/map_pipeline/extract_navigation.py `
  "..\starhome_lz_ry_full_parsed\ftc_resources\expanded\NFT_BT\map\RoomSvr1\roomsvr1.fcc.cab" `
  "..\..\work\glory_roomsvr1_navigation" `
  --unpacker "..\..\work\pkh_unpack.exe" `
  --engine-dll "D:\Program Files\FancyBoxII Games\newsystem_ry\fkernel.dll"
```

输出包括：

- `packed_indexdata.pkh`：从 FCC 提取的压缩负载。
- `raw_indexdata.bin`：DLL 解压后的三字节原始记录。
- `navigation_grid.bin`：供 Godot 使用的一字节通行网格。
- `navigation_metadata.json`：来源、SHA-256、尺寸、标志和 tile kind 统计。

导入正式工程前必须给地图、物件和贴图改成业务语义名称，并在 manifest 的
`source_*` 字段中保留原逻辑路径。原客户端的 NFT、`pic/pic2`、时间戳或哈希目录
不能直接进入运行时 `assets/`。

全量荣耀版地图的可复现命令为：

```powershell
python tools/map_pipeline/extract_all_maps.py `
  "..\starhome_lz_ry_full_parsed\ftc_resources\expanded" `
  "..\starhome_lz_ry_full_parsed\ale_sprites" `
  "..\starhome_lz_ry_full" `
  "..\starhome_lz_ry_maps_parsed" `
  --unpacker "..\..\work\pkh_unpack.exe" `
  --engine-dll "D:\Program Files\FancyBoxII Games\newsystem_ry\fkernel.dll"
```

上面的全量命令默认在本地未命中 ALE 时访问荣耀更新目录
`http://update.ftxjjy.com/gameser/ry_www/`。可用 `--offline` 禁止联网但继续消费既有缓存；
也可用 `--official-cache-root`、`--official-base-url`、`--official-timeout` 和
`--ale-decoder` 显式覆盖缓存、服务器、超时与解码器位置。下载结果必须具备 ALE/RLE0/AEX
文件头并由解码器实际生成 `frames.json` 后才算恢复成功。没有 `files_dir.dz` MD5 的文件会
自行记录下载后的 MD5 与 SHA-256。

若荣耀版地图 FCC 明确引用了荣耀版全量包中不存在的 ALE，可在**离线比对报告**中把
免费版、激战版解析目录作为只读检索库，用来确认缺口的业务含义；这种模式的输出不能
进入正式工程。解析器始终优先荣耀版完整逻辑路径，检索库也先按完整路径匹配，仅当同名
ALE 在所有检索库中仍对应唯一逻辑路径时，才按文件名给出研究候选：

```powershell
python tools/map_pipeline/extract_all_maps.py `
  "..\starhome_lz_ry_full_parsed\ftc_resources\expanded" `
  "..\starhome_lz_ry_full_parsed\ale_sprites" `
  "..\starhome_lz_ry_full" `
  "..\starhome_lz_ry_maps_parsed" `
  --fallback-ale-root "..\starhome_lz_fr_full_parsed\ale_sprites" `
  --fallback-ale-root "..\starhome_jznp_full_parsed\ale_sprites" `
  --retry-unresolved-scene-objects `
  --unpacker "..\..\work\pkh_unpack.exe" `
  --engine-dll "D:\Program Files\FancyBoxII Games\newsystem_ry\fkernel.dll"
```

`resolved_ale` 以 `@starhome_lz_fr_full_parsed/` 或
`@starhome_jznp_full_parsed/` 开头时，表示该物件只是跨版本研究候选。正式导入器必须拒绝
这类结果：构件应保持缺失，直到在荣耀版中找到可验证来源，不能通过重命名掩盖跨版本素材。

批量工具按 FCC SHA-256 去掉六个 NFT 分支间的完全相同副本，但在目录中保留全部来源。
每个地图目录主要包含：

- `composite.png`、`thumbnail.jpg`：高分辨率重建图及目录缩略图；
- `tile_layer.png`、`background.png`：图块层和叠加固定 ALE 后的背景；
- `scene_objects.json`：独立场景物件、锚点、ALE 原点和解析状态；
- `navigation_grid.bin/json`、`navigation_metadata.json`：通行网格及统计；
- `minimap.jpg`：原版专用小地图（原包存在时）；
- `map_metadata.json`：名称、分支、来源脚本、各层状态和缺失项。

根目录的 `map_names.csv` 使用 UTF-8 BOM，适合直接用 Excel 查看；`map_catalog.json`
保留 828 条来源；`unique_maps.json` 记录 497 份唯一产物；`index.html` 可按名称、代码和
分支搜索。`partial` 不等于地图失败：官网补抓后 497 张唯一地图中 431 张完整，66 张仍
存在结构、小地图或场景物件问题；其中 49 张包含 298 个摆放缺口，对应 25 个官网 404 的
唯一 ALE。地图图块、碰撞和小地图仍可能成功，应查看 `issues` 与分层状态。

### 地图跳转关系

荣耀版的常规传送点以 `AddImgEx('transport', ...)` 元数据保存在地图 FCC 中。多数记录
以 `//AddImgEx` 形式保留，运行时实际传送对象由服务器创建；`////AddImgEx` 表示已经
禁用的旧出口。可用以下命令提取六个 NFT 分支的跳转图：

```powershell
python tools/map_pipeline/extract_map_transitions.py `
  "..\starhome_lz_ry_full_parsed\ftc_resources\expanded" `
  "..\starhome_lz_ry_maps_parsed"
```

传送字符串依次为：目标地图代码、显示名称、本地图接近点 X/Y，以及可选的目标入口号。
`transport.OnCreate` 会登记本地图接近点；玩家进入 100 像素范围后调用
`ChangeSvr(目标地图代码, 入口号)`。目标地图内的实际出生坐标由服务器依据入口号选择，
不在这份 FCC 元数据中。`transport2` 会在同一入口提供多个房间或楼层目标。后期地图的
`AGTransPoint` 规则直接记录目标落点，`AGTransLine` 则根据玩家穿过边界的位置计算目标
边界落点；提取器也会将这两类客户端规则合并进图谱。输出包括
`map_transitions.json`、UTF-8 CSV、仅有效边清单、G08 专项清单和无法在同分支找到目标
代码的审计报告。

D04 的十二条有效出口引用同一旧动画目录下的 `jt-01..08` 四帧素材；截至 2026-08-28，
官网对单点与双点文件名均返回 404，恢复包中也没有这些文件。运行时不会因此静默隐藏出口：
`tools/import_glory_d04_transition_animations.py` 使用同一荣耀版本仍可从官网取得的方向标记
生成四帧明暗循环，并为每条业务出口写独立资源与 `missing_original_http_status=404` 审计。
其中旧样式 08 没有同名方向标记，明确回退到同版通用传送标记；找到原四帧 ALE 后只需替换
导入器来源，地图定义中的业务 `asset_id` 和交互契约无需变化。

供 remake 直接消费的结构化结果分为两层：

- 根目录 `map_transition_graph.json` 保存 497 个唯一地图节点、83 个未落入地图目录的外部
  引用节点和 523 条有效边；每条边都带可解析的源/目标节点 ID；
- 每个唯一地图目录都写入 `transitions.json`，即使该地图没有出口也保留空数组。有效、
  禁用旧出口分别存放，边中保留图标锚点、本地图接近点、目标代码、入口号、目标地图
  目录候选和来源脚本。常规 `transport` 不应伪造目标出生坐标；只有 AG 规则能够提供或
  计算目标落点。

当前 91 条有效边的目标代码无法在同一荣耀版分支缓存中解析成地图目录。它们多为惰性
房间、商店或活动实例；提取器会保留这些边并标记 `destination_present_in_branch=false`，
而不是静默删除。另有 6 条 AG 边来自全局 `client_include` 中的 `AG_HHPY_1` 规则，荣耀版
地图目录没有对应 FCC；它们保存在全局图谱的外部源节点中，不能伪装成某张已解析地图
的本地 `transitions.json`。

### 缺失场景素材人工审计

地图保持缺失位置为空白，不通过相似文件名猜图。完成跨版本只读回退后，可批量生成
原尺寸标记图、缩略图、逐图缺失清单和可搜索 HTML：

```powershell
python tools/map_pipeline/generate_missing_scene_review.py `
  "..\starhome_lz_ry_maps_parsed" `
  "..\starhome_lz_ry_maps_missing_review"
```

红色标记表示未解析 `AddImg`，黄色表示 `AddImgEx`，同一锚点混合两种类型时为洋红色。
锚点落在地图画布外时无法在 PNG 上绘制，但仍会写入逐图 JSON、总 JSON 和 CSV。审计包
根目录的 `index.html` 可按地图代码、名称、分支或缺失 ALE 路径搜索；每张卡片链接原尺寸
标记图、未标记复原图和机器可读清单。官网精确路径恢复后，当前结果覆盖 49 张地图、298 个
缺失摆放、25 种唯一缺失 ALE，生成过程无错误；其中 11 个摆放锚点位于画布外。

## 7. 新地图接入检查表

1. 从荣耀版 FCC 建立地图目录与来源清单，确认选择了正确 NFT 变体。
2. 校验所有 `oversrc`、`AddImg`、`AddImgEx`、小地图和声音引用是否本地存在；ALE 未命中时
   先查持久缓存，再按荣耀官网精确路径请求一次，并保存成功/404/错误审计。
3. 解析每条摆放的注释状态和完整参数；按 FCC 顺序合成有效项并生成最终像素 owner。
4. 普通 owner 默认使用锚点 Y；可穿行复合物件应提供资产局部 depth profile，禁止坐标补丁。
5. 将 owner 层裁到 alpha bbox，离线重合成并与静态 composite 逐像素校验。
6. 解压 PKH，验证 `raw_size == grid_width * grid_height * 3`。
7. 应用 `0x80` 通行位，再审计 `SetGoFlag` 等动态修改。
8. 在 Godot 中验证边界、门、立牌、传送点和至少数条长距离路径。
9. 按业务语义重命名后才导入 `assets/`，运行素材规范检查再提交。
