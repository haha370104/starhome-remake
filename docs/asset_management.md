# 素材目录与版本管理

文档校准：2026-09-14。运行素材已拆为 `assets` Git 子模块。规则以[项目全局约定](../PROJECT_CONTEXT.md)为准；
当前全量资源装载范围见[运行内容](../docs/runtime_content.md)。

## 业务分类

| 当前目录 | 业务用途 |
| --- | --- |
| `characters/` | 玩家/非战斗 NPC 裸模、基础动画和共用阴影 |
| `monsters/` | 怪物动作、变体、阴影和调色板 |
| `equipment/`、`equipment_world/` | 服装、战车及其方向动画/叠加层；两个现存入口均须按清单追溯，后续可评审合并 |
| `items/` | 背包、掉落与物品槽视图；不能以统一格子尺寸缩放所有图片 |
| `ui/` | HUD 与交互窗口素材 |
| `maps/` | 底图、小地图、导航、语义遮挡层及摆放清单 |
| `minerals/` | 矿源世界表现 |
| `content_packs/` | 全量解码运行资源的 ZIP 包；包内路径也受命名规则约束 |

物品的背包图、面板大图和世界动画是一个业务定义的不同视图，关联规则见
[素材关系](../docs/asset_relationships.md)。地图运行数据单列，不混入穿戴装备。

## 来源与命名

- 非 HUD 的正式来源仅荣耀版 `../../starhome_lz_ry_full/` 与
  `../../starhome_lz_ry_full_parsed/`，包括其 `official_lazy_cache/`。
- 免费版豁免顶部栏、底部栏/快捷栏、小地图边框，以及用户后续明确批准的任务日志、商城、
  系统菜单和名单边框回退；准确边界见 [免费 HUD](../docs/free_hud_rendering.md)。
  小地图 JPG、人物/背包/战车等未获准窗口及其他非 UI 内容不在豁免中。
- 官网精确路径恢复失败时保留缺口；不使用跨版本、模糊同名或相近图替代。
- 运行路径用业务语义 `snake_case`，动画按实体/变体/动作组织。
  原 `pic/pic2`、时间戳、FCH 哈希、旧窗口类名只保留于 `source_*` 等来源字段。
- 当前全量精灵包尚有原始目录泄漏，这是待整改问题，不是新的规范例外。

## 普通 Git、LFS 与缓存

| 数据 | 策略 |
| --- | --- |
| 源码、JSON 定义/索引、清单、导入设置、小图片、导航 | 普通 Git |
| 大地图 `floor.png`、`semantic_layer_atlas.png`、`scene_color.png`、`static_composite.png`、`source_order_reference.png` | 按 `.gitattributes` 进入 LFS |
| `assets/content_packs/glory_*.zip` | LFS；克隆后拉取实际包 |
| `.godot/`、日志、临时文件 | 忽略，可重新生成 |
| 原始客户端全集、解密档案和恢复中间产物 | 仓库外保存；不直接纳入运行素材树 |

大于等于 5 MiB 的素材受[大小策略](../tools/check_asset_size_policy.py)检查；
主仓库保存代码和数据定义，素材子仓库保存运行素材及其导入设置。
具体 LFS 路径由 [素材 .gitattributes](../assets/.gitattributes)决定，不将所有 PNG 一刀切放进 LFS。
`.import` 边车文件保存可复现导入设置，不能和 `.godot/` 缓存混为一类。
推送前确认远端支持 LFS；仅提交指针、不上传实体会使他人无法运行。

离线生成器需要仓库外的荣耀版源档案；运行工程应依赖已发布的包，不依赖原客户端安装目录。
公开分享仓库或素材前需确认原游戏素材再分发权利。
