# 全量已知内容注册表

> 本文描述身份/来源注册层。下方旧 runtime 映射表保留注册器生成时的口径，
> 不代表 2026-08-31 的实际可装载数量；当前覆盖见[运行内容](./runtime_content.md)。

## 目的

横切注册表保存荣耀版客户端能够静态确认的地图、怪物和道具身份，同时不把“客户端留下过
一行数据”误写成“复刻版已经可以运行”。现有运行时目录仍只负责已经完成规则、资源和校验的
纵切内容；全量注册表负责稳定 ID、中文名、旧类名、来源字段、地图关系和后续提升状态。

入口为 `res://data/content/known_content_registry_v1.json`，领域查询入口为
`KnownContentRegistry.load_default()`。

## 状态含义

每条注册都有三个独立状态：

- `registration = known`：荣耀版客户端或当前受控运行定义提供了身份依据。
- `runtime = ready`：已经存在可以被复刻版实例化的业务定义；否则为 `unimplemented`。
- `presentation`：`ready` 表示业务化 Godot 资源齐全，`partial` 表示可显示但仍有缺口，
  `source_references_known` 只表示旧 ALE/ACT 引用已知，不能直接当作已导入资源。

因此，服务端地图注册表、战斗怪物目录和 `ItemCatalog` 不会自动遍历全量注册表。内容只有在
规则及素材均完成后，才映射一个 `runtime_id` 并进入现有可运行目录。

## 身份注册与早期 runtime 映射

| 类型 | 已知注册 | 来源覆盖 | 早期 runtime 映射 |
| --- | ---: | --- | ---: |
| 地图 | 814 | 6 个世界、497 组场景资源 | 15 个来源键映射至 9 张业务地图 |
| 怪物 | 139 | 119 条 NPC 数值行、20 个地图类、85 条地图关系 | 4 |
| 道具 | 1393 | 1012 条装备、258 个材料名、123 个本地制造产物 | 14 |

稳定注册 ID 的格式为 `map:<世界>/<地图键>`、`monster:<来源>:<键>` 和
`item:<来源>:<键>`。业务代码不得直接拼接或解析这些 ID；应通过注册表按 `runtime_id`、
旧客户端键或注册 ID 查询。这样后续补齐某项规则与素材时，只需提升该注册的状态并建立
runtime 映射，不必迁移存档或网络协议中的身份。

早期注册层允许多个荣耀世界分支共用同一业务定义，例如其中 NFT_BL、NFT_BT、NFT_BTB、NFT_PL
的 D04 来源键映射到 `d04_field_zone`。这是旧注册映射，不能用来合并当前各世界的地图种群。
查询 runtime 映射返回数组，以保留这种多对一
关系。旧类名也可能重复，按旧键查询同样返回数组，禁止任意取第一条。

怪物地图关系是客户端地图制作证据，而不是退役服务器最终刷怪表。注册表保存关系但不会据此
直接生成怪物；正式刷怪仍由权威服务器的地图遭遇配置决定。

## 重新生成

来源目录更新后运行：

```powershell
python tools/build_known_content_registries.py
```

生成器固定读取 `starhome_lz_ry_full_parsed`，输出采用“一条注册一行”的 JSON 布局。这样三份
全量目录仍可代码审查，且每个数据模块都能满足单次提交不超过 2000 行的工程约束。生成器会
拒绝重复注册 ID、怪物引用不存在的地图以及漏掉当前 runtime 道具的结果。

加载完整性测试：

```powershell
& "C:\Users\tomato\Downloads\Godot_v4.7.2-stable_win64_console.exe" `
  --headless --path . `
  --script res://tests/domain/content/known_content_registry_test.gd
```
