## 已经完成

- 服务端可以注册一个 LLM 控制器接管断线玩家。
- LLM 只能看到经过过滤的观察数据：
  - 自身位置和状态
  - 附近可见实体
  - 公开目标和事件
- LLM 只能返回高层动作，不能直接改坐标、背包、伤害或存档。
- 当前动作支持：
  - `wait`
  - `travel_to_area`
  - `hunt_monster(species_id, combat_mode)`（只狩猎当前场景指定种类的一只怪物，结束后反馈结果，由 LLM 决定下一步，不自动换怪续猎；`stationary` 接近后原地打，`shuttle` 两点往返边走边打，`hexagon` 绕怪物走正六边形边走边打；服务器选择目标、武器和路线，优先复用可行布局，受阻时最多检查 4 个合法半径×24 个朝向，校验接入段和整圈路线的障碍、动态占位及射程；找不到可行布局才反馈失败，不擅自改模式）
  - `gather_mine`（只提交可见矿源，服务器复用采矿装备、技能和能耗校验）
  - `self_repair`（请求开始战车自维修，服务器校验当前战车、维修技能和状态；满血或能量不足停止时再通知 LLM）
  - `return_to_base`（复用普通玩家的三秒基地救援与生命恢复，不允许模型指定目的地或生命值）
  - `manage_objective`（只提交当前观察中的任务和操作，服务器复用 Commerce/Quest 事务）
  - `send_chat`（区域、队伍或对已知在线玩家的跨地图私聊，不要求目标在当前观察中；服务器复用在线状态、聊天频率和频道校验）
  - `manage_party`（邀请、申请、接受/拒绝、离队、踢人和转让队长，服务器复用组队状态机）
  - `manage_trade`（邀请、接受/拒绝、物品、金币、锁定和取消，服务器复用双方锁定及原子提交）
- `travel_to_area` 会由服务器解析区域；同图转换为普通移动意图，跨图则绑定当前地图出口，走到接近点后自动完成迁移，不再要求模型重复下达同一指令。切图成功只返回抵达状态、目的地图标识和名称，不返回人类切图回包中的世界/本地战车快照；新区域详情仍由过滤观察和查询提供。`pickup_loot` 和 `gather_mine` 同样自动接近后重做权威资格、距离和状态校验；只操作当前场景，死亡、中断或新动作清除待执行意图。`return_to_base` 无参数，复用普通玩家三秒救援规则，返回基地后刷新观察。
- 最终仍走 Human 使用的同一套权威移动校验。
- 有异步延迟、超时、过期动作、重复动作、安全待机和 Human 重连保护。
- 行动实际完成后，程序进入定时 `wait`：战斗地图1.5秒，非战斗地图3秒；移动、狩猎、采矿和自修从完成事件开始计时，不从接受指令开始。新语义事件复用 `wait` 的提前唤醒规则，低层事件不唤醒；没有新事件则到期刷新观察并恢复决策。等待不额外请求模型、不伪造模型动作或函数回执，模型主动 `wait` 仍按原有低频规则唤醒。已有思考不因进入定时等待而被普通消息取消；查询续请求、移动速度和武器间隔不变。
- 已有控制器注册表，避免 LLM 状态散落在服务器各处。
- 事件进入收件箱，下一轮决策批量读取；只有交易报价/金币/准备/完成/取消、强制转移和外部动作失效立即中断，`wait` 中所有语义事件均可唤醒。死亡立即停止实际行为并更新观察，但不取消思考；首次受击摘要停止实际行为并请求重评估，不取消已有请求。旧请求返回的行动按最新观察和正常权威规则校验，合法就执行，同时将受击收件箱交给下一次决策；重评估期间的新受击摘要只入箱和刷新观察，不反复停止行为。普通工具错误只反馈，不升级为全局中断。
- 已抽出可替换的 `LlmProvider`，当前提供本地 Callable 与 Replay provider，不依赖网络。
- 已接入可替换的 OpenAI Responses provider；真实模型只通过用户本地配置文件调用，核心 Agent Runtime 不绑定供应商 session。
- 已建立语义工具注册表与路由器，工具描述随 Turn 传递，执行仍由服务端 handler 控制。
- OpenAI Responses 使用 strict function tools，一次只允许一个工具调用；查询继续同一 Turn，动作拒绝作为工具结果返回供模型重规划，成功动作启动确定性行为后结束 Turn。
- 查询和动作执行前刷新权威观察；真实续请求同时提交工具结果、新观察和收件箱，递归过滤运行时身份、版本和序号，不发送预算或重复工具定义。下一轮携带最近已接受动作及失败原因，接受不等同于确定性行为已完成。所有工具统一验证参数类型并规范 JSON 整数，单次请求超时统一为配置值（默认 180 秒），整轮最多 4 次请求；最后一次只提供行动工具，保留提交动作或主动等待的机会，不增加调用预算。
- 异步请求等待期间持续检查超时；更换 provider 会取消旧请求，旧回调不能完成新请求。模型请求失败后按连续失败次数退避 15/30/60/120 秒，成功响应重置；失败或中断会恢复尚未得到响应的整批收件箱事件，不只保留最近 8 条。冷却结束后由观察刷新/低频调度恢复，不因收到消息立即反复请求。中断仍可即时取消思考。退避只安排后续决策，不自动重放可能已经成功的游戏事务。[官方重试建议](https://developers.openai.com/api/docs/guides/rate-limits)
- 本地 `provider_input` 日志记录新增输入字节、整包请求字节和完整/差分模式；`provider_response` 记录同次输入量、请求耗时、HTTP/网络结果、响应状态及供应商返回的 token/cache usage；字节量不等同于 token 或费用。`turn_finished` 记录整轮耗时与调用次数，不记录密钥或加密压缩正文。未完成响应不能执行其中的函数调用。
- 已加入低价值事件过滤及 provider/tool/时间预算边界。
- 控制器保留有限原始事件环，并把最近事件随 Turn context 传给本地 provider；低价值事件仍不会唤醒模型。
- 服务端通过 `queue_llm_event()` 自动刷新过滤观察；移动抵达、受击摘要、死亡和社交消息会触发对应 Turn。尚未重评估受击时停止行走、狩猎、采矿和自修；模型空闲时立即重评估，忙时保留当前请求，合法旧行动可以先执行，后台决策收到新观察、受击摘要及已接受动作，结果返回后接管行为。始终只允许一个模型请求，程序行为可与思考并行；购买、使用物品和交易等一次性事务执行后不撤销、不自动重放。
- 当前已接入上述事件源，以及击杀后的任务进度、采矿背包满和动作失效。正伤害先合并 600 ms，按怪物 `species_id` 统计命中次数与总伤害；每次通知后固定冷却 5 秒，持续受击不延长冷却，期间伤害继续累计；冷却结束且合并已满 600 ms 时发送新摘要，无新伤害则不重发。模型忙时也投递摘要，不取消请求。权威拒绝动作通过同一工具调用返回失败，避免失败后直接待机。安全待机的通用低频复查由 15 秒调度器触发。
- 已支持 `spawn_llm_player()` 创建独立 `llm.*` 玩家：拥有独立角色存档、无网络 peer 的在线会话和可保存下线的生命周期。 上线会先提交一次过滤观察，再通过 `player_spawned` 事件启动首个 Turn。
- 独立 LLM 玩家会出现在同地图玩家投影中，食品时钟和社交可靠消息使用统一的在线会话边界。
- 已加入 World State Snapshot + Diff：首次观察记录完整初始状态，后续 Turn 上下文记录地图、自身、实体、目标和事件变化。
- Turn 记录初始观察、世界状态变化摘要和工具调用结果，可用于后续 replay 与诊断。
- 已接入确定性狩猎闭环：观察把存活怪物按种类聚合计数；LLM 选择种类和战斗模式，服务器选定一只实体，负责寻路、走位和武器执行；击杀后停止并以 `combat_result` 唤醒 LLM，目标被他人击杀或消失则反馈 `action_invalidated`，不自动续猎。
- 已接入确定性采矿闭环：LLM 选择可见矿源后自动靠近到合法采矿距离，再走现有采掘臂、技能、背包和能耗事务；采集成功以 `gather_result` 唤醒下一轮，持续采矿因能源或资格不足失败时以 `action_invalidated` 反馈；死亡或主动取消后的迟到预约不再次打断。
- 已补齐语义化世界观察：怪物只提供按种类聚合的数量，矿源和其他实体按权限投影；自身战车生命/能源、背包占用和货币可见，完整背包与服务端内部字段仍不会暴露。
- 已把当前地图任务发布者的公开进度投影到 Observation；任务需求、目标和完成状态可见，对话文本与里程碑奖励内部字段仍被过滤。
- 任务动作已接入 `accept`、`turn_in`、`abandon`；服务器持久化成功后投递 `objective_result`，再刷新观察并触发下一轮 Turn。
- 聊天动作已接入区域、队伍和私聊；自己发送聊天不会因成功回执开启新 Turn，其他玩家消息以 `chat_event` 进入收件箱，等待时立即唤醒。
- `inspect_private_chat(player_name, cursor)`（查看私聊记录）两个参数均允许 `null`：名称为空查看自己的会话列表；指定列表中的玩家名称读取最近 50 条，使用 `next_cursor` 翻阅更早消息，每对玩家合计保留最近 500 条。人类与 LLM 共用独立持久化档案，对方离线仍可查，同名会话拒绝猜测。返回名称、正文、实际发送时间和翻页游标，不返回内部角色标识或存储路径；历史不自动注入观察，不重放为新事件，不改变聊天唤醒策略。
- Observation 已加入经过过滤的队伍成员和待处理邀请；组队邀请进入收件箱，事务完成后以 `party_result` 触发下一轮。
- Observation 已加入好友关系和待处理好友邀请；`inspect_friends` 可查看，`manage_friend` 可邀请、回应和删除好友，最终由权威好友服务提交。
- `inspect_manufacturing(station_id, recipe_ids)` 分层查询：`recipe_ids: []` 返回该设施全部配方的编号、名称、要求等级和当前能否制造（不隐藏等级不足项），填写一个或多个编号批量返回这些配方的完整详情；设施、当前有效技能 `skill_levels`、订单和生产规则统一放在 `manufacturing` 顶层，详情不重复设施/当前技能。未知或不属于该设施的编号整批拒绝，重复编号只返回一份；两层均读取最新权威状态，人类制造面板不变。`station_id` 空字符串查询已有订单及其设施；`manage_production(operation, station_id, recipe_id, quantity, speed)` 开始/暂停/继续/取消订单，`quantity` 表示轮数。版本由服务器补齐，无网络 peer 的 LLM 按在线角色推进生产；提交后的轮次、暂停和写入失败以 `production_result` 入箱，不打断正常思考。概要不覆盖已学到的完整配方知识，仅详情进入配方热索引，原始查询仍保留在经历日志。
- `inspect_mail(section)` 查询自己的邮件/留言；`manage_mail` 发送、标记已读或删除，收件人支持已知名字或标识。复用人类玩家的持久化、限频和归属校验，自己的回执不触发通知循环，外来邮件遵守现有收件箱/等待唤醒策略。
- Observation 含经过过滤的交易邀请、当前报价和可交易物品摘要；邀请与其他社交事件进入收件箱，`trade_state`、`trade_completed`、`trade_cancelled` 允许立即中断，自身交易工具回执以 `trade_result` 触发下一轮，不反过来取消当前工具。原子提交包含双方未保存领域；完成或取消通知发出前清除交易会话，使下一轮观察与结果一致。
- LLM 跨地图出口由服务端按其自身所在地图实例解析；人类客户端当前显示的地图不参与 LLM 寻路。


## TODO

- 服务端会每秒自动刷新未处于 provider Turn 的 LLM 观察；调试或特殊流程仍可显式调用：
  ```text
  observe_llm_player()
  request_llm_decision()
  ```
- 事件分类器已接入部分权威事件；当前所有 LLM 事件入口都经由统一总线解析和去重，通用低频唤醒调度器每 15 秒只复查安全待机玩家，连续 `combat_result` 仍在控制器内局部合并。
- 任务、聊天、组队、交易、好友、邮件和生产订单的基础语义动作已实现；战斗、采矿、任务、生产、组队、交易和跨地图迁移事务由结果事件重新决策。
- 已持久化跨轮目标/计划、真实经历、可追溯的空间/配方知识和重复失败经验，支持后台旧日志检索；基于模型的复杂归纳、人格演化和目标调度仍未实现。
- 登录界面已支持勾选固定的 Riko `(LLM)` 角色上线；尚未支持创建或配置多个 LLM 角色。
- 没有真实模型下的延迟、费用、失败率和 D04 长时间性能验证。

### OpenAI Responses provider 配置

服务端支持用户本地的单文件 `config.toml`，Linux 默认优先使用 `$XDG_CONFIG_HOME/starhome-remake/llm/config.toml`；未设置 `XDG_CONFIG_HOME` 时使用 `$HOME/.config/starhome-remake/llm/config.toml`，也可以通过 `--llm-config=/path/to/config.toml` 指定。配置可以把密钥直接放在同一个文件中；如果没有 `OPENAI_API_KEY`，provider 会尝试读取同目录的 `auth.json`。

```toml
model = "gpt-6.1-sol"
model_reasoning_effort = "medium"
base_url = "https://proxy.example.invalid"
wire_api = "responses"
OPENAI_API_KEY = "clp_xxxx"
context_compact_threshold = 247520
```

`base_url` 可以填写站点根地址、`/v1` 地址或完整 `/v1/responses` 地址，provider 会统一请求 Responses API。配置文件和 `auth.json` 已加入 Git 忽略，不应提交真实密钥。

`context_compact_threshold` 默认 247520 token，即 272000 的 91%，预留 24480 token；可通过配置覆盖，设为 0 可关闭。该阈值不是计费上限保证，模型/中转站规则和单次新增输入仍需考虑。开启时每个请求附带 Responses 的 `context_management`；假设中转站支持服务端 compaction，不自行猜测或丢弃加密压缩内容。成功动作的真实回执在下一轮通过 `function_call_output` 返回，并延续 `previous_response_id`；中断/下线放弃供应商会话，游戏侧记忆仍然保留。返回压缩项时记入 `context_compacted` 调试日志，不记录其加密正文。API 会话不是永久记忆。

Provider 以成功完成并解析出的模型响应为送达基线，而不是逐帧世界差分：首次及切图发送完整 `observation`，后续 `observation_delta` 按字段整体替换，空对象/数组清空，遗漏表示未变化。两个事件来源只补送新增或更新通知，内部编号不暴露；内容相同但编号不同的消息仍分别发送。计划、最近动作和语义相同的记忆不重复发送，记忆排序/次数/时间更新不单独触发全文重发，实际内容或可信性改变仍带历史时间返回。去重指纹最多512条；失败、会话重建、中断、下线和服务端压缩后重新完整注入，压缩不破坏函数回执链。工具定义的查询结果与回执不截断，不修改长期记忆格式或91%阈值。

### 当前记忆实现

- `update_plan(goal, plan, next_step)` 保存玩家的主观目标，不改变游戏状态；三个字段都清空表示完成/放弃。计划不被当成已发生的事实。
- 每轮主动附带 `working_memory`、最近动作以及最多 6 条、合计不超过 8000 字符的 `relevant_memories`。`recall_memories(query)` 按地点/名字/怪物或关键词检索自己的经历；无需向量数据库和额外模型请求。
- 语义事件、实际工具反馈和动作接受/失败写入独立 JSONL 经历日志；相同经历合并计数，区域和查询记录更新到最近实际见到的结果。聊天保持“转述”，动作“接受”不等于执行完成，历史状态不替代当前观察。
- 空间知识只记实际见过的出口、矿物、NPC和设施；生产查询逐配方提取材料及技能要求，不把当时库存、有效技能或可生产状态当作永久事实。重复的同地同参数失败标注为需要重新验证的经验，不推断永久规则或他人可信度。知识保留原始来源位置与观察时间，可从日志重建；有限索引优先保留知识而非普通经历。
- `search_history(query)` 以关键词检索自己的完整已落盘日志：低优先级后台线程流式扫描，游戏帧不等待磁盘；同时仅允许一个任务。结果以 `history_search_result` 入箱，普通思考不打断、等待时唤醒；最多6条、合计8000字符，大记录明确标注截断预览，下线取消并回收线程。不另调模型，未开启持久化时只能检索本次热索引。
- 每名角色的记忆位于原生存档路径后追加 `.llm/<角色标识SHA256>/` 的目录；默认 Linux 为 Godot 用户数据目录中的 `server/player_states.json.llm/<SHA256>/`，含 `events.jsonl` 和 `memory.json`。关闭服务端存档时仅保留本次会话记忆。
- 文件写入复用低优先级后台线程，日志先于原子检查点；计划/动作结束、每 16 条记录及下线才生成检查点，避免每个事件复制整个索引。重新登录恢复计划并重放未进入检查点的日志尾部，检查点丢失或格式损坏时可从日志重建。日志保留原始证据，热索引最多256条，淘汰的经历仍可通过后台全文检索找回；尚未做模型归纳或永久遗忘策略。
- 单角色经历日志当前上限 1 GiB；写盘失败/达到上限会明确告警并停止推进派生检查点，不静默删除经历。正常下线排空后台写入；突然断电仍可能丢失未刷盘的尾部，半条 JSON 尾记录会在重登时修复。
- 参考本地 Codex 源码 `2351d9e1b608e6f9d9a3699b71d7eb39ee41cfa4` 的 `codex-rs/memories/`、`core/src/context_manager/` 和 `core/src/compact_remote_v2.rs`，借鉴原始 rollout/派生记忆分离、有限检索与压缩后重注入关键状态，不移植其多代理编排。参考源码保留在 `/tmp/starhome-codex-reference`，不并入游戏仓库。[Responses 压缩接口](https://developers.openai.com/api/docs/guides/compaction)

通过 `AuthoritativeServer.create_openai_llm_provider()` 创建 provider 后，再传给现有的 `spawn_llm_player()` 或 `register_llm_player()`；LLM 玩家身份、存档和权威动作链仍由游戏服务端管理。

### 当前实际水平

早期纵切验证过的流程（不是当前全部能力）：

```text
创建 `llm.scout` 独立玩家
    ↓
注册本地模拟 LLM 控制器
    ↓
读取过滤后的 D04 观察
    ↓
模拟模型返回“前往某区域”
    ↓
服务器解析目标
    ↓
进入普通权威移动流程
```

阶段验收文档记录了 2 个 Human + 2 个模拟 LLM 同图运行，相关控制权、重连保护和异步决策测试通过。

基础生产/邮件和本地证据知识、历史检索闭环已接通；后续重点是实际模型的长时间行为质量、知识更新和低价值重复行为，仍不通过提示词虚构能力或用记忆替代当前角色状态。

# Starhome LLM Player Architecture

目标：让 LLM 成为《星际家园》中的第一等独立玩家，而不是 NPC、陪伴角色、代打脚本或管理员代理。

## 1. 核心目标

LLM 玩家应与人类玩家处于同一抽象层级，拥有独立的：

- 身份
- 角色状态
- 位置
- 背包
- 装备
- 金币与资源
- 技能
- 任务状态
- 社交关系
- 长期记忆
- 持久化进度
- 自主目标与行为历史

LLM 玩家可以独立探索、移动、采集、战斗、交易、做任务、进入建筑和地图、使用物品、与 NPC 或其他玩家交流，也可以与人类玩家或其他 LLM 玩家组队。

“组队”只是普通游戏行为之一，不能成为 LLM 玩家的身份定义。

第一阶段允许只实现 1 个独立 LLM 玩家和单人 PvE，用于验证架构，但底层必须天然支持：

- Human ↔ LLM
- LLM ↔ LLM
- 多个并发 LLM 玩家
- 聊天
- 交易
- 组队
- 长期持久化
- 独立上下线
- 模型替换
- LLM provider 替换

核心目标不是增加“AI 队友功能”，而是让游戏从架构层面真正支持“非人类玩家”。

---

## 2. 第一原则：Human 与 LLM 共用同一玩家能力模型

不要建立两套平行的玩家逻辑。

正确方向：

```text
Player / Actor
├── HumanController
└── LLMController
```

二者的主要区别只存在于“决策来源”：

```text
Human:
键鼠 / UI
    ↓
玩家命令
    ↓
权威服务端

LLM:
感知
    ↓
高层决策
    ↓
受约束的玩家动作接口
    ↓
玩家命令
    ↓
权威服务端
```

LLM 必须通过普通玩家能力影响世界，不允许：

- 直接修改角色坐标
- 直接修改背包
- 直接生成物品
- 直接修改任务状态
- 绕过距离限制
- 绕过战斗规则
- 绕过冷却
- 绕过资源消耗
- 读取普通玩家不可见的服务器全局状态
- 调用管理员能力

权威服务端必须对 Human 和 LLM 使用相同的规则校验。

---

## 3. 第二原则：LLM 负责高层意图，不负责低层控制

不要把低信息密度、高频、强确定性的工作交给 LLM。

典型错误：

```text
附近怪物：
A (123, 417)
A (129, 422)
B (208, 301)
C (451, 92)
...
```

然后让 LLM 判断应该走向哪只怪。

这种做法：

- 浪费 token
- 空间判断不稳定
- 延迟高
- 成本高
- 不如普通算法可靠

正确做法是：

```text
LLM:
“我要猎杀铁甲兽”
        ↓
确定性程序:
扫描当前地图
→ 筛选铁甲兽
→ 选择具体目标
→ 寻路
→ 接近
→ 攻击
→ 处理冷却
→ 拾取
→ 重新搜索
```

LLM 负责：

- 去哪里
- 打哪类怪
- 做什么任务
- 采集什么
- 买卖什么
- 是否撤退
- 是否继续当前目标
- 是否组队
- 是否接受交易
- 如何回应玩家
- 长期计划与策略

普通程序负责：

- 自动寻怪
- 路径规划
- 移动
- 距离判断
- 具体目标选择
- 战斗执行
- 冷却管理
- 自动采集
- 交互距离检查
- 物品操作细节
- 任务交互流程中的确定性步骤

原则可概括为：

```text
LLM 负责 intent
程序负责 execution
```

---

## 4. 总体架构

推荐长期架构：

```text
LLMPlayer
│
├── PersistentState
├── LongTermMemory
│
└── AgentRuntime
      │
      ├── EventQueue
      ├── WorldStateSnapshot
      ├── ContextManager
      ├── TurnManager
      ├── ToolRouter
      ├── InterruptController
      └── LLMProvider
              ↓
        OpenAI Responses API
              ↓
        Semantic Player Tools
              ↓
        Deterministic Controllers
              ↓
        Normal Player Commands
              ↓
        Authoritative Game Server
```

OpenAI Responses API 可以作为第一版 provider。

但必须把模型供应商与 agent runtime 设计为可替换层。

不要让以下任意一个东西成为游戏架构本身：

- OpenAI session
- Agents API session
- Agents SDK runtime
- 某个模型名字
- 某种 prompt 格式
- 某个供应商的 memory/session 机制

正确边界：

```text
Game-owned LLM Player
        ↓
Starhome Agent Runtime
        ↓
LLM Provider Interface
        ↓
OpenAI Responses API / 未来其他实现
```

这样将来更换：

- 模型
- API
- provider
- agent framework
- context window
- memory implementation

都不会破坏玩家本身。

---

## 5. Agent Runtime 不是简单的无限 while，而是事件驱动状态机

基础工具调用循环确实很简单：

```text
model
→ tool call
→ execute tool
→ tool result
→ model
→ ...
```

但长期质量不来自这个循环本身，而来自：

- Turn
- Event
- World State Diff
- Interrupt
- Context
- Persistence

LLM 不应每秒持续思考。

推荐生命周期：

```text
发生值得决策的事件
↓
唤醒 LLM
↓
构造 observation + relevant memory
↓
允许若干查询工具调用
↓
LLM 做出高层决定
↓
启动确定性行为
↓
LLM 进入 sleep
↓
普通程序继续执行
↓
行为完成 / 失败 / 发生重大事件
↓
再次唤醒 LLM
```

典型唤醒事件：

- 到达目的地
- 目标区域资源耗尽
- 战斗失败
- HP 低于阈值
- 弹药或资源不足
- 背包满
- 死亡
- 收到聊天
- 收到交易请求
- 收到组队请求
- 新任务出现
- 当前任务完成
- 当前路径失败
- 新区域首次发现
- 当前策略无法继续
- 重要世界事件

不值得唤醒 LLM 的事件：

- 每帧位置变化
- 普通怪物坐标变化
- 每次攻击动画
- 每次冷却 tick
- 每次寻路节点变化

---

## 6. 从 Codex CLI 学习的关键点

不要复制 Codex CLI 本身，但应吸收其 agent harness 思想。

### 6.1 Turn / Active Turn 生命周期

一次 LLM “醒来”应有明确边界。

每个 turn 应记录：

- 触发原因
- 初始 observation
- 查询过的工具
- 工具结果
- 当前意图
- 最终决定
- 是否被中断
- 行动结果

Turn 结束后，大量临时上下文可以丢弃。

长期玩家不能等同于某一个 turn。

### 6.2 Tool Registry 与 Tool Router 分离

LLM 看见的是稳定的语义工具。

例如：

```text
inspect_self()
inspect_area()
inspect_inventory()
inspect_quests()
travel_to(destination)
hunt(monster_type)
gather(resource_type)
trade(...)
say(...)
```

但实际内部执行可以由多个控制器完成：

```text
hunt()
├── MonsterQuery
├── TargetSelector
├── NavigationController
├── CombatController
└── LootController
```

LLM 不需要知道内部实现。

这样以后：

- 重写寻路
- 修改战斗系统
- 修改网络协议
- 修改服务器实现

都不应该迫使 LLM 工具接口变化。

### 6.3 World State Snapshot + Diff

不要每次重新把完整世界状态塞给模型。

保存“模型上一次知道的世界状态”，下一次醒来时只生成变化。

首次：

```text
当前位置：植物园
HP：100%
背包：42%
附近：
- 椰子树
- 生豆树
- 玩家 A
当前任务：...
```

两分钟后：

```text
自上次决策后：
- 获得生豆 ×18
- 背包占用 42% → 78%
- HP 无变化
- 玩家 A 已离开
- 玩家 B 出现
- 当前区域生豆已耗尽
```

World State Diff 是降低 token、提高可读性和稳定性的核心机制之一。

### 6.4 Steering / Interrupt / Cancellation

LLM 决定：

```text
去宇航中心
```

TravelController 开始自动导航。

途中发生：

```text
战车死亡
```

此时不能等待 travel 完成。

推荐：

```text
重大事件
↓
中断当前确定性行为
↓
记录当前意图与进度
↓
唤醒 LLM
↓
重新决策
```

建立事件分类器：

```text
Game Event
↓
Event Classifier
├── ignore
├── deterministic handler
├── append observation
└── interrupt + wake LLM
```

### 6.5 Stable Prompt / Tool Prefix

系统规则、工具 schema、角色长期基础设定尽量稳定。

动态内容放后面：

```text
稳定部分：
- 行为边界
- 游戏规则
- 工具定义
- 角色基础人格

动态部分：
- 当前 HP
- 当前地图
- 最近事件
- 当前任务
- relevant memory
```

这样有利于 prompt caching，也减少行为漂移。

不要每一轮动态增删大量工具。

### 6.6 Context Compaction

不要无限累积历史 conversation。

当前上下文只保留：

- 当前目标
- 当前重要状态
- 最近关键事件
- 当前工具调用历史
- relevant memories

旧经历进入长期记忆系统，不要永久停留在上下文中。

### 6.7 Rollout / Replay / Checkpoint

每次 agent 决策链建议记录：

```text
trigger event
observation
retrieved memories
tool calls
tool results
chosen intent
interrupts
final outcome
```

用途：

- 调试 LLM 为什么做出错误决策
- 重现 bug
- prompt 调整后 replay
- 对比不同模型
- 行为 benchmark
- 崩溃恢复
- 分析 token 与延迟
- 测试新 agent runtime

---

## 7. 记忆系统

最重要原则：

```text
Raw Event Log = source of truth
Memory = derived data
```

任何长期记忆都应该可以从原始事件重新生成。

不要让 LLM 随口生成一句话就永久成为不可追溯的事实。

### 7.1 真实游戏状态不是 memory

以下内容属于权威游戏状态：

- 等级
- HP
- 坐标
- 背包
- 金币
- 装备
- 技能
- 任务完成情况
- 当前队伍
- 当前地图
- 当前服务器状态

这些应始终从游戏系统读取。

不要复制进长期记忆当作事实来源。

### 7.2 Working Memory

只服务当前 turn。

例如：

```text
当前目标：去宇航中心
刚才发生：途中遭袭
当前计划：先脱离战斗再继续
```

Turn 结束后可以大量丢弃。

### 7.3 Episodic Memory

保存“这个玩家经历过什么”。

原始事件示例：

```text
时间：...
地点：D04
遇到：Player_A
事件：Player_A 主动交易给我 1000 金币
结果：接受
```

这些信息来自游戏事件，不来自模型自述。

### 7.4 Semantic Memory

后台从多个经历中提炼知识：

```text
Player_A 对我友好
植物园可以稳定获得生豆
铁甲兽对当前装备威胁较高
```

建议附带：

- source
- confidence
- first_observed
- last_verified
- last_used
- usage_count

世界会变化，因此长期知识必须允许过期与重新验证。

### 7.5 Social Memory

按角色保存：

```text
Player_A
relationship = friendly
trust = ...
important_events = [...]
last_interaction = ...
```

不要把关系值当成服务端强制真理，而应视为该 LLM 玩家的主观内部状态。

### 7.6 Spatial Memory

只记录该玩家自己探索和学习到的空间知识：

```text
植物园
known_routes = [...]
known_resources = [...]
danger = low
```

服务器知道整个银河系，不意味着 LLM 玩家也应该知道。

LLM 玩家必须允许真正地说：

```text
“我没去过那里。”
```

### 7.7 Procedural Memory

记录“学会怎么做”。

例如：

```text
多次经验：
近距离攻击铁甲兽损血严重

提炼：
当前装备下应优先保持远距离攻击
```

这是第一阶段最推荐的学习方式。

不要优先做在线 fine-tuning。

先实现：

```text
Experience
→ Reflection
→ Learned Knowledge
→ Retrieval
→ Future Behavior Change
```

即可产生明显的长期学习效果。

---

## 8. 记忆生成应采用后台两阶段流程

参考 Codex CLI 的思路：

### Phase 1：Memory Extraction

玩家正常游戏时只记录原始 Event Log。

后台异步从一段经历中提取：

- 值得保存的事件
- 人际变化
- 地图知识
- 任务经验
- 战斗经验
- 新发现

不要阻塞正常 agent turn。

### Phase 2：Memory Consolidation

更低频地把大量 memory 合并成稳定知识。

例如：

```text
连续多次和 Player_A 合作
↓
Player_A 通常友好且可信
```

或者：

```text
多次在区域 X 遭遇高级怪
↓
区域 X 对当前等级风险较高
```

旧 memory 可以：

- 合并
- 降低权重
- 标记过期
- 被更可靠的新证据覆盖

---

## 9. Memory Retrieval

保存 memory 不是重点，检索才是重点。

每次 LLM 醒来时，根据：

- 当前地点
- 当前实体
- 当前任务
- 当前目标
- 当前事件
- 最近重要经历

检索少量相关 memory。

例如：

```text
当前实体：赤尾津
当前地点：宇航中心
当前目标：寻找队友
```

返回：

```text
Relevant memories:
- 赤尾津曾两次与你组队，关系友好。
- 他曾送给你一件装备。
- 你上次来宇航中心时入口尚未开放。
```

不要把玩家一生全部塞进 prompt。

---

## 10. Observation 设计

Observation 应提供语义化、压缩后的世界信息。

例如不要给：

```text
monster_1 x=123 y=417
monster_2 x=129 y=422
...
```

应该给：

```text
当前区域：荒野
附近可狩猎目标：
- 沙虫：很多，低威胁，经验低
- 铁甲兽：少量，中等威胁，经验较高
- 强盗：较远，高威胁

生命：82%
弹药：充足
背包：61%
```

Observation 应分成：

```text
Current State
Recent Changes
Current Goal
Current Constraints
Relevant Memories
Available Semantic Actions
```

---

## 11. Tool 设计原则

工具必须：

- 语义稳定
- 粒度适中
- 返回结果清晰
- 可验证
- 可取消
- 有明确成功/失败状态
- 不暴露管理员能力
- 不要求 LLM 处理大量坐标

建议区分两类：

### Instant Tools

立即返回结果：

```text
inspect_self
inspect_inventory
inspect_quests
inspect_area
inspect_relationship
inspect_known_locations
```

### Long-running Behaviors

启动一个确定性行为：

```text
travel_to
hunt
gather
trade
follow
escort
wait
```

Long-running behavior 需要：

- progress
- completion
- failure
- cancellation
- interrupt

不要让模型阻塞等待几分钟。

---

## 12. Agent Turn Budget

每次 LLM 唤醒建议有明确预算：

- 最大模型调用次数
- 最大工具调用次数
- 最大 token
- 最大 wall-clock time
- 最大连续失败次数

防止：

```text
inspect_self
inspect_self
inspect_self
...
```

或者陷入无意义工具循环。

如果预算耗尽：

- 保留当前状态
- 选择安全默认行为
- sleep
- 等待下一次事件重新唤醒

---

## 13. 并发 LLM 玩家

不要让 agent runtime 假设“世界里只有一个 LLM”。

每个 LLM Player 应拥有独立：

- identity
- persistent state
- event queue
- current turn
- memory
- provider context
- deterministic behavior state

服务端仍然只看普通玩家命令。

多个 LLM 之间不应有隐藏的 agent-to-agent 后门。

LLM A 想与 LLM B 交流，应通过正常游戏行为：

```text
say
trade
invite_party
follow
...
```

---

## 14. Provider 抽象

定义稳定 provider 接口，例如概念上：

```text
LLMProvider
- create_turn(...)
- continue_with_tool_result(...)
- cancel(...)
```

第一版实现：

```text
OpenAIResponsesProvider
```

未来允许：

```text
OtherCloudProvider
LocalModelProvider
ReplayProvider
MockProvider
```

ReplayProvider 和 MockProvider 对测试非常重要。

---

## 15. Persistence 边界

绝对不要：

```text
OpenAI conversation/session = LLM 玩家
```

应该：

```text
LLM 玩家 = 游戏数据库中的永久实体

模型上下文 = 某次醒来时临时构造的认知上下文
```

玩家可以活几年。

即使：

- 模型被替换
- provider 被替换
- API 改版
- context 被清空
- agent runtime 重写

玩家依然是同一个玩家。

---

## 16. 推荐实现顺序

### Phase 1：最小可行 Agent Runtime

实现：

- 1 个 LLM 玩家
- 可替换 Provider 接口；先用 Callable 与 Replay，不接真实模型 API
- TurnManager
- EventQueue
- 少量 inspect 工具
- 2-3 个高层行为工具
- deterministic travel / hunt
- 基本中断
- 基本日志

目标：

```text
LLM 能独立决定去哪里
→ 自动走过去
→ 自动打指定种类怪
→ 行为结束后重新决策
```

### Phase 2：World State Diff

加入：

- snapshot
- diff
- 最近变化
- token 优化

### Phase 3：Memory

加入：

- raw event log
- episodic memory
- memory extraction
- semantic memory
- retrieval

### Phase 4：Social / Spatial / Procedural Memory

加入：

- 玩家关系
- 自己探索出的地图知识
- 战斗和任务经验学习

### Phase 5：多人

加入：

- Human ↔ LLM
- LLM ↔ LLM
- 聊天
- 交易
- 组队
- 多 agent 并发

### Phase 6：Replay / Evaluation

加入：

- agent rollout
- replay
- model comparison
- benchmark
- debug UI

---

## 17. 第一阶段明确不做

为了避免架构被过早复杂化，第一阶段不要优先做：

- 在线 fine-tuning
- LLM 每帧控制
- 截图驱动寻怪
- 全地图坐标塞进 prompt
- 把 Agents API session 当玩家
- 把 Agents SDK 深度绑定进核心
- LLM 直接操作服务器状态
- 大规模多 agent
- 自主经济系统优化
- 复杂人格模拟
- 情绪模型
- 无限上下文
- 隐式管理员权限

---

## 18. 验收标准

架构第一阶段完成后至少应满足：

1. Human 与 LLM 使用同一玩家能力模型。
2. LLM 不能直接修改权威状态。
3. LLM 可以通过语义工具检查自身与局部环境。
4. LLM 可以给出高层意图。
5. 确定性程序可以独立完成寻路、寻怪和战斗执行。
6. 行为完成后能够重新唤醒 LLM。
7. 重大事件可以中断当前行为。
8. 普通低价值事件不会频繁触发模型调用。
9. 每个 turn 有预算和明确生命周期。
10. 模型/provider 可以替换。
11. 玩家持久化不依赖模型 session。
12. 原始事件可以用于重建长期记忆。
13. 决策链可以 replay。
14. 后续增加第二个 LLM 玩家时不需要重写核心架构。

---

## 19. 最重要的架构约束

在后续实现中始终保持以下边界：

```text
游戏世界属于服务端
玩家身份属于游戏
长期记忆属于游戏
Agent Runtime 属于游戏
工具语义属于游戏
确定性执行属于游戏
LLM 只是可替换的决策引擎
```

最终目标不是“把 ChatGPT 塞进游戏”。

目标是：

```text
让一个非人类智能体
以普通玩家身份
在同一权威世界规则下
拥有长期经历、记忆、目标与行为
并真正作为玩家生活在这个 MMO 世界中。
```
