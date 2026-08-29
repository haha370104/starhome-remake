# Starhome Remake 技术架构

> 状态：可执行基线，面向首期可玩版本。  
> 玩法依据：[游戏主要玩法与复刻规格](../../游戏主要玩法.md)  
> 素材约束：[项目全局约定](../PROJECT_CONTEXT.md)、[Asset layout](../assets/README.md)  
> 地图解析依据：[地图资源解析管线](./map_resource_pipeline.md)

## 1. 目标与非目标

本项目面向少量熟人联机，但从第一条联网玩法开始就采用服务器权威模型。目标不是复原原
服务器的部署形态，而是在保留原游戏观感和规则证据的前提下，得到容易理解、调试和持续
扩展的代码边界。

首期技术目标：

- Godot 4.7.2 客户端支持自由窗口、斜视角 2D 地图、八向角色、遮挡和固定像素 HUD。
- 同一代码库导出无界面的 Godot 专用服务器，服务端裁决移动、地图切换和全部数值结果。
- 两名玩家可进入同一地图实例，并在延迟或短暂丢包下看到稳定的位置同步。
- 物品、装备、怪物、配方、任务和地图使用版本化数据契约，不由 UI 或场景脚本私有定义。
- 所有正式素材均可追溯到获准版本，并在进入运行时目录前通过命名和来源门禁；除
  `docs/free_hud_rendering.md` 定义的 HUD 外观白名单外，正式素材仍只允许荣耀版。
- 每个玩法纵切都能在无界面环境下做确定性的服务端测试。

首期不做：大规模 MMO 分区、微服务、帧同步、客户端可信结算、运行时 ALE/FCC 解码、一次
导入全部 497 张地图，以及在没有证据时补齐原版掉落或数值。

## 2. 架构决策

### 2.1 一个仓库、两个运行入口

客户端与专用服务器先保持在同一个 Godot 工程中，分别使用客户端启动场景和服务端启动
场景。服务端以 `--headless` 或专用服务器导出运行。这样可以共享导航坐标、协议 DTO、
数据验证器和确定性规则，避免小规模项目过早维护两套语言和构建链。

共享代码不等于共享职责：服务端入口不得实例化 HUD、贴图、音效或客户端角色节点；客户
端不得直接调用服务端领域对象。二者只通过协议契约通信。若以后需要把登录、管理后台或
网页账户拆为独立 HTTP 服务，实时地图服务器和现有协议边界无需改变。

### 2.2 Godot 高层多人 API + ENet

实时连接使用 Godot `ENetMultiplayerPeer`。第一版直接使用高层 RPC，但 RPC 只能出现在
网络适配层；领域服务接收普通命令对象，不能依赖远端节点路径。建议固定端口由启动配置
提供，开发默认仅监听本机或局域网地址。

当前传输层在客户端与专用服务器进程中都安装固定节点
`/root/StarhomeNetworkTransport`。所有高层 RPC 只声明在该节点上，业务场景名称和客户端
节点嵌套方式不会再改变 RPC NodePath。连接成功后客户端自动发送协议版本、公开内容版本和
可选重连令牌；服务器在握手成功后一次性返回会话身份、地图实例和初始快照。客户端与服务
端开发默认端口统一为 `24680`，命令行配置可以覆盖服务端端口。

逻辑频率采用玩法规格的重建默认值：

| 项目 | 首版值 |
|---|---:|
| 服务端逻辑 Tick | 20 Hz |
| 状态快照 | 10 Hz |
| 客户端输入上限 | 20 Hz |
| 小偏差平滑阈值 | 24 px / 0.15 s |
| 强制校正阈值 | 96 px |

网络 Tick 与 Godot 渲染帧解耦。服务端用单调时钟和递增 `server_tick` 推进模拟；业务冷却
统一以服务端 Tick 或毫秒时间戳计算，不能依赖客户端帧率。

### 2.3 服务端状态不使用场景树作为数据库

服务端地图实例、角色、怪物、矿点和掉落是普通领域状态；Godot Node 只负责进程生命周期
和定时驱动。客户端的 `WorldCharacter`、动画和特效是领域状态的投影，不是权威实体。

这条边界可以避免以下问题：

- 场景节点被释放时意外丢失需要保存的状态；
- UI 直接修改背包或生命值；
- 客户端动画完成信号决定伤害、生产或采矿结果；
- 无界面服务端被迫加载美术资源。

### 2.4 服务端存档使用仓储接口

当前已建立 `PlayerStateRepository`、类型化玩家聚合、版本化 SQL migration、SQLite 驱动端口
和可运行的开发文件仓储。开发实现覆盖隔离事务、失败回滚、revision 冲突及重启重载，但它
不具备 SQLite 的 WAL、并发写入和生产 ACID 保证，不能作为正式多人存档。

正式服务器采用本地 SQLite 足以覆盖少量熟人联机，但必须先安装并固定一个 Godot 4
GDExtension 驱动，再实现仓储适配器并复用同一组事务测试。领域层、网络层和场景树都不得
依赖具体 SQL API；迁移脚本随仓库版本管理。

任何物品和货币操作都在一个服务端事务中完成，并记录操作 ID。重复网络请求以操作 ID
幂等返回，不重复扣除或发放。JSON 文件只可用于只读模板或开发快照，不作为正式多人存档。

## 3. 目标目录与职责

目录在相应纵切开始时按需创建；本文不要求一次生成空目录。

```text
scenes/
  client/                 # 客户端启动与世界呈现场景
  server/                 # 无界面服务器启动场景
scripts/
  shared/
    contracts/            # 消息 DTO、枚举、协议版本和验证
    domain/               # 无 Node 依赖的值对象、公式和领域事件
    data/                 # 只读模板加载、schema 校验、稳定 ID
    maps/                 # 坐标、导航、出口与公共地图定义
  client/
    application/          # 登录、进图、交互等客户端用例
    network/              # RPC 发送、快照接收、重连
    world/                # 本地预测、远端插值、Node presenter
    ui/                   # HUD 和窗口控制器
  server/
    bootstrap/            # 配置、依赖组装、进程入口
    network/              # 会话、RPC 适配、限流
    application/          # 命令处理和事务边界
    simulation/           # 固定 Tick、地图实例和实体调度
    modules/              # 战斗、物品、制造、任务等领域服务
    persistence/          # 仓储接口实现、迁移、审计流水
data/
  contracts/              # JSON schema、协议/数据版本
  definitions/            # 可共享的只读公开模板
  server/                 # 掉落权重、管理参数等服务端私有配置
  maps/                   # 地图定义、导航、出口、出生点
assets/                   # 仅客户端读取；继续遵守业务语义命名
tests/
  unit/ integration/ fixtures/
```

现有 `scripts/main_hall.gd` 是原型编排器。迁移时应逐项抽出移动控制、地图加载、联机适配与
交互用例，并保持当前大厅可运行；不以一次大改名或一次性重写作为里程碑。

### 3.1 当前状态与渐进重构边界

`main_hall.gd` 目前并非“仅编排”：它仍创建世界和 HUD、保存玩家路线、处理输入和 NPC
交互，并接入联机表现。该现状是可运行的迁移基线，不是目标架构。重构时每次只抽取一个
可独立测试的职责，`AuthoritativeServer` 同样先作为兼容 facade 保留；禁止先做全仓目录
搬迁，再期待文件位置自动形成边界。

目标运行时所有权如下：

| 状态或用例 | 唯一所有者 | 其他模块的权限 |
|---|---|---|
| 本地目标、路径、方向、预测和表现位置 | `LocalPlayerController` | 输入层提交意图；角色节点只接受投影 |
| 活动地图、导航、场景层、NPC、相机和地图 HUD 状态 | `ActiveWorldController` | preloader 提供完整 bundle；会话只提供确认状态 |
| 玩家脚点与地图外观投影 | `PlayerWorldAvatar` | 移动控制器只写脚点；地图只声明人形或业务战斗 actor |
| 远端玩家、NPC、怪物视图生命周期 | `EntityViewRegistry` | 快照/领域事件驱动，不反写权威状态 |
| 联机会话身份、序列和消息 | `ClientMultiplayerSession` | 不创建或直接修改具体场景节点 |
| 当前登录人物、背包与战车的同版本客户端投影 | `CurrentPlayerState` | UI/HUD 只读订阅；命令仍经会话提交权威服务器 |
| HUD 内部控件与通知频道 | `HudController / HallHud` | 外部只调用语义 API 和订阅业务信号 |
| 服务端世界与玩法结果 | server application/modules | RPC 层只鉴权、验证、路由和序列化 |
| 账户、角色、背包、装备、战车和位置存档 | `PlayerStateRepository` | 用例开启事务；驱动适配器负责 SQLite/开发文件细节 |

权威位置校正到达时，由 `LocalPlayerController` 按原因选择从新位置重算目标或取消旧路线；
大厅入口和 presenter 不得再次直接写同一角色位置。地图迁移必须由
`ActiveWorldController.change_map(bundle, joined_state)` 原子提交，不能让会话身份与活动
地图视图长期不一致。

稳定的 HUD 和应用骨架最终落入 `.tscn`；动态工厂只创建地图实体和列表项。这个场景化步骤
排在状态所有权之后，不能和移动、地图切换或服务端拆分混成一次重构。

## 4. 依赖方向

依赖只允许从外向内：

```text
客户端 UI / Node presenter ─┐
                            ├─> 客户端 application ─> shared contracts/domain
客户端网络适配器 ───────────┘

服务端 RPC / Tick / SQLite ─> 服务端 application ─> server modules
                                                  └─> shared contracts/domain/maps

离线解析 tools ─> 生成 data/assets/manifest
运行时代码  -X-> 离线解析目录、FCC/ALE、未获白名单许可的免费版或激战版素材
```

具体约束：

- `shared` 不依赖 `client`、`server`、场景文件或具体网络 Peer。
- `server/modules` 不调用 RPC；它返回领域事件和结果，由网络层序列化。
- `client/ui` 不直接写玩家状态，只发出用例意图。
- `Dictionary` 只允许作为 JSON/RPC 边界载体；loader/adapter 验证后立即转换为类型化定义、
  命令、查询或 bundle。模块间不得继续传递自由形态字典。
- 地图导航是客户端预测和服务端校验的共同实现，但服务端加载的数据版本为准。
- 配置中没有写明的原版规则保留为版本化服务端参数，不散落为脚本常量。

## 5. 共享数据契约

### 5.1 ID 与版本

运行时 ID 使用稳定的英文 `snake_case` 业务名，例如 `map.yian_harbor.hall_floor_1`、
`monster.om_larva.standard`、`item.ore.iron`。旧客户端代码、时间戳和目录只出现在
`source_*` 溯源字段中。

每份定义至少包含：

```json
{
  "schema_version": 1,
  "definition_id": "monster.om_larva.standard",
  "content_version": 1
}
```

- `schema_version` 表示结构兼容性；加载器拒绝未知的主版本。
- `content_version` 表示平衡或内容修订，用于存档迁移和联机握手。
- 服务器启动时计算公开定义包哈希；客户端握手时上报协议版与内容哈希。
- 允许客户端缺少服务端私有掉落权重，但不可缺少当前地图的公开表现定义。

### 5.2 定义、实例与视图分离

- **定义**：物品模板、配方、怪物模板、地图静态数据；只读且有稳定 ID。
- **实例**：角色拥有的一件装备、某张地图里的一个怪物；有唯一 `entity_id` 或
  `item_instance_id`，由服务器创建和保存。
- **视图**：客户端可见快照；只包含该玩家当前获准知道的字段。

不要把 `Texture2D`、NodePath、Callable、Godot Resource 二进制对象或任意脚本类通过网络
传输。协议负载只使用经过验证的标量、数组和字典；资源以稳定 `asset_id` 引用。

### 5.3 命令信封

可靠业务命令应带幂等和排序信息：

```text
protocol_version
message_type
session_id
command_id             # UUID/足够唯一的字符串
client_sequence
expected_revision      # 背包、交易、任务等聚合版本
payload
```

服务端响应带 `command_id`、结果码、最新 revision 和产生的公开事件。禁止用中文错误文本作为
逻辑分支；协议发送稳定错误码，客户端本地化显示。

## 6. 网络通道与消息

建议使用三个 ENet 通道：

| 通道 | 可靠性 | 消息 |
|---|---|---|
| 0 控制 | reliable ordered | 握手、入图、切图、断线恢复、协议错误 |
| 1 命令 | reliable ordered | 点击移动意图、交互、攻击请求、拾取、背包、制造、交易、任务 |
| 2 状态 | unreliable ordered | 10 Hz 快照、非关键朝向/动画状态 |

第一版不做 Delta 压缩，按地图兴趣范围广播必要的完整实体状态；实体数量实际成为瓶颈后再加
脏字段位图。可靠事件与快照可以重复包含最终状态，客户端按序列号丢弃旧包。

### 6.1 核心消息

客户端到服务端：

- `hello(protocol_version, public_content_hash, client_build)`
- `join_world(character_id)`
- `move_intent(map_instance_id, requested_world_point, input_sequence)`
- `map_transition_intent(map_instance_id, transition_id, destination_entry_number, input_sequence)`
- `interact_intent(target_entity_id, action_id)`
- `use_ability_intent(map_instance_id, ability_id, target_entity_id, input_sequence)`
- `inventory_command / craft_command / trade_command / quest_command`

服务端到客户端：

- `welcome(session_id, server_tick, required_content_version)`
- `map_joined(map_id, map_instance_id, entity_id, spawn_position, definition_version, server_tick)`
- `command_result(command_id, result_code, revisions)`
- `world_snapshot(server_tick, server_time_seconds, entities[])`
- `domain_events(events[])`，用于发射、命中、掉落、升级等一次性表现
- `position_correction(authoritative_position, reason)`

移动意图只提交用户目标。当前是低频的点击寻路，最后一次目标不能因丢包永久消失，因此走
可靠命令通道；若以后改成连续摇杆输入，再改为带冗余重发和确认序号的不可靠有序流。客户
端可立即用同一导航数据预测路径，服务器独立执行最近可达点选择、A*、视线拉直、速度与
动态障碍校验。每个实体快照统一包含 `entity_id`、`server_tick`、`position`、
`facing_direction`、`action_id`、`speed`、`state_revision` 和
`acknowledged_input_sequence`；本地玩家使用自己实体上的确认序号重放未确认意图，远端角色
在快照间插值。当前协议仍处于首个未发布版本，故不提供旧字段兼容别名；客户端和契约层会
明确拒绝 `direction`、`action`、`ack_input_sequence`，以后已发布协议的破坏性变更必须提升
`protocol_version`。

`MoveIntent` 在信任边界采用精确字段白名单，只接受 `map_instance_id`、
`requested_world_point` 和 `input_sequence`；包括 `speed`、`velocity`、`position` 在内的
任何额外字段都按非法载荷拒绝，而不是静默忽略。移动速度只来自服务端配置和权威实体，客户
端无法通过移动命令覆盖。坐标对象同样只接受 `x/y`。

阶段 3 的 `UseAbilityIntent` 同样采用精确字段白名单，只允许当前地图实例、业务技能 ID、
目标实体 ID 和独立递增序号。攻击力、伤害、目标坐标、射程、能耗和冷却均属于服务端权威
字段，客户端夹带时直接拒绝。首条能量炮纵切只实现实体目标；以后确需地面范围技能时新增
明确的目标类型/坐标契约，不复用任意形状的动态字典。

### 6.2 会话、切图和重连

- 连接身份与角色实体分开；一个角色同一时刻只允许一个控制会话。
- 断线角色按玩法规格保留 30 秒，服务端继续模拟；重连令牌只能恢复原会话角色。
- 切图由服务端验证出口距离、准入和目标入口后原子执行：旧实例移除、目标实例加入、广播。
- 普通旧传送只提供目标入口号，目标出生点由新服务端 `spawn_points` 配置；不得把源地图
  `approach_point` 当成目标落点。
- `AGTransPoint` 可使用显式目标坐标，`AGTransLine` 由共享地图模块计算对边落点。

`MapTransitionIntent` 使用精确字段白名单，只允许当前 `map_instance_id`、业务化
`transition_id`、该出口声明的 `destination_entry_number` 与独立递增序列。客户端不得提交
目标地图 ID 或出生坐标。服务端依次校验会话当前地图、序列、出口存在且启用、角色脚点距
`approach_point`（缺失时为 `source_anchor`）不超过配置半径、入口号与出口定义一致，以及目标
实例已被部署目录准入。未加载或仍属外部缺口的目标固定返回
`map_transition.target_unresolved`。

目标落点由目标 `MapDefinition.spawn_for_entry()` 解析；普通旧传送按入口号选择出生点并允许
显式默认点回退，只有 `client_point` 类型可采用经审计的显式目标坐标。迁移事务先在目标实例
完成可行走与动态占位校验并创建实体，再从源实例移除并更新会话；目标创建失败时源实体完全
不变。成功以可靠 `map_joined` 控制消息返回严格契约、目标地图首帧快照和
`transition_sequence`。失败的可靠 `command_rejected` 额外携带
`command_type=map_transition_intent` 和原序列，客户端无需解析错误码前缀即可关联命令。

权威服务器从 `map_directory.json.definitions` 建立地图实例注册表（同时接受提取工具使用的
`world_graph_seed.json.definition_paths` 形状），并保留可注入的实例
数组作为自动测试夹具。固定 tick 会推进全部已注册实例，但每个 peer 的快照只从其会话当前
`map_instance_id` 生成；不同地图的实体不会互相广播。地图目录是部署准入边界，网络请求永远
不能传入资源路径。

## 7. 模块边界

### 7.1 地图与移动

`MapDefinition` 保存静态世界尺寸、导航网格、动态覆盖声明、场景物、出口和出生点；
`MapInstance` 保存当前实体、动态障碍、矿点余量和实例生命周期。服务端只需导航和业务
数据，客户端另由 `asset_id` 加载底图、前景、场景物与小地图。

客户端和服务端共用已验证的菱形坐标转换、八邻域规则和视线检测。动态 `SetGoFlag` 类状态
作为 `navigation_overrides` 叠加，不改写原始网格。碰撞与遮挡仍是两套数据：服务端只裁决
脚点；客户端根据 `sort_baseline` 或前景拆层做 Y 排序。

实体脚点动态阻挡位于权威 `MapInstance` 层，默认启用，可通过
`dynamic_blocking_enabled` 和 `dynamic_blocking_radius` 配置。半径表示两个脚点中心间的最小
距离，不按两个“实体半径”再次翻倍。出生点和终点预约会选择最近的空闲导航点；寻路时临时
禁用其他实体占据范围内的图节点，逐 tick 模拟再以线段距离防止高速穿透。临时禁点在单次查
询后恢复，单实体寻路和原始静态导航数据不受修改；明确关闭该策略时允许脚点重叠。

### 7.2 实体与表现

领域实体只包含 ID、地图实例、脚点、运动、属性和状态；呈现节点负责身体、装备、阴影、
名称、动画和特效。八向动画方向在每条无遮挡路径段开始时量化一次，实际运动向量保持连续。

实体类型可使用组合数据，但首期不引入通用 ECS 框架。玩家、NPC、怪物、战车共享位置和
状态值对象，各自的行为由服务端系统调度。NPC 的商店/任务能力通过组件或能力 ID 配置，
不把每位 NPC 硬编码进场景。

本地玩家节点不是位置状态的所有者；它只投影 `LocalPlayerController` 的位置和动画意图。
NPC 也不再以“角色节点子类”作为长期业务边界：`NpcView` 负责表现，客户端环境控制器负责
插值或非权威氛围行为，`InteractWithNpcUseCase` 在服务端验证距离和能力。商店、任务和其他
服务由 action handler/service 组合，同一个 NPC 可以同时声明多种能力。

### 7.3 战斗与状态

服务端结算管线固定为：

```text
校验会话/状态/目标/距离/视线/冷却
-> 预占并扣除能量或弹药
-> 创建攻击或服务端投射物
-> 命中判定
-> 伤害与状态效果
-> 死亡、归属、奖励和技能经验
-> 持久化/审计事件
-> 广播表现事件与最终快照
```

伤害公式、PVP 倍率、发生器叠加和怪物 AI 参数均来自服务端配置。客户端只发送能力和目标，
不能上报伤害、掉落、经验或“已经命中”。投射物表现可以预测，命中结果必须与服务端事件
对齐。

D04 首条战斗纵切采用“每地图一个战斗世界”：`AuthoritativeMapInstance` 从
`CombatDefinitionCatalog` 按业务 `map_id` 装载刷怪组，拥有怪物生命周期、AI tick、玩家战车
资源和能力结算。`AuthoritativeServer` 只按已鉴权会话把 `UseAbilityIntent` 路由到当前地图，
再为每个接收者生成包含私有战车状态的战斗快照。客户端 `MonsterWorldController` 仅按
`combat_actor_id` 投影怪物，HUD 仅显示服务端生命/工作能量；任何客户端坐标、攻击力和耗能
都不会进入结算。编辑器离线模式通过 `OfflineCombatAuthorityBridge` 复用同一权威模块，
它是调试用进程内服务器替身，不是第二套客户端战斗规则。

怪物表中的已恢复生命、基础攻击与未知字段保持证据原义；为可玩纵切增加的 AI 速度、攻击
距离、游荡半径和 5 秒空闲游走间隔均显式标记 `reconstructed_default`。尤其奥姆幼虫和毒胶的已恢复基础攻击为
零，在持续腐蚀等服务端规则被证实前，不得为了“看起来合理”而制造伤害。

怪物游荡、追击和返巢均由地图实例基于同一导航图生成完整 AStar 路线，战斗模块只推进怪物
领域对象持有的路线进度。随机游荡候选会先收敛到同连通区域的可达脚点；无路线或单 tick
未产生有效位移时立即取消本次游荡、停止移动动画，并重新等待配置化游荡间隔，禁止持续朝
障碍物推进或由逐点吸附造成边缘抽动。

怪物死亡时 `DropTable` 只消费服务端私有概率并生成地面掉落值对象。`ground_loot` 随当前
地图战斗快照发布稳定 `loot_id`、物品定义、数量和位置；客户端拾取意图只提交 `loot_id`。
服务器先预检会话、地图与距离，再通过 `Player.receive_loot` 和 `Inventory.add_reward` 完成
堆叠/空间校验及持久化提交，最后删除地面实体，从而避免背包满时吞掉掉落。

地面掉落表现由独立 `GroundLootWorldController` 管理，不并入怪物生命周期。控制器从业务化
`ground_loot_v1.json` 读取语义资源，以荣耀 ALE 单帧的原始尺寸、原点和 1:1 比例挂到活动
世界的 Y 排序层；快照缺失即删除视图。鼠标命中使用同一真实帧矩形，线上交给服务端校验，
离线调试也复用“战斗预检 → 正式背包规则入账 → 地面实体提交删除”的两阶段边界。原客户端
地图物品拾取半径为 125 像素，服务端据此校验，客户端不预判距离或背包空间。

### 7.4 物品、装备与背包

`ItemDefinition` 描述模板；`ItemInstance` 保存数量、耐久、绑定、强化点和随机属性。
`Inventory` 是带 revision 的 40 格聚合，服务端负责堆叠、拆分、空间和槽位校验。

人物装备与战车装备使用不同的装配上下文。客户端 22 槽只是协议容量线索，实际战车型号的
可用槽必须来自定义。装备变更、强化、商店和拾取都通过库存事务服务，不允许模块分别改写
货币与物品。

### 7.5 制造、采矿与经济

配方定义输入、输出、技能、耗时、成功规则和经验。生产作业是服务端状态机；批量生产拆成
逐次事务，每次完成时重新校验材料和背包 revision。采矿同样由服务端周期结算，客户端
动画结束不是成功依据。

商店价格和回收价属于服务端经济配置。玩家交易使用 `proposed -> both_locked -> committed`
状态机；双方锁定后任何内容变化都解除确认，最终在单一事务中交换。

### 7.6 NPC 与任务

NPC 定义仅声明外观、位置/巡逻和能力：`shop_id`、`quest_giver_id`、`service_ids`。客户端
显示上下文菜单，服务端根据距离和能力验证交互。

任务是服务端聚合，目标通过领域事件推进，例如 `monster_defeated`、`item_acquired`、
`recipe_completed`、`map_entered`。普通掉落和任务掉落分别结算；任务 UI 只显示服务端投影。

当前 `NpcBase` 的客户端巡逻和 `ShopNpc`/`QuestNpc` 占位子类只用于原型表现，不得直接扩展
为正式商店或任务领域层。正式交互必须通过稳定 NPC ID、能力 ID 和服务端用例完成。

### 7.8 HUD 语义边界

HUD 负责固定像素锚点、控件状态和各类提示频道，但不拥有玩家、地图或网络状态。对外接口
使用业务语义，例如 `show_movement_status`、`show_network_notice`、
`show_npc_interaction`、`set_map`、`set_reserve_energy`；对外事件使用 `npc_action_requested`、
`hud_action_requested` 等业务信号。入口、网络 presenter 和玩法模块不得获取 `hint_label`、
`popup`、`minimap_player_dot` 等内部节点，也不得争用同一个 Label 形成隐式状态机。短时提示
应进入按频道或优先级管理的通知队列。

### 7.9 服务端应用边界

`AuthoritativeServer` 当前同时包含进程启动、ENet 回调、Tick、会话、移动、切图和 wire
序列化，是渐进拆分的兼容 facade。按顺序抽出 `MapTransferService`、`SessionService`、
`ServerSimulationLoop` 和 `ServerCommandRouter`；领域事务必须能在没有 RPC 和场景树的
测试中运行。客户端 payload 只提供意图，身份来自 peer/session，位置、伤害、掉落、冷却和
经济结果始终由服务端重新计算。

### 7.7 存档与审计

需要持久化的最小聚合：账户/角色、技能、人物装备、战车与部件、背包、任务、解锁、地图
出生点和进行中的交易/生产恢复信息。瞬时投射物、特效和客户端路径不保存。

当前第一版聚合已覆盖账户/角色、12 项人物技能等级、40 格背包堆叠、人物/战车装备槽与耐久、
战车生命/储能/工作能量/输出功率、地图实例/位置/检查点；任务和经济审计在各自纵切接入时
扩展 schema。
完整实现边界与当前驱动缺口见 `docs/persistence_architecture.md`。

库存、交易、制造、强化、拾取和管理命令写入审计流水：操作 ID、角色、类型、输入 revision、
变更摘要、结果和服务器时间。存档写失败时业务事务整体失败，不能先向客户端发成功。

## 8. 配置和未知规则

玩法文档标记为【重建默认】或【待验证】的规则全部进入有版本号的服务端配置，例如 Tick、
伤害随机区间、怪物警戒/刷新、掉落保护、生产耗时和升级机成功率。客户端只复制展示需要的
公开值，最终以服务器下发版本为准。

随机结算由服务端拥有；测试中允许注入固定种子。每次重要随机结果记录配置版本和随机上下
文，便于复现。后续得到新证据时替换单一配置或领域服务，不修改协议的无关字段和美术层。

### 8.1 领域对象组装规则

JSON、SQLite 行和 RPC 字典只能作为边界 DTO。通过目录与 schema 校验后，必须尽快组装为具有
行为的领域对象；应用服务不得继续用字典字段完成耐久、换装、属性汇总、索敌或攻击规则。

- `MovableEntity` 只拥有坐标、速度、朝向和移动方法；`Player`、`MonsterLifecycle`、`NpcBase`
  分别增加玩家聚合、怪物战斗和 NPC 交互职责。
- 物品按业务类型继承，不按每个定义建类。实例数值来自配置，耐久、修复、装备限制和数值贡献
  由对应类型的方法维护。
- `Player` 持有背包、固定人物装备、固定战车装配和技能对象；人物面板、战车面板与世界角色
  只允许消费这一聚合的投影或子对象。
- 怪物同时持有 `MonsterAggroPolicy`、`MonsterAttackMode`、`DropTable`、血攻防、出生点和 AI
  运行状态；权威模拟循环只推进对象，不维护平行的 `monster_runtime` 字典。
- `NpcBase` 是纯领域基类，商店、任务等具有特殊业务的 NPC 使用领域子类；`NpcWorldView` 仅负责
  导航路径与动画，并通过工厂选择对应领域类型。

## 9. 测试策略

### 9.1 测试层级

1. **纯规则单元测试**：坐标转换、导航、速度、技能门槛、伤害、背包、配方、状态覆盖。
2. **契约测试**：schema 版本、必填字段、稳定 ID、消息往返、旧内容迁移和错误码。
3. **服务端模拟测试**：用固定 Tick/随机种子运行怪物、采矿、制造和掉落，不启动渲染。
4. **网络集成测试**：启动一个无界面服务器和两个测试客户端，验证加入、移动、校正、切图、
   断线重连和命令幂等。
5. **地图黄金测试**：导航字节长度、世界/网格往返、出生点和出口可达、目标地图引用审计。
6. **表现验收**：代表性八向动作、叠衣、遮挡、HUD 锚点和窗口尺寸人工截图对照。
7. **素材门禁**：每次导入运行命名检查、来源 manifest 检查和必要资源可视化验收。

当前没有测试框架依赖。第一阶段使用可由 Godot `--headless --script` 执行的轻量测试入口和
明确退出码；只有当断言组织成本明显上升时再评估 GdUnit4，避免先引入与玩法无关的插件。
真实 ENet 集成由 `tools/run_enet_integration.ps1` 编排三个独立 Godot 进程，避免把内存内
函数调用误当成网络测试；用例会自动退出并验证双客户端实体隔离、互见快照、连续移动广播、
定向拒绝以及宽限期内恢复原实体。

### 9.2 每次提交的最低检查

- 每个提交只完成一个可独立说明、测试和回退的模块或模块子步骤；模块较大时允许由多个连续小提交完成，不允许等整个阶段结束后一次提交。
- 暂存区文件数不得超过 20；`git diff --cached --numstat` 中所有文本新增行与删除行之和不得超过 2000。二进制文件按文件数计入，但不虚构文本行数；超过上限必须继续拆分。
- Godot 无界面导入/解析成功，脚本无编译错误。
- 受影响单元与集成测试通过。
- `tools/check_asset_conventions.ps1` 通过。
- 新数据通过 schema/引用完整性检查。
- 没有把 `.godot/`、原始解密包、离线 composite 或审计图加入运行时目录。
- 任何服务端规则变化同时更新配置版本、测试和玩法依据链接。

### 9.3 GDScript 函数文档规范

所有具名 GDScript 函数都必须在声明前使用 Godot 原生 `##` 文档注释；范围包括公开函数、私有函数、静态函数、生命周期回调、RPC 和测试辅助函数。匿名闭包由其所属函数的文档解释，不要求逐个添加独立文档块。

统一格式如下：

```gdscript
## 根据服务端确认位置修正本地预测状态。
## [param authoritative_position] 服务端返回的权威世界坐标。
## [param acknowledged_sequence] 服务端已处理的最后一个输入序号。
## Returns 修正后仍需重放的输入数量。
## Design: 校正策略只处理预测缓存，不直接驱动角色表现节点。
func reconcile(authoritative_position: Vector2, acknowledged_sequence: int) -> int:
```

约束：

- 第一行必须说明函数对业务或模块承担的职责，不能只复述函数名。
- 每个具名入参都必须在文档块中以 `[param 参数名]` 引用并解释；可独占一行，也可自然嵌入职责描述，无入参时省略。
- 非 `void` 返回值必须使用 `Returns ...` 解释含义；构造/回调没有返回值时省略。
- 涉及状态机、策略、适配器、权威边界、缓存一致性或可替换实现时，必须增加 `Design:` 段，解释抽象边界及不负责的内容。
- 注释描述契约和原因，不逐行翻译实现；实现变化导致契约变化时必须同步更新注释。
- `@rpc` 等注解可以位于文档块与函数声明之间；文档块仍归属于紧随其后的函数。
- 工程检查通过 `tools/check_gdscript_doc_comments.py` 拒绝缺失参数或返回值说明的新函数。

## 10. 素材来源门禁

所有本轮之后新增的正式可见/可听素材默认只能来自荣耀版的既定原始和解析根。唯一例外是
`docs/free_hud_rendering.md` 第 1 节列出的免费版 HUD 外观白名单；小地图内容、弹窗和全部
非 HUD 素材仍不得跨版本。导入步骤是：

1. 先写业务 `asset_id` 和目标业务目录。
2. 在获准的版本解析库定位 PNG/音频/帧表，并从脚本确认动作、方向、锚点与用途。
3. 复制按需子集并业务化重命名，不保留 `pic/pic2`、时间戳、哈希或补丁目录。
4. 写 `source_manifest.json`：发布版、逻辑路径、原 FCH/ALE、导出工具、哈希、帧/方向、人工状态。
5. 在 Godot 中预览代表性状态并运行命名门禁。

免费版除 HUD 白名单外、激战版全部内容均只能做格式研究，不能自动回填正式素材。当前大厅已经整体迁移到荣耀版
`RoomSvr1` 的 `NFT_BT/NFT_SK` 分支，旧大厅底图、碰撞、构件和参考截图均已从运行目录
移除；4 个荣耀版源包本身缺失的构件依赖只记录为空，不跨版本补图。怪物正式目录也已按
荣耀版 `npcinfo_xc + npcclt1` 证据重新生成，并由来源 manifest 审计。

## 11. 安全与运维基线

- 服务端拒绝未知协议版、超频命令、非法实体 ID、越界数值和非当前地图目标。
- 所有 RPC 从 `multiplayer.get_remote_sender_id()` 绑定会话，不信任负载内自报的玩家 ID。
- 邀请码或预共享凭据只用于建立会话，不写入客户端仓库；公网部署时再增加加密隧道或认证
  网关，因为原生 ENet 不等同于完整的账户安全方案。
- 服务端配置端口、保存目录、日志级别和世界种子由命令行/环境配置注入，不散落在脚本。
- 日志包含会话、命令 ID、地图实例和 Tick，不记录口令；重要经济操作保留结构化审计。
- 服务端定期备份 SQLite，并在迁移前自动生成可恢复副本。

## 12. 完成定义

某个玩法模块只有同时满足以下条件才算完成：

- 服务端拥有并校验状态，客户端只提交意图；
- 数据定义有 schema、稳定 ID、版本和来源；
- 至少有正常路径、非法请求和重复请求测试；
- 断线/切图/背包满等相关失败不会复制或丢失物品；
- 所需素材通过版本白名单、来源门禁和代表性视觉验收；
- 玩法依据、重建默认和仍待验证项在文档中可追溯。
