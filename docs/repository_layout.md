# 主仓库布局

## 运行时边界

主仓库包含 Godot 工程、源码、场景、`data/` 定义与索引、测试、工具和文档。
开发运行资源统一物化在项目根的 `assets/`，运行时只使用 `res://assets/...`；本轮恢复
上游的资源根名称，保留展开资源树加载方式，不恢复旧 ZIP 挂载入口或子模块。

| 路径 | 用途 | 版本管理 |
| --- | --- | --- |
| `assets/` | 开发阶段完整运行资源树、导入设置和物化图集 | 本地物化；由清单记录来源和校验信息 |
| `data/` | 业务定义、运行时索引、物化清单 | 主仓库 |
| `.godot/` | Godot 本机导入缓存 | 忽略 |
| `../starhome_lz_ry_full/raw/` | 工程外荣耀原始档案 | 本地保留，不属于主仓库 |
| `../starhome_lz_fr_full/raw/`、`../starhome_jznp_full/raw/` | 已取得的跨版本原档 | 本地保留，不属于主仓库 |
| 工作区外恢复目录 | 历史恢复中间产物 | 不属于运行工程 |

`assets/` 下按命名空间分类：`glory/` 保存荣耀版包内容，`recovered/` 保存跨版本补回
素材，其他目录保存角色、装备、物品、地图、矿物、怪物和 UI 的运行资源。命名空间不会
互相覆盖。

## 首次准备

需要 Git、Godot 4.7.2，以及已经物化的 `assets/`。主仓库克隆后，另行取得本地资源并
核对物化清单：

```powershell
git clone git@github.com:haha370104/starhome-remake.git
cd starhome-remake
python -X utf8 tools/check_asset_size_policy.py
```

开发机缺少 `assets/` 时，不能启动完整运行时；需取得清单所列资源或相应恢复原档。
`data/content/content_materialization_manifest_v1.json` 是迁移校验记录，不是自动下载或全量重建脚本。

## 日常检查

```powershell
git status --short
python -X utf8 tools/check_asset_size_policy.py
```

修改运行资源后，核对对应导入器和来源记录，再按改动范围运行检查。荣耀原档
保留在工程外，历史恢复树和离线缓存按恢复文档管理。

## 物化记录

旧散装目录和 ZIP 已一次性迁移到 `assets/`，迁移时的文件数、大小和 SHA-256 记录在
`data/content/content_materialization_manifest_v1.json`。该清单是历史迁移审计记录，不是运行时
ZIP 挂载清单；各资源导入器按需从对应原档再生成。

历史 bundle 和未提交备份留在工程旁的恢复目录；工程外荣耀原档不属于主仓库，校验索引放在 `data/source_evidence/glory/`。

## 2026-09-14 拆分记录（历史）

拆分前主仓库有 405 个提交。对独立副本筛选历史：主仓库移除 `assets/`，
素材仓库提取 `assets/` 并将其提升到仓库根。保留各自相关历史，提交 ID 因拆分发生变化。
切换前逐项比较原树与两个新树的文件名、模式及 blob ID；没有改写运行素材内容。

原 Git 元数据（包括 LFS 对象）、完整 history bundle、未提交文件备份和文件哈希清单
存放在工程旁的 `.starhome-repository-migration-20260914/`，不加入 GitHub 仓库。
未提交的用户源码/项目设置修改保留在当前工作树。
备份仓库不能作为日常工作仓库使用；需要查询旧提交时可对 `original.git` 使用 `git --git-dir`。
