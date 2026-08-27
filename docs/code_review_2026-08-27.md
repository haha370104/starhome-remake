# Starhome Remake 代码评审（2026-08-27）

> 评审范围：当前工作区中的 Godot 运行时代码、入口场景、地图/NPC/HUD 数据接缝、客户端联机层、权威服务器与自动检查。
> 基线：评审开始时 Git `HEAD=6148126`；同时包含 2026-08-27 19:53 前已落盘但尚未提交的阶段 2 改动。
> 本文只给出问题与重构顺序，没有改写运行时代码。

## 1. 结论

当前工程已经具备比“单文件原型”更好的底层零件：导航、网络契约、预测/插值、地图定义、HUD 组件和权威地图实例都有独立文件，也有真实 ENet 三进程测试。但模块拆分主要停留在“把类放进不同目录”，尚未形成清晰的状态所有权和完整用例边界。

最需要先处理的不是继续增加小类，而是收紧以下三个边界：

1. `main_hall.gd` 只能做启动组装，不能继续拥有地图、移动、交互、HUD 和联机会话的运行状态。
2. 本地玩家位置、路径和权威校正必须只有一个写入者。
3. `map_joined` 必须落到一个原子“替换活动地图”的客户端用例，而不是停在网络信号和孤立预加载器上。

当前没有必须推翻重写的 P0 问题。最新工作区的全套自动检查通过，说明现有行为可以作为渐进重构的保护网。建议保留可运行大厅，每次抽一个职责并提交，不做一次性目录大搬迁。

## 2. 做得好的部分

- 服务端权威方向正确。移动目标、地图出口、出生点和动态阻挡都由服务端重新验证，客户端没有提交位置或速度的权限。
- `DiamondNavigation` 被客户端预测和服务端地图实例共用，避免出现两套坐标/碰撞算法。
- 网络契约对字段、类型、版本和序列做了明确验证；地图迁移在服务端已经考虑跨图原子提交、同图传送和状态继承。
- `LocalMovementPredictor`、`RemoteEntityInterpolator`、`ClientNetworkAdapter` 的算法职责大体可辨认，比把网络处理直接塞进场景脚本健康。
- 自动检查覆盖纯领域、契约、客户端、服务端、HUD、地图、导航、遮挡、素材来源和真实 ENet 双客户端；这套检查值得保留。
- 荣耀版素材门禁、免费版 HUD 白名单和业务语义路径已经形成明确规范。

## 3. 主要问题

### P1-1：`main_hall.gd` 仍是事实上的 God Object

证据：

- `scripts/main_hall.gd:3-18` 固定具体地图、NPC、角色资源并预加载几乎全部客户端子系统。
- `scripts/main_hall.gd:62-73` 同时负责启动参数、数据读取、地图/导航加载、世界、HUD 和联机组装。
- `scripts/main_hall.gd:116-143` 驱动玩家移动；`148-162` 处理输入；`258-415` 用代码创建整个世界、角色、摄像机、HUD 和联机表现器；`428-461` 又处理 NPC 命中和业务动作。
- `scenes/main_hall.tscn:5-6` 只有一个挂脚本的空 `Node2D`，Godot 场景组合能力没有真正参与模块边界。

影响：

- 加第二张地图时只能继续给入口脚本加分支或重建整棵树。
- 任一模块测试都要伪造大量无关依赖，最后容易靠生产代码里的测试兼容接口维持测试。
- 地图、战斗和 NPC 后续接入时会争夺 `_process`、输入和节点生命周期。

建议边界：入口只解析启动配置、创建依赖并启动 `ClientApplication`。活动地图生命周期交给 `ActiveWorldController`；本地移动交给 `LocalPlayerController`；NPC 交互交给用例控制器；HUD 只暴露语义方法和信号。

### P1-2：本地移动有多个位置写入者，权威校正没有同步路线状态

证据：

- `scripts/main_hall.gd:116-143` 直接修改 `player.position`，并在修改后把位移回填预测器。
- `scripts/client/presentation/hall_multiplayer_presenter.gd:156-162` 收到预测/校正状态后再次直接写同一个角色位置。
- `scripts/main_hall.gd:43-45` 保存路径和段方向；权威位置改变时，`scripts/main_hall.gd:420-421` 只同步摄像机和小地图，没有取消或重算旧路径。

正常预测时这两条写入链碰巧得到相同坐标，但服务端因动态占位、不同落点或强制校正改变位置后，大厅仍会沿旧的 `path_points/path_index` 继续走，并产生新的预测位移。单元测试分别验证预测器和表现器，却没有验证它们与大厅路径状态组合后的行为。

建议：由 `LocalPlayerController` 独占“目标、路径、当前段、方向、预测序号、表现位置”状态。角色节点只接受控制器投影。校正事件必须有明确策略：小校正保留目标并从新位置重算路径，强制校正或地图切换取消旧路线。`main_hall.gd` 不再直接写玩家位置。

### P1-3：地图切换底层已存在，但活动场景没有闭环

证据：

- `ClientMultiplayerSession` 能提交切图、校验 `map_joined`、替换会话地图身份并重置预测器（`scripts/client/network/client_multiplayer_session.gd:112-145, 240-292`）。
- `HallMultiplayerPresenter` 把 `map_joined` 继续向上转发（`scripts/client/presentation/hall_multiplayer_presenter.gd:73-82`）。
- `main_hall.gd:395-413` 只订阅了本地角色状态，没有订阅 `map_joined`、预加载结果或切图失败；地图、导航、NPC、摄像机限制和 HUD 因此不会更换。
- `ClientMapPreloader` 已经单独存在，但没有任何运行时调用方。它只异步加载 `floor/minimap`，场景清单里的纹理、导航二进制和导航对象仍不在原子 bundle 内（`scripts/client/presentation/client_map_preloader.gd:45-69, 101-129`）。

影响：网络会话可以认为玩家已进入新地图，而屏幕仍显示旧地图；如果直接接通信号，还会在提交后同步加载导航或大量场景层，破坏“预载完成再切换”的承诺。

建议：建立唯一的 `ActiveWorldController.change_map(bundle, joined_state)` 事务。bundle 至少包含已验证的 `MapDefinition`、导航实例、底图、小地图、场景表现定义及其实际纹理依赖。先完成预载，再请求/确认切图，或让服务端确认后进入“等待本地资源、冻结输入”的显式状态；绝不能让会话身份和活动地图视图长期不一致。

### P1-4：运行时数据边界仍大量依赖裸 `Dictionary`

证据：

- `main_hall.gd:64-65` 直接解析角色和 NPC JSON，没有根类型、schema 或必填字段验证。
- `main_hall.gd:311-346` 对场景清单直接使用 `composition["props"]`、`semantic_layers`、数组下标和资源路径。
- `CharacterFactory` 对角色目录使用多层强制索引并在工厂中直接 `load`（`scripts/characters/character_factory.gd:11-22, 28-46`）。
- HUD、NPC、联机会话启动配置和预加载 bundle 继续用自由形态字典传递内部状态。

网络边界使用字典是合理的，问题在于字典穿过验证层后仍成为模块内部 API。字段拼写错误会变成运行时异常，调用方无法从类型看出必需字段，也无法安全演进 schema。

建议：只在 JSON/RPC 边界接收字典，立即转换为类型化定义或命令。优先补 `CharacterAppearanceDefinition`、`NpcDefinition`、`SceneCompositionDefinition`、`ClientStartupOptions` 和 `MapPresentationBundle`。不要为了“类型化”给每个字段建一个类；一个聚合定义对应一个稳定 schema 即可。

### P1-5：`AuthoritativeServer` 同时承担了入口、模拟、用例和协议适配

证据：`scripts/server/authoritative_server.gd` 当前约 604 行，同时负责：

- 命令行配置与启动/退出；
- ENet endpoint 安装和回调；
- 固定 Tick 与快照调度；
- 会话建立、重连和清理；
- 移动命令路由；
- 完整地图迁移用例；
- wire result 序列化；
- 地图目录加载和实例组装。

阶段 1/2 尚能维护，但战斗、怪物、掉落、采矿和交易进入后，这个类会成为所有服务端模块的汇合点。更关键的是，协议回调和领域事务现在在同一类，后续很难给命令处理做独立幂等、权限和事务测试。

建议逐步抽出：

- `ServerBootstrap`：配置、依赖组装、进程生命周期；
- `ServerSimulationLoop`：固定 Tick、实例推进、快照调度；
- `SessionService`：建连、重连、断线宽限；
- `MovementService`：会话鉴权后调用地图实例；
- `MapTransferService`：完整原子迁移；
- `ServerCommandRouter`：RPC envelope 与服务方法之间的薄适配。

不要一次拆完。先抽纯用例类，保留 `AuthoritativeServer` 作为 facade，待调用方稳定后再缩小入口。

### P1-6：当前工作树不具备安全重构基线

评审时工作树共有 676 个未提交路径，其中 464 个是已跟踪改动、212 个未跟踪；已跟踪文本统计约为 28662 行新增、27784 行删除，另有 187 个二进制改动。它们不是本次评审产生的，但会让任何后续重构提交难以判断真正影响范围。

新增长期硬约束：每完成一个可独立验收的模块或模块子步骤立即提交；单次最多 20 个文件、文本新增与删除合计最多 2000 行。开始架构重构前，应先把现有工作树按功能和素材批次整理成满足限制的提交，不能把它们和重构混在一起。

### P2-1：NPC 把领域行为、客户端表现和占位业务揉在同一个节点

`NpcBase` 既继承 `WorldCharacter`，又在客户端 `_process` 中巡逻，还读取交互配置并返回业务文本；`ShopNpc`/`QuestNpc` 只覆盖两段占位动作。当前路线图明确把 NPC 权威化留到后续，这在原型期可以接受，但此结构不应直接扩展为商店和任务系统。

建议将 NPC 分成 `NpcView`、客户端插值/环境表现、`InteractWithNpcUseCase` 三层。商店和任务是 action handler/service，不应通过角色节点子类区分。这样固定 NPC、巡逻 NPC、商店+任务复合 NPC 也不需要多重继承或继续增加子类。

### P2-2：HUD 组件已拆文件，但封装仍被入口穿透

`HallHud` 已经组合顶部栏、底栏、快捷栏和小地图，这是正确方向；但 `main_hall.gd:386-388` 又取出 `hint_label`、`popup`、`minimap_player_dot` 内部节点，联机 presenter 也直接拿 `Label` 写状态。移动提示、网络提示、功能未接入提示共享一个文本控件，多方写入顺序会成为隐式状态机。

建议只暴露 `show_movement_status`、`show_network_notice`、`show_npc_interaction`、`set_map` 等语义 API。短暂通知使用独立通知队列/频道，入口和网络层不持有具体 UI 节点。

### P2-3：代码动态建树过多，降低 Godot 工程可读性

世界、玩家、摄像机、HUD 容器和弹窗几乎都由 `.new()` 与 `add_child()` 创建。纯数据驱动的重复实体适合工厂，但稳定的界面结构和场景骨架更适合 `.tscn`/`PackedScene`。当前方式让编辑器层级、锚点和依赖只能靠读代码理解，对 Godot 新手尤其不友好。

建议把稳定结构落为场景：`client_app.tscn`、`active_world.tscn`、`hall_hud.tscn`、`world_character.tscn`。动态数据只填资源、位置和列表项，不动态创造整套固定界面。

### P2-4：角色动画资源按实例重复组装

`CharacterFactory.build_character_set` 每创建玩家、远端玩家或 NPC 都重新构建三套 `SpriteFrames` 和所有 `AtlasTexture`。底层 PNG 会被 Godot 缓存，但帧资源和对象图仍重复创建。大厅 NPC 多、未来怪物更多时会产生不必要的启动开销和内存占用。

建议按 appearance/action 预生成 `.tres`，或至少在工厂内按业务 appearance ID 缓存不可变 `SpriteFrames`。角色实例只保存播放状态和装备组合，不拥有重复的帧定义。

### P2-5：测试覆盖了零件，但缺少客户端组合测试

全套检查当前通过，这是很好的基础。但仍缺少以下高价值场景：

- 大厅正在走路时收到平滑/强制权威校正，路径状态与位置不会互相打架；
- `map_joined` 后旧地图节点、导航、NPC、相机限制和 HUD 被一次性替换；
- 地图预载失败时会话/画面/输入处于明确状态；
- 角色、NPC、场景 manifest 缺字段时返回可读错误而不是数组/字典索引异常；
- 多客户端 NPC 权威化后位置和交互目标一致。

现有主场景 smoke 只能证明三秒内没有脚本加载错误，不能证明这些模块接缝成立。

### P2-6：强制给所有函数写文档，已经产生低信息注释

代码中大量注释是“Performs the operation”“Input value consumed by the operation”一类模板文本。检查器证明注释存在，却不能证明职责或不变量被解释；它还放大了每次重构的行数和审阅噪声。

建议保留对公开 API、复杂状态机、协议边界和非显然算法的强制文档；私有短函数允许用清楚的命名替代模板注释。检查器应拒绝明显模板句，或把私有简单函数从强制范围移除。

## 4. 建议的目标结构

目录不必一次调整，先建立以下运行时边界：

```text
ClientApplication                         # 仅组装与应用生命周期
├─ ActiveWorldController                 # 当前地图的原子装载/卸载
│  ├─ MapPresentationLoader              # 定义、导航、贴图、场景层 bundle
│  ├─ LocalPlayerController              # 输入、路径、预测、校正、动画意图
│  └─ EntityViewRegistry                 # 远端玩家/NPC/怪物视图生命周期
├─ ClientMultiplayerSession              # 会话状态与网络消息，不碰具体节点
└─ HudController / HallHud               # 语义 UI API，不暴露内部控件

ServerBootstrap                          # 配置与依赖组装
├─ ServerCommandRouter                   # RPC -> 用例
├─ ServerSimulationLoop                  # Tick 与快照
├─ SessionService
├─ MovementService
├─ MapTransferService
└─ World/MapInstance                     # 权威运行状态

Shared
├─ contracts                             # 仅 wire DTO 与验证
├─ maps                                  # 类型化定义、导航和坐标
└─ domain                                # 无 Node、无 UI、无 RPC 的规则
```

判断是否需要新模块的标准是“是否有独立状态所有权、变化原因和测试边界”，不是文件行数。一个 250 行、职责单一的导航类比五个互相传裸字典的 50 行类更健康。

## 5. 分批重构顺序

以下每批均按新限制设计为不超过 20 个文件和 2000 行；实际提交前仍要以暂存区统计为准。

1. **R0：冻结基线与提交门禁**
   整理现有未提交改动；补提交规模检查脚本。只处理工程流程，不改行为。
2. **R1：补组合回归测试**
   先覆盖移动校正期间的旧路径、`map_joined` 后活动地图替换失败状态。测试可以先失败，提交信息明确是 characterization/failing test。
3. **R2：抽 `LocalPlayerController`**
   从 `main_hall.gd` 搬走输入、路线、方向、移动和预测桥接；角色位置改为单写入者。不要同时移动目录或改算法。
4. **R3：抽 `ActiveWorldController` 与类型化 `MapPresentationBundle`**
   集中创建/销毁底图、语义层、导航、NPC、相机边界；接通 preloader 和 `map_joined`。先只支持大厅到一张野外图。
5. **R4：收紧数据入口**
   为角色、NPC、场景 composition 增加 loader/validator；工厂只消费已验证定义。
6. **R5：封装 HUD**
   移除外部对 `hint_label/popup/player_dot` 的引用，增加语义接口和通知队列；再把固定结构迁入 `.tscn`。
7. **R6：拆服务端入口**
   第一提交只抽 `MapTransferService`；第二提交抽 `SessionService`；第三提交抽 Tick/快照循环。`AuthoritativeServer` 在每一步仍作为兼容 facade，所有测试持续通过。
8. **R7：重构 NPC 边界**
   在商店/任务正式开发前拆开视图、权威状态和交互用例，避免把占位子类扩展成业务层。
9. **R8：资源缓存和场景化**
   预生成/缓存角色 `SpriteFrames`，把稳定节点结构迁到 `.tscn`。这属于可维护性和性能优化，排在状态所有权之后。

不要先全仓移动到 `scripts/shared/client/server` 目标目录。大范围移动会制造引用改动和合并冲突，却不会自动修复状态边界。先在现路径抽出职责，等依赖稳定后用纯重命名小提交整理目录。

## 6. 提交约束的执行口径

提交前至少核对：

```powershell
git diff --cached --name-only
git diff --cached --numstat
```

- 第一条结果最多 20 个路径；新增、删除、重命名和二进制都计一个文件。
- 第二条中所有可计数的新增与删除相加最多 2000；二进制显示 `- -`，只计文件数。
- 同一模块可以有多个连续提交，但每个提交都必须能解释、能测试、能回退。
- 不把素材批量导入、离线解析产物、运行时代码和架构重构混入同一提交。
- 提交后工作区可以保留其他既有改动，但本提交的路径必须精确暂存，不能顺带提交无关内容。

## 7. 验证结果

在最新工作区运行：

```powershell
./tools/run_project_checks.ps1 `
  -GodotExecutable C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe
```

结果：全部通过，包括领域/协议/客户端/服务端/HUD/地图/导航/遮挡测试、真实 ENet 双客户端与重连、主场景 smoke、素材命名与来源审计、阶段 2 地图表现审计。

Godot 在受限环境中仍输出 Windows 根证书读取和编辑器设置保存警告，但未导致项目检查失败；它们不属于本次模块拆分问题。
