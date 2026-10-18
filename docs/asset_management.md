# 素材目录与版本管理

## 2026-10-18：只发布运行依赖

用户明确要求：游戏未使用、仅开发阶段可能使用的素材保存到仓库外，不占用 Git LFS。
当前运行代码、场景及其递归配置是根；所有注册地图、物品、怪物以及可选功能的实际表现均保留。
已解码索引本身不代表运行用途，`source_audit`、旧动作记录和离线画面对照也不作为保留理由。
仍被运行资源使用的 `.import` 与紧凑溯源元数据保留。

执行工具为 [compact_runtime_assets.py](../tools/compact_runtime_assets.py)。它先验证引用完整性，
要求显式指定仓库外归档目录，再归档所有将改动的文件；按 SHA-256 合并包内相同的图片和导航数据，
同步地图定义和精灵页索引，不改动画帧、原点、逻辑身份及来源版本。已有实体路径尽量保留。
原始包、删去的松散文件和 `cleanup-report.json` 一起留在归档中，原包内的开发素材可直接解压使用。

```powershell
python -X utf8 tools/compact_runtime_assets.py --archive C:/outside-repository/asset-archive
python -X utf8 tools/compact_runtime_assets.py --archive C:/outside-repository/asset-archive --apply
python -X utf8 tools/check_runtime_assets.py --archive C:/outside-repository/asset-archive
```

同一次执行不能覆盖不同内容的旧归档。重新导入原图后必须再次裁剪并通过
[运行依赖检查](../tools/check_runtime_assets.py)，不可直接提交原始全量解码产物。
该检查已接入项目门禁；另检查大文件 LFS、地图切换、装备、怪物动画和受击效果。
测试 ZIP 改为在隔离的 `user://` 目录生成；离线 HUD 溯源检查通过
`STARHOME_ASSET_ARCHIVE` 指定上述归档根目录，普通运行检查不依赖这个目录。

本轮从 14,182 条索引裁剪到 2,339 条运行动画；原件保存在外部归档，绝不当作丢失源素材重新下载。
当前素材约 6.62 GiB，原来约 10.59 GiB。历史 LFS 对象不因当前树删除而从 GitHub 自动回收；
远端清理按 GitHub 的 LFS 支持流程处理，不能通过跳过上传钩子发布缺实体的指针。
字节一致性、21 项 Godot 回归脚本及提交范围见[本轮验证记录](verification/runtime_asset_cleanup_2026-10-18.json)。

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
| 大地图 `floor.png`、`semantic_layer_atlas.png` | 按 `.gitattributes` 进入 LFS |
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
