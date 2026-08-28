# 阶段 2：荣耀版地图图谱种子

本阶段的数据入口是 `res://data/maps/map_directory.json`。客户端和服务器都只能用业务
`map_id` 查询该目录，再加载目录内固定的 `res://data/maps/*.json`；网络消息不得携带或
决定资源路径。全图谱解析证据仍保存在工程外的
`starhome_lz_ry_maps_parsed/map_transition_graph.json`，不会把 NFT、原 ALE 路径或
`pic/pic2` 目录带入运行时。

## 真实纵切拓扑

荣耀版 `RoomSvr1` 只有一个有效出口：图标锚点 `(408, 348)`、自动接近点
`(480, 370)`，目标是 `City1Svr` 的入口 0。它没有直达任何野外地图的边。因此阶段 2
不能为了少做一张图而虚构“大厅→G08”，真实首条链路固定为：

```text
yian_harbor_hall_floor_1 (RoomSvr1)
  -> yian_harbor_city (City1Svr)
  -> d04_field_zone (D04)
```

`City1Svr` 有四个通往 D04 的门，分别指定目标入口 1–4。D04 的 12 条有效出口全部进入
业务定义；其中四条返回城市的边是内部引用，其余 C03/C04/C05/D03/D05/E03/E04/E05
仍未提升，因而显式标记为 `external`。`City1Svr` 原始脚本共有 31 条有效边；本种子只提升
大厅边和四条 D04 边，余下 26 条没有删除，仍由全量解析图谱保管，并在
`world_graph_seed.json` 中记录为 `deferred_not_deleted`。

当前运行时目录已经按这条真实链路登记三张地图，City 与 D04 的 MapDefinition、导航、
出生点、内部跳转引用和业务化表现资源均已落盘。这里的“已落盘”不等于真实联网跨图验收
完成；服务器原子迁移、客户端切换和双 ENet 客户端分图广播仍以集成测试结果为准。

当前业务显示沿用项目既有“易安港”上下文，但所选 Glory `City1Svr` FCC 的
`m_sMapName` 实际是“龙之城”。这个差异保存在 `source_audit.semantic_name_note`，后续获得
服务器地图命名证据后再统一，不把推测写成来源事实。

## 普通传送与出生点

旧客户端普通 `Transport` 只保存目标地图代码和入口号，目标实际落点由旧服务器选择；
`approach_point` 是源地图坐标，绝不能直接当成目标落点。新配置使用：

```json
"spawn_points": {
  "default_id": "field_center",
  "points": [{
    "spawn_id": "field_center",
    "entry_number": 0,
    "position": [2412, 2400],
    "evidence_level": "navigation_derived"
  }]
}
```

`entry_number: null` 表示只用于无入口上下文的默认出生，非空整数对应普通传送入口。
`source_confirmed`、`navigation_derived`、`reconstructed_default` 是当前允许的证据等级。
由于旧服务器落点不可得，本轮入口坐标均采用可走的互逆出口附近点或地图中心，并明确标为
`navigation_derived`；完整性测试会真实加载导航字节，拒绝落在阻挡格的出生点。

## G08 图谱样板

G08 不在大厅的相邻链路上，但它的五条出口证据完整，适合作为全图谱引用测试：

| 目的地 | 图标锚点 | 接近点 | 源行 |
| --- | ---: | ---: | ---: |
| F07 | `(96, 72)` | `(156, 84)` | 509 |
| G07 | `(2280, 84)` | `(2315, 90)` | 510 |
| H07 | `(4632, 84)` | `(4653, 91)` | 511 |
| H08 | `(4656, 2448)` | `(4662, 2441)` | 512 |
| F08 | `(96, 2736)` | `(174, 2728)` | 513 |

测试要求目标集合精确等于 `f07/f08/g07/h07/h08`，既不能漏边，也不能把其他分支的边
拼入当前 NFT_BL/BT 变体。

## 已导入导航与表现资源

四张地图的导航数据均来自荣耀版，并已按业务目录重命名：

| map_id | 网格 | SHA-256 | 可走/阻挡 |
| --- | ---: | --- | ---: |
| `yian_harbor_hall_floor_1` | 41×320 | `d68ad7bc872fb1d907ca6ecb2410cc782e631f846d03a9b4b3b0dacc5b45a327` | 10160/2960 |
| `yian_harbor_city` | 71×560 | `46bfb65fc3a6c5faef835ec35602139bec96d3a29469bfe313136ca25a5a3fde` | 32958/6802 |
| `d04_field_zone` | 101×800 | `6596d9afc3b99553649f5d980de0365dc51a36eacb50a2e07fc0075fa612f65b` | 77814/2986 |
| `g08_field_zone` | 101×800 | `df15d24a1bb74f63385d10d51e2419e3ffa5669810b52dc6b1d1913dc21537dc` | 72738/8062 |

City 与 D04 已完成荣耀版语义场景导入，不再使用空 resource 路径：

| map_id | 已解析摆放 | 缺失摆放 | 语义层 | atlas | Glory-only 校验 |
| --- | ---: | ---: | ---: | ---: | --- |
| `yian_harbor_city` | 818 | 0 | 919 | 2048×4770 | 精确重合；官网惰性恢复 31 个摆放 |
| `d04_field_zone` | 45 | 16 | 117 | 2048×845 | 精确重合；官网惰性恢复 10 个摆放 |

两张地图都已生成业务化 `floor.png`、`minimap.jpg`、`map_manifest.json` 和共享语义 atlas；
MapDefinition 的 `assets.resources` 指向这些受控 `res://assets/maps/...` 路径。manifest 的
`semantic_reconstruction_exact` 与 `parsed_composite_matches_glory_only` 均为 true。City 已无
场景缺口；D04 剩余 16 个摆放仍保留在 `missing_dependencies` 中，不以免费版或激战版素材补洞。

G08 当前仍只有图谱、五出口定义、入口配置与导航字节。它尚未导入 floor、minimap 或语义
场景 manifest，因此 `assets.resources` 保持为空，`presentation_state` 继续标记为素材导入
阻塞。其荣耀版解析结果为 658 个已解析摆放、95 个缺失摆放；此前允许把可见缺口延后到
实际游玩时人工确认，但这不等于 G08 已具备客户端表现。

## 当前完成边界

已经完成：

- 受控 `map_id → MapDefinition` 目录，以及大厅、City、D04、G08 四份业务定义；
- `RoomSvr1 → City1Svr → D04` 真实拓扑、普通入口出生点与内部引用；
- City、D04 的荣耀导航、地面、小地图和语义遮挡层导入；
- D04 全部 12 条出口与 G08 五出口的引用门禁。

阶段 2 的多地图运行时已经完成：真实 ENet 覆盖大厅到 City 的可靠切图；服务端覆盖双玩家
分图广播隔离、非法远程切图、失败原图保留和切图后会话地图身份；客户端覆盖异步预载、
权威确认和原子场景提交。G08 客户端地图表现仍未导入，它是后续按需内容工作，不是本阶段
真实纵切的运行时缺口。

## 自动检查

单独运行地图数据门禁：

```powershell
& "C:\Users\tomato\Downloads\Godot_v4.7.2-stable_win64_console.exe" `
  --headless --path . `
  --script res://tests/maps/glory_world_graph_data_test.gd
```

门禁覆盖受控目录、内部引用、四份导航的尺寸与 SHA-256、全部出生点可走性、真实纵切链路、
D04 12 条出口和 G08 五出口集合。

真实网络跨图测试：

```powershell
& .\tools\run_enet_map_transition_integration.ps1 `
  -GodotExecutable "C:\Users\tomato\Downloads\Godot_v4.7.2-stable_win64_console.exe"
```
