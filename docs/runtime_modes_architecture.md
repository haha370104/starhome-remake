# 双运行模式：独立权威服务器与进程内直连

核对日期：2026-09-14。本文根据当前代码描述运行架构，不把目标设计当作已实现能力。
整体入口见[评审导读](./review_guide.md)，保存细节见[持久化](./persistence_architecture.md)。

## 1. 核心结论

两种模式都是“客户端 + 权威服务器”，区别是服务器在哪里运行、消息如何送达。
离线直连不是客户端直接改状态，也不是另一份离线战斗逻辑，而是在客户端进程里实例化
同一个 `AuthoritativeServer`，通过可替换传输端口交流。

| 项目 | 独立服务器模式 | 离线直连 / 进程内模式 |
| --- | --- | --- |
| 进程 | 一个服务器进程 + 一个或多个客户端进程 | 一个游戏进程包含客户端和本地权威服务器 |
| 客户端选择 | `--online` | 默认主场景，或显式 `--offline-debug` |
| 传输实现 | `NetworkTransportEndpoint`，ENet 高层 RPC | `InProcessAuthoritativeTransport`，复制载荷并投递方法调用 |
| 服务端入口 | `dedicated_server.tscn` → `AuthoritativeServer._ready()` | 传输端点手动 `new()` → `initialize()`，不启动监听 |
| 业务处理 | 同一个 `dispatch_transport_command()`、地图实例、领域模型和应用服务 | 相同 |
| 模拟驱动 | 独立服务端 `_physics_process()` | 同一个服务端节点 `_physics_process()`；传输不自动推进 |
| 存档归属 | 服务器所在机器/账号的仓储 | 游戏进程内的服务器仓储，不归客户端 UI |
| 多人 | 多个客户端连接同一个服务器、共享同图实例 | 当前每个端点独有一个服务器、固定本地 peer 2 |

即使 `--online --server-host=127.0.0.1` 全部跑在一台电脑上，仍属于真实网络模式。
反过来，开两个默认离线游戏窗口，会创建两个不同世界，不会自动进入同一个多人房间。

## 2. 实际依赖与进程边界

### 2.1 独立服务器

```text
客户端进程 A / B …                         独立服务器进程
MainHall / HUD / 世界表现                   dedicated_server.tscn
  │                                             │
  ├─ LocalPlayerController                      ▼
  └─ HallMultiplayerPresenter             AuthoritativeServer
       └─ ClientMultiplayerSession               ▲
            └─ ClientNetworkAdapter              │ dispatch_transport_command(peer, type, payload)
                 └─ NetworkTransportEndpoint ─ ENet ─ NetworkTransportEndpoint
                          ▲                      │
                          └── 可靠消息 / 快照 ────┘
```

两端的 RPC 节点固定为 `/root/StarhomeNetworkTransport`，不跟着大厅/野外场景名字改变。
服务端由网络端点取 `multiplayer.get_remote_sender_id()`，再映射到会话实体；
不能信任客户端载荷里自己声称的玩家身份。

### 2.2 进程内直连

```text
一个游戏进程 / 同一主线程事件循环
MainHall → HallMultiplayerPresenter → ClientMultiplayerSession
                                      └─ ClientNetworkAdapter
                                           └─ InProcessAuthoritativeTransport
                                                ├─ 客户端命令复制 + call_deferred
                                                │    └─ AuthoritativeServer.dispatch_transport_command
                                                │         ├─ 会话 / 地图 / 战斗 / 采矿
                                                │         └─ 玩家事务 / 自动保存 / 仓储
                                                └─ 可靠消息与快照复制 → 客户端信号
```

本地 `AuthoritativeServer` 由传输端点先显式 `initialize()`，随后 `add_child()` 加入场景树。
服务端 `_ready()` 检测已初始化的 `map_registry` 后直接返回，避免重建地图/存档。
两种模式都只用服务器 `_physics_process()` 自动推进。端点 `advance_simulation()` 仅给
确定性测试使用，调用方须暂停服务端物理处理。2026-09-07 曾修复双时钟导致提前命中的回归，
见 [战斗诊断](combat_diagnostics.md)，不得恢复传输 `_process` 自动推进。

主要代码入口：

- [MainHall](../scripts/main_hall.gd)：启动参数和依赖组装；输入、切图、战斗与玩家投影见[客户端架构](client_architecture.md)。
- [HallMultiplayerPresenter](../scripts/client/presentation/hall_multiplayer_presenter.gd)：组装客户端会话与表现信号。
- [ClientMultiplayerSession](../scripts/client/network/client_multiplayer_session.gd)：序列、契约、预测/快照、切图与玩法消息。
- [ClientNetworkAdapter](../scripts/client/network/client_network_adapter.gd)：连接状态与端点选择。
- [ClientTransportEndpoint](../scripts/network/transport/client_transport_endpoint.gd)：共享传输接口与信号。
- [ENet 端点](../scripts/network/transport/network_transport_endpoint.gd)、[进程内端点](../scripts/network/transport/in_process_authoritative_transport.gd)。
- [AuthoritativeServer](../scripts/server/authoritative_server.gd)：统一命令分派、应用用例与模拟入口。

## 3. 启动、握手和初始地图

### 3.1 客户端如何选择模式

`MainHall._apply_multiplayer_command_line()` 设置模式，经 presenter 的 `start(settings)`
传给 `ClientMultiplayerSession.offline_debug_enabled`，再配置网络适配器。
适配器 `_ensure_transport_endpoint()` 才决定创建哪种端点。

主场景默认 `multiplayer_offline_debug_enabled=true` 且自动连接；可复用的 session/adapter
自身默认值是 `false`。因此“默认离线”是当前主场景的启动策略，不是全局网络层的隐式降级。
联机连接失败也不会自动切成另一个离线世界。

### 3.2 服务端如何启动

- 独立模式：服务端场景 `_ready()` 用 `DedicatedServerConfig.from_command_line()` 读取参数，
  调用 `initialize()`，再 `start_network()` 监听连接。
- 进程内模式：端点 `initialize()` 使用注入配置或 `DedicatedServerConfig.new()`，强制
  `network_enabled=false`，调用相同服务器的 `initialize()`，订阅输出信号，不创建 ENet socket。
- 两种初始化都建立内容索引、目录、地图注册表、会话和持久化/面板服务；地图导航和种群
  按玩家进入加载，不在启动时创建全部地图。服务端也挂载当前内容包，但不实例化 HUD 或渲染角色。

### 3.3 握手与进入流程

1. 客户端先显示加载屏；当前仍会在遮罩后组装默认大厅，不能误写成完全不加载大厅。
2. 端点建立连接并通知 `connected_to_server`。进程内通过 deferred 通知，保证先进入 CONNECTING。
3. 适配器提交协议版本、内容版本及可选重连令牌；这是会话握手，不是正式账号认证。
4. 服务端 `open_session()` 校验版本，创建或恢复会话，并恢复已有角色存档及目标地图。
5. `session_opened` 返回会话、`map_joined` 和初始快照；客户端再查询人物/背包/战车快照。
6. 客户端完成目标地图预载并由 `ActiveWorldController.commit_bundle()` 提交后结束初始遮罩。
   “连接已建立”“会话已就绪”“场景已提交”是三个不同条件。

`--no-auto-connect` 是预览/测试开关：只组装本地初始场景并结束加载屏，不建立权威会话。
它不能用来验收战斗、掉落或保存，也不是第三种完整玩法模式。

## 4. 命令与回包：替换传输，不替换业务

### 4.1 上行命令

所有正常玩法都经过：

`输入/窗口 → 客户端会话 → 网络适配器 → 传输端点 → dispatch_transport_command()`。

| 意图 | 服务端处理器 | 客户端不得决定 |
| --- | --- | --- |
| 移动 | `handle_peer_move` | 最终坐标、速度、导航可达性 |
| 切图 | `handle_peer_map_transition` | 任意目标资源路径、未授权地图和落点 |
| 攻击/维修/采矿能力 | `handle_peer_use_ability` | 是否命中、伤害、能耗、冷却、采集产量 |
| 掉落拾取 | `handle_peer_loot_pickup` | 物品定义、数量、归属；只选 `loot_id` |
| 面板查询/换装/整理 | `handle_peer_player_panel_command` | 装备数值、背包最终状态、玩家身份 |
| 击毁后回城 | `handle_peer_vehicle_recovery` | 回城地图、恢复生命值和延时 |

ENet 的 RPC 回调只携带真实 peer 和复制后的载荷，进入上述分派器。
进程内 `_enqueue()` 对载荷 `duplicate(true)`，再 `call_deferred("_dispatch", ...)`；
`_dispatch()` 使用固定 `LOCAL_PEER_ID=2` 进入同一分派器。复制不是业务验证，服务端仍需校验。

### 4.2 下行与网络通道

服务端 `_send_reliable()` 发出可靠消息信号；独立模式额外发送 RPC。
`_emit_snapshot()` 为每个 peer 生成其当前地图快照；两种端点分别送到同一客户端接收路径。
进程内端点只转发 peer 2 的消息，不把所有世界快照混给客户端。

当前 ENet 声明如下，见端点中的 `@rpc`，不以理想协议表替代代码：

| 通道 | 传输方式 | 消息 |
| --- | --- | --- |
| 0 | reliable | 会话请求、面板命令、所有可靠服务端消息 |
| 1 | reliable | 移动、切图、能力、拾取、击毁恢复意图 |
| 2 | unreliable_ordered | 世界快照 |

不能假设不同通道消息之间有全局顺序；命令序号、server tick、map instance 与事务 revision
承担不同的一致性职责。移动成功通常靠后续快照确认，失败才发拒绝；能力命令被接受也不代表
弹体已经最终命中。最终生命/能量/事件仍消费权威输出。

**当前进程内实现并非双向异步网络仿真**：上行 deferred，下行在服务器发信号时
复制数据并同步 `emit`。它没有真实序列化往返，也没有模拟各通道延迟、丢包、乱序和重传。
同线程同步回调还可能暴露不同于 RPC 的重入顺序，测试不能依赖这种“回包马上到了”的偶然行为。

## 5. 模拟频率、移动与视觉预测

两种模式共用 `AuthoritativeServer.advance_simulation(elapsed_seconds, now_msec)`：

- 默认 20 Hz 逻辑 tick；累计 delta 达到 0.05 秒才推进一步。
- 默认 10 Hz 快照；每两个逻辑 tick 发一轮。
- 每步处理活跃地图模拟、采矿结算、技能事件和到期恢复；地图无人且在途事务结清后休眠。
- 自动保存累积调用方传入的 elapsed time；重连过期检查默认使用 `Time.get_ticks_msec()`。

两种模式现均从服务端 `_physics_process()` 调用；但进程内客户端和服务器共享主线程，
游戏渲染、同步资源加载或本地保存阻塞主线程时，本地服务器也会延后运行。
当前 accumulator 用 while 补足已累计步数，没有独立预算化追帧调度。
所以“本机没有网络延迟”不等于“不会因为调度/预测/快照出现顿挫”。

两种模式都保留同一客户端预测层，而不是离线关闭预测、联机才启用：

- [LocalPlayerController](../scripts/client/gameplay/local_player_controller.gd) 负责路径和唯一的本地角色位置写入。
- [LocalMovementPredictor](../scripts/client/network/local_movement_predictor.gd) 负责输入确认、偏差与校正；
  当前阈值为 24/96 像素，平滑时间 0.15 秒。确认输入不等于路线已经走完。
- [RemoteEntityInterpolator](../scripts/client/network/remote_entity_interpolator.gd) 默认保留 0.1 秒插值延迟，
  用于其他玩家；不要据此推断所有怪物动画也共用这个插值器。
- 客户端炮弹提前碰撞和爆炸只是表现，不能反向扣血或发经验；开火不取消移动。

## 6. 状态归属与存档

| 状态 | 所有者 | 客户端拥有的内容 |
| --- | --- | --- |
| 会话身份与实体绑定 | `SessionRegistry` / 服务器 | 会话投影和重连令牌 |
| 地图内坐标、怪物、矿源、掉落、战斗资源 | 权威地图实例及模块 | 快照、局部预测和表现缓存 |
| 背包、穿戴、战车装配、技能长期状态 | 服务端 Player 聚合及应用/保存服务 | `CurrentPlayer : Player` 的同版本快照投影 |
| 保存文件、revision、迁移与提交 | 服务端 `PlayerStateRepository` | 不直接读取或写入 |
| HUD、动画、特效、镜头、NPC 环境巡逻 | 客户端表现层 | 本地呈现状态，不是经济权威 |

共享模型指复用类型和规则代码，不是双方共享同一个可变 Player 对象。
同进程也必须通过载荷传递，不能把服务器的 Player/Inventory 引用直接交给客户端。

两种服务器默认每60秒后台保存到 `user://server/player_states.json`；换装/拾取即时提交内存事务，
正常退出等待最新快照写盘。单机策略接受强杀后的检查点进度丢失，详见[持久化](persistence_architecture.md)。
路径属于**运行服务器的主机、系统用户和 Godot 项目数据目录**，不是远程客户端本机路径。
同一台机器、同一系统账号下启动独立服与离线游戏，默认可能落到同一个文件；
两个离线游戏也可能同时写它。当前文件仓储不提供多进程数据库保证，必须隔离测试保存路径。

目前仍是 `FilePlayerStateRepository` 开发替身。SQLite 只有端口与 SQL migration，尚未完成
真实适配器；服务器新会话仍按连接顺序分配 `player.N`，也不具备正式账号归属。
模式统一不会自动解决这些问题。地图休眠中的怪物/矿源/掉落只保留在本次进程，不等于世界存档。

## 7. 退出、重连与尚存差异

| 边界 | 当前实现与注意点 |
| --- | --- |
| 独立客户端掉线 | 服务端进程继续运行，角色默认保留 30 秒；未过期令牌可恢复原会话 |
| 独立服正常退出 | `_exit_tree()` 尝试保存全部角色；强杀/崩溃不能保证执行退出钩子 |
| 离线端点关闭 | 先清引用与连接标志，再 `disconnect_session(2)` → `stop_network()` 同步保存 → `queue_free()`，避免释放锁定对象 |
| 离线世界生命周期 | 与客户端进程绑定；关闭端点后不继续模拟，也不保留可恢复的内存会话 |
| 离线端点重新连接 | 是新服务器实例；不能把原内存重连令牌当成有效的新服凭据，重连状态重置需单独测试 |
| 配置入口 | 独立服解析服务端命令行；当前离线端点默认直接 new 配置，不解析这些参数 |
| 测试注入 | adapter/session 仍有 `inject_*snapshot` 入口，供表现测试使用；不属于正常玩法传输 |
| 并发与网络故障 | 本地固定单 peer、同线程、无故障网络；不能替代多客户端争抢、乱序和延迟测试 |

尤其不要把 `--player-state-store=...`、`--autosave-interval-seconds=...` 加到普通离线客户端
命令行就假设生效：目前 `MainHall` 不转发这些服务端参数。
离线测试需在连接前通过 `ClientNetworkAdapter.configure_in_process_server(config, repository)`
注入，或直接配置端点。可参考[场景测试的配置注入](../tests/integration/map_transition_scene_smoke_test.gd)。

## 8. 启动与验证方式

在仓库根目录运行。默认离线直连：

```powershell
$godotExe = 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . -- --offline-debug
```

独立服务器（独立终端，隔离保存路径，仅监听本机）：

```powershell
$godotExe = 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . scenes/server/dedicated_server.tscn -- --listen-address=127.0.0.1 --port=24680 --player-state-store=user://network_review/player_states.json
```

客户端（可重复运行两次，连接同一世界）：

```powershell
$godotExe = 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . -- --online --server-host=127.0.0.1 --server-port=24680
```

默认监听地址实际是 `*`，上例显式收紧为本机。没有正式认证和生产数据库前，不开放公网。
缺少 LFS 内容实体时，两种模式都可能在内容挂载阶段失败；不要把资源缺失误判为网络故障。

### 验证入口

| 入口 | 当前覆盖 / 不覆盖 |
| --- | --- |
| [进程内传输集成测试](../tests/integration/in_process_authoritative_transport_test.gd) | 真实服务器握手、面板查询、移动确认、peer 快照和切图；不是全部战斗/丢包测试 |
| [客户端网络测试](../tests/client/network/client_network_smoke_test.gd) | 预测、快照、会话及非法载荷；部分测试使用快照注入 |
| [完整场景切图](../tests/integration/map_transition_scene_smoke_test.gd) | 默认大厅到多个地图的实际表现提交和隔离配置 |
| [真实 ENet 双客户端](../tools/run_enet_integration.ps1) | 独立进程连接、移动、远端实体和重连 |
| [真实 ENet 切图](../tools/run_enet_map_transition_integration.ps1) | 跨进程大厅→城区迁移 |
| [保存/恢复测试](../tests/server/persistence/authoritative_autosave_test.gd) | 同一权威保存服务的定时与重载；不是生产 SQLite 验收 |

例如运行进程内链路测试：

```powershell
& 'C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/integration/in_process_authoritative_transport_test.gd
```

战斗差异诊断见[战斗日志](./combat_diagnostics.md)：进程内客户端与服务器同一 JSONL，以
`side` 区分；独立模式分别收集各进程日志，通过命令序号和 shot ID 关联。

## 9. 后续扩展必须守住的边界

1. 新能力加在共享服务端处理器/领域对象里；两个端点只适配同一命令，不写 offline 专用玩法分支。
2. 未来若增加延迟/丢包仿真，应装饰传输端点，按上行/下行和通道调度，不在战斗代码 sleep。
3. 如要提升本地时序一致性，优先补双向消息队列、序列化限制检查、配置转发与故障注入；
   这些是建议，当前尚未实现。
4. 如要把本地权威服移到独立线程/进程，明确唯一 tick 驱动、时钟与退出保存，再测试，不直接共享 Node/模型对象。
5. 为同一玩法保留领域测试、进程内链路测试和真实 ENet 验收；共用源码不等于跨端时序天然一致。

2026-09-14 文档核对未修改运行代码，也未重新执行上述游戏测试。当前仍需重点 review 的是
下行同步重入、离线断开重连、不同通道先后顺序、默认保存路径冲突，以及带延迟的并发战斗。
