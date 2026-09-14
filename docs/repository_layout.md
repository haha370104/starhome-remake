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

需要 Git、Git LFS、可访问两个仓库的 GitHub SSH 身份，以及 Godot 4.7.2。

```powershell
git lfs install
git clone --recurse-submodules git@github.com:haha370104/starhome-remake.git
cd starhome-remake
git -C assets lfs pull
python -X utf8 tools/check_asset_size_policy.py
```

若已经克隆了主仓库：

```powershell
git submodule sync --recursive
git submodule update --init --recursive
git -C assets lfs pull
```

在主仓库执行 `git lfs pull` 不会代替子模块下载。
缺少子模块时，素材门禁必须失败；看到文件存在也不能据此确认 LFS 实体已下载。
可以用 `git -C assets lfs fsck` 检查当前版本对象是否完整。

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
git -C assets lfs pull
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

LFS 的 pre-push hook 会上传提交引用的实体；不可用 `--no-verify` 绕过。
首次发布保留的素材历史时，先执行 `git -C assets lfs push --all origin main`，
再推送素材 `main`，最后推送主仓库 `main`。这会上传历史版本对象，传输量高于当前素材目录体积。
若 LFS 上传失败，先处理错误再发布主仓库指针，避免其他开发者拿到不可用版本。

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
