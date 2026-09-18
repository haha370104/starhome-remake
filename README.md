# starhome_remake

Godot 4.7.2 纯 2D 联机复刻工程。共享领域规则与权威服务器，客户端负责输入、预测和呈现；
本地调试通过进程内传输运行同一个服务器，不维护另一套离线玩法。

## 从哪里开始

- **新对话交接**：[项目交接](./docs/project_handoff.md)——先读此页，不重建原型。
- **复刻方法**：[对齐方案](./docs/remake_alignment_plan.md)、[原客户端阅读指南](./docs/original_client_reading_guide.md)。
- **整体 review**：[代码评审导读](./docs/review_guide.md)——当前状态、职责图、源码/测试入口与优先级。
- **全部文档**：[文档导航](./docs/README.md)——区分当前模块、目标设计和原客户端证据。
- **两种运行模式**：[双运行模式架构](./docs/runtime_modes_architecture.md)——独立服/进程内直连的共用逻辑与实际差异。
- **开发规则**：[PROJECT_CONTEXT.md](./PROJECT_CONTEXT.md)——素材版本、业务命名、状态所有权、注释和提交约束。
- **操作与调试**：[使用说明](./使用说明.md)。玩法需求在仓库外的[游戏主要玩法](../游戏主要玩法.md)。

当前可装载 810 张地图；战斗、拾取、换装、技能、自维修及采矿已有基础链路。
已有权威商店买卖、循环/训练任务和裁缝/烹饪/工业制造基础链路。
数量不等于完整复刻：正式账号、SQLite 适配器、生产级经济幂等与世界持久化等仍未完成，
详见[运行内容与资源包](./docs/runtime_content.md)及[开发路线图](./docs/development_roadmap.md)。

## 本地启动

1. 安装 Git LFS，使用 `git clone --recurse-submodules git@github.com:haha370104/starhome-remake.git`，
   进入目录后执行 `git -C assets lfs pull`。已有克隆先执行 `git submodule update --init --recursive`。
2. 使用 Godot 4.7.2 打开 `project.godot`，等待首次素材导入完成。
3. 运行默认场景 `scenes/main_hall.tscn`；默认连接进程内权威服。

嵌入式调试窗口想撑满容器时，在运行窗口尺寸菜单选择 `Stretch to Fit`。
游戏本身采用固定像素 HUD，放大窗口扩大地图视野，不整体放大按钮和角色。

## 独立服务器与客户端

在本仓库目录执行。开发验证建议限定监听本机，并使用独立保存路径，避免覆盖平时调试进度：

```powershell
$godotExe = 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . scenes/server/dedicated_server.tscn -- --listen-address=127.0.0.1 --port=24680 --player-state-store=user://review_server/player_states.json
```

另开终端启动客户端；重复运行可开第二个客户端：

```powershell
$godotExe = 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . -- --online --server-host=127.0.0.1 --server-port=24680
```

当前 `ServerConfig` 未指定监听地址时默认 `*`。没有正式认证与生产数据库，
不要直接开放公网，也不要把开发用 `player.N` 当成稳定账号身份。
开发文件仓储默认 `user://server/player_states.json`，服务器默认每60秒后台保存、正常退出等待写完，
不是 SQLite 数据库。详情见[持久化](./docs/persistence_architecture.md)。

## 检查入口

```powershell
./tools/run_project_checks.ps1 -GodotExecutable 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
```

门禁包含 Godot 导入、脚本/警告、分层测试、真实 ENet 集成和素材审计，会生成缓存/日志。
当前新增测试尚未全部加入总门禁，全量精灵索引也存在命名债务；不能据历史通过记录
宣称当前全绿。范围和单模块入口见[评审导读](./docs/review_guide.md)。

## 素材与仓库边界

正式素材以荣耀版为准；只有免费版 HUD 外观在明确白名单内豁免。
主仓库保存代码、数据定义、工具和文档；`assets` 是独立素材子模块，保存运行素材、素材清单与 LFS 内容包。
原始解密档案留在仓库外，`.godot/` 为本机缓存。克隆、更新和推送顺序见[仓库组织](./docs/repository_layout.md)。
细则见[素材管理](./docs/asset_management.md)。原游戏素材的使用/再分发权利需另行确认，勿直接公开发布。
