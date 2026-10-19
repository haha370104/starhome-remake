# 主仓库与素材子模块

## 边界

| 仓库 | 本地位置 | origin |
| --- | --- | --- |
| 主仓库 | Godot 工程根目录 | `git@github.com:haha370104/starhome-remake.git` |
| 素材子仓库 | `assets/` | `git@github.com:haha370104/starhome-remake-asset.git` |

主仓库保存 `project.godot`、场景、源码、`data/` 业务定义和索引、测试、工具及文档。
素材仓库保存运行图片、地图、动画、内容 ZIP、素材溯源清单和 `.import` 设置。
源码的 `.gd.uid` 属于主仓库；图片的 `.import` 属于素材仓库。`.godot/` 是本机缓存。
原版完整客户端、解包目录和离线中间产物保留在工作区其他位置，不进入两个仓库。

子模块固定具体提交，不自动跟随素材仓库的最新分支。
继续使用 `res://assets/...`；移动子模块挂载路径需要另行迁移所有资源引用。
详细规则见[素材管理](./asset_management.md)。

## 首次克隆

需要 Git、可访问两个仓库的 GitHub SSH 身份，以及 Godot 4.7.2。
2026-10-18 起按用户要求临时使用普通 Git，不需要安装 Git LFS。

```powershell
git clone --branch work/community-gameplay-integration --recurse-submodules git@github.com:haha370104/starhome-remake.git
cd starhome-remake
python -X utf8 tools/check_asset_size_policy.py
```

若已经克隆了主仓库：

```powershell
git submodule sync --recursive
git submodule update --init --recursive
```

当前 ZIP 都是普通 Git 中的真实文件，独立挂载，无需手工拼接。
缺少子模块、残留 LFS 指针或超出 48 MiB 的文件时，素材门禁必须失败。

## 日常更新与提交

先检查两个工作树：

```powershell
git status --short
git -C assets status --short
```

没有本地冲突时更新代码及其锁定的素材版本：

```powershell
git pull --ff-only
git submodule update --init --recursive
```

修改素材前，在子模块内切到开发分支；普通子模块检出可能处于 detached HEAD。
例如已有 `main` 时执行 `git -C assets switch main`，首次从 detached HEAD 开发可用
`git -C assets checkout -b asset/my-change`。旧 Git 不支持 `switch` 时使用 `checkout`。
不要使用 `submodule update --remote` 替代版本锁定。

按实际路径分别暂存、检查和提交，素材提交后更新主仓库引用：

```powershell
# 在 assets 中完成素材提交后：
git -C assets push -u origin HEAD
git add assets
git diff --cached --submodule
git commit -m "chore(assets): update runtime asset revision"
git push --recurse-submodules=check origin main
```

当前使用普通 Git：正常推送，不跳过任何钩子。首次上传采用不超过 500 MiB 的增量分批提交、推送，
低于 GitHub 单次 2 GiB 的上传限制；每次提交最多 20 个文件、文本增删合计最多 2000 行。
所有中间提交用于建立完整素材基线，运行游戏必须使用主仓库锁定的最终完整提交。
禁止从旧克隆或备份执行 `git push --all`、`git push --mirror` 或 `git lfs push --all`，
避免把已归档历史重新上传。重建后旧克隆需先保存本地改动，再重新初始化或克隆素材子模块。

## 2026-10-18 普通 Git 基线

用户授权删除并同名重建私有素材库，主仓库已发布的历史保留；`karei03` 的协作邀请已重发。
重建后 LFS 仍因本月累计额度拒绝上传，用户随即明确要求暂时改为普通 Git。
当前存储策略为 `data/content/asset_storage_policy_v1.json`，素材 `.gitattributes` 显式禁用 LFS filter。
超过 48 MiB 的运行 ZIP 已拆为独立包；包内文件的路径、顺序、内容逐项验证不变，加载器仍使用原挂载协议。
普通 Git 基线不引用旧 LFS 历史，克隆当前分支即可获得真实素材。

完整旧 Git 历史、73 个 LFS 实体及用户设置补丁位于
`C:/Users/tomato/Documents/Codex/local-archives/starhome-assets/20261018-lfs-rebuild/`；
未裁剪开发素材在相邻 `20261018-runtime-cleanup/`；拆包前原件、普通 Git 导入及推送记录在
`20261018-regular-git/`。这些目录均在仓库外，不上传。

旧代码提交、旧标签及未合并清理分支的默认 `main` 仍锁定旧素材 SHA，不能从新素材远端还原。
回看旧版本需从上述 bundle 恢复素材历史并复制 LFS 实体；默认 `main` 需评审合并清理分支后才适配新基线。
本次仅推送 `work/community-gameplay-integration`，不自动合并或改动默认分支。
以后恢复 LFS 必须同时处理普通 Git 大对象历史，不能仅修改 attributes；不会自动恢复或提高付费预算。

## 2026-09-14 拆分记录

拆分前主仓库有 405 个提交。对独立副本筛选历史：主仓库移除 `assets/`，
素材仓库提取 `assets/` 并将其提升到仓库根。保留各自相关历史，提交 ID 因拆分发生变化。
切换前逐项比较原树与两个新树的文件名、模式及 blob ID；没有改写运行素材内容。

原 Git 元数据（包括 LFS 对象）、完整 history bundle、未提交文件备份和文件哈希清单
存放在工程旁的 `.starhome-repository-migration-20260914/`，不加入 GitHub 仓库。
未提交的用户源码/项目设置修改保留在当前工作树。
备份仓库不能作为日常工作仓库使用；需要查询旧提交时可对 `original.git` 使用 `git --git-dir`。

这次审计确认项目内没有散落在 `assets/` 外的图片、音频、字体、原客户端资源或 ZIP。
大型地图及内容包继续使用 LFS，规则迁入素材仓库的 `.gitattributes`。
素材大小检查已改为查询子模块自己的索引和 attributes，避免主仓库 gitlink 导致漏检。
