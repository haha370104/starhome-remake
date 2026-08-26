# 地图资源离线解析与运行时消费

本文记录 FancyBoxII 老客户端地图资源的来源、离线解析方式，以及
`starhome_remake` 在 Godot 中的消费约定。结论来自客户端文件、引擎 DLL
导出的 PKH 解压函数和实际数据交叉验证；没有抓游戏内存，也不依赖登录器或服务器。

## 1. 现在的大厅地图来自哪里

当前工程中的“易安港基地大厅一层”最早用免费版做原型，来源如下：

- 地图脚本：`starhome_lz_fr_full_parsed/ftc_resources/expanded/map/roomsvr1/roomsvr1.fcc.cab`
- 小地图：`starhome_lz_fr_full/raw/map/smap/roomsvr1.jpg`
- 场景图块和立牌：地图 FCC 引用的 ALE，解析后按帧原点重新摆放
- 碰撞：同一 FCC 中 `bktile.indexdata=$PKH{...}` 的本地网格

也就是说，地图并不是从截图描边，也不是从 PNG 透明度推测可走区域。当前地图的
视觉层、前景物件、导航层和小地图都有独立的原始数据。既有原型的来源仍保留在
`assets/maps/yian_harbor/hall_floor_1/map_manifest.json` 中；按项目新约定，后续新地图
只从荣耀版提取，免费版大厅在再次迁移前不会被悄悄替换。

## 2. 一张地图的组成

### 2.1 FCC：地图的装配清单

解包后的地图 FCC 是核心入口，常见字段包括：

- `size=W*H`：地图画布像素尺寸。
- `loadtle=...; tilesize=GW,GH`：地图图块资源，以及引擎网格的宽和高。
- `oversrc=...ale`：底图/覆盖图所用的 ALE 帧资源。
- `overdata=$HEX{...}`：底图帧的摆放记录。
- `AddImg(...)`、`AddImgEx(...)`：立牌、门、传送点等独立场景物件。
- `bktile.indexdata=$PKH{...}`：压缩后的本地导航网格。
- `SetGoFlag(...)`：运行时对局部格子追加或修改通行状态。

FCC 字符串通常应先尝试 GBK/GB18030 解码。解析结构时应以 ASCII 关键字和二进制
字段为准，避免地图中文名乱码影响提取。

### 2.2 底图：ALE 帧加摆放记录

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
接触的位置，运行时应保存为独立的 Y-sort 节点：

```text
物件纹理左上角 = 物件地面锚点 + ALE 帧原点
排序值          = 物件地面锚点.y
角色排序值      = 角色脚底.y
```

这样角色站在立牌后面时会被遮挡，走到前面时又会盖住立牌。门、传送点、NPC 触发器
等 `AddImgEx` 项还可能带业务参数，不能只当装饰图处理。

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

## 5. 荣耀版是否还能离线解析

可以。对当前完整荣耀版展开目录重新扫描的结果：

- 含 `indexdata=$PKH` 的地图 FCC：828 份。
- 去除六个 NFT 内容分支的同名重复后，叶子脚本名约 261 种。
- 六个分支计数：`NFT_BT` 184、`NFT_SK` 171、`NFT_BL` 125、`NFT_DS` 124、
  `NFT_PL` 122、`NFT_BTB` 102。
- 随机选取荣耀版 `NFT_BT/map/RoomSvr1/roomsvr1.fcc.cab`，使用荣耀版
  `fkernel.dll` 重新提取，解压成功且网格尺寸、记录数、标志分布全部自洽。

早期“只有 21 张地图”的记录来自尚未下载完整时的旧缓存分析，不能代表现在的
`starhome_lz_ry_full`。登录服务器失效不会影响已经落在本地全量包里的 FCC、ALE、
小地图和碰撞数据。真正无法离线恢复的只有从未缓存、也未包含在全量下载中的惰性
资源；这类缺失应根据 FCC 引用做依赖审计并明确报告。

同名地图在不同 NFT 分支可能是版本变体，不能仅按文件名覆盖。选择正式地图时需要
比较 FCC 哈希、地图尺寸、引用资源和场景内容，再为 remake 赋予唯一业务名。

## 6. 可复现提取

项目提供 `tools/map_pipeline/extract_navigation.py`。以下命令只生成分析产物，不会
写入 `assets/`：

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

## 7. 新地图接入检查表

1. 从荣耀版 FCC 建立地图目录与来源清单，确认选择了正确 NFT 变体。
2. 校验所有 `oversrc`、`AddImg`、`AddImgEx`、小地图和声音引用是否本地存在。
3. 合成固定底图；将需要遮挡或交互的物件保持独立，并保留地面锚点。
4. 解压 PKH，验证 `raw_size == grid_width * grid_height * 3`。
5. 应用 `0x80` 通行位，再审计 `SetGoFlag` 等动态修改。
6. 在 Godot 中验证边界、门、立牌、传送点和至少数条长距离路径。
7. 按业务语义重命名后才导入 `assets/`，运行素材规范检查再提交。
