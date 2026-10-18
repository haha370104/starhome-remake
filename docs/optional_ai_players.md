# 可选AI玩家：启用与维护

状态：2026-10-14～15已接入。默认关闭，不需要配置文件或模型密钥。它控制独立角色，不接管你的角色。
社区提交 `1f46553bd479d3413fdb082444e77cb8831e03dc` 的观察、决策、执行分层思路被重新适配；没有搬入其大型控制器、素材改名或多人社交服务。

## 快速体验：不联网的演示模式

从主仓库根目录运行，Godot路径按实际安装位置修改：

```powershell
& "C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe" --path . -- --enable-ai-players --ai-config=res://config/ai_players.example.json
```

示例创建一个 `explorer` 角色，在初始大厅中走动。野外遇到合适目标会开火、拾取自己的战利品；植物园中会尝试采摘；生命过低会返回基地。
演示提供器是本地规则程序，不是大模型，不理解自然语言目标，也不会自主规划跨地图成长。它用于先确认模块能正常启动、行动和与真人共存。

直接按原来的方式启动游戏，或显式加 `--disable-ai-players`，即可关闭。关闭参数优先于启用参数，顺序不限。
不需要修改 `project.godot`；本次没有替你长期开启AI。

## 接入真实模型

1. 将 [Responses示例](../config/ai_players.responses.example.json) 复制到仓库外的本地目录。
2. 填写 `model` 为你有权限使用、支持函数调用的模型名；`endpoint` 默认是 OpenAI Responses API。
3. 在启动游戏的同一个 PowerShell 进程设置 `STARHOME_AI_API_KEY` 环境变量。密钥不写入JSON、Git或启动参数，也不复用其他应用的登录凭据。
4. 启动时指定你的配置路径：

```powershell
# STARHOME_AI_API_KEY 已在本终端环境中配置。
& "C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe" --path . -- --enable-ai-players "--ai-config=C:/Users/tomato/Documents/starhome-ai.json"
```

配置内 `actors[].goal` 是该角色的自然语言目标，例如“先在基地购买适合的装备，再去低级野外练级，生命低时回基地”。模型只从当前观察中选择行动，不保证每个模型都能完成长期目标。
更换服务时必须确认提供的是 **Responses函数调用接口**，不能直接填写 Chat Completions 地址。
外部地址要求HTTPS；本机 `localhost` / `127.0.0.1` 的HTTP只供本地模型或测试。

真实模式会把该AI角色的有限观察（自身背包、装备、技能、任务、附近目标及行动结果）发送给所配置的模型服务，并产生该服务的调用费用。不会发送真人背包、会话令牌或密钥到模型输入中。
`store:false` 控制Responses应用状态存储，不代表服务商不保留安全日志；具体数据政策由所选服务决定。
本轮只调用本机模拟HTTP，没有使用真实模型账户、产生在线调用费用或验证某个收费模型的规划效果。

协议参考：[OpenAI函数调用](https://developers.openai.com/api/docs/guides/function-calling)。

## 参数与默认限制

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `provider` | `demo` | `demo` 本地规则；`responses` 真实模型 |
| `actors` | 必填 | 1～8个角色；`id` 为稳定英文标识，`goal` 为目标 |
| `decision_interval_seconds` | 10 | 一次行动结束到下次决策的最小间隔，范围2～300秒 |
| `requests_per_minute` | 6 | 整个模块共享的每分钟决策请求上限，范围1～60 |
| `max_requests_per_session` | 120 | 本次游戏进程总决策次数，范围1～10000；用完暂停AI |
| `max_output_tokens` | 1024 | 每次模型输出上限，范围128～4096，不等于总费用上限 |
| `timeout_seconds` | 20 | 单次请求时限，范围1～120秒 |
| `observation_radius` | 900 | 附近目标观察半径，范围100～1500像素 |
| `api_key_env` | `STARHOME_AI_API_KEY` | 真实模式读取的环境变量名 |
| `memory_directory` | `user://ai_players/memory` | 独立计划与有限行动记录目录 |

只有启用后才读取配置。未给 `--ai-config` 时读取 `user://ai_players/config.json`；这个文件默认不存在。
角色ID只允许英文字母或下划线开头、随后字母数字下划线，最多48字符，不能重复。
更改ID会创建新角色；保持ID会恢复该AI以前的装备和进度。所有角色共用一次在途模型请求，错峰轮转观察。

预算耗尽或连续三次模型失败只暂停AI；正常退出后重新启动才有新进程预算。
HTTP采用Godot非阻塞异步请求，响应限制256KiB，模型输入限制128KiB；单次行动最多持续30秒。
狩猎期间执行器按有限频率继续开火，每发仍经过正式武器冷却和能量校验，不为每发子弹请求模型。
每类观察最多32个目标，背包最多80项，历史最多20条，模型计划最多256字符。商品/配方查询同样有限裁剪，不等于全目录百科。

## 支持的行动

- 移动、接近传送点并切图、接近怪物并连续攻击、维修、回基地。
- 接近矿点并开始采掘、植物园自动接近采摘、拾取自己的击杀掉落。
- 查询商人，购买/出售，接取/交付/放弃循环及训练任务。
- 查询制造和生产、启动/暂停/恢复/取消生产，使用背包物品、换装、拆分和合并。
- 查询日常任务状态；日常委托的接取/交付尚未开放给AI工具。

所有物品、版本号、距离、冷却、装备、技能、容量、价格和奖励都由现有服务器裁决。模型不能指定账号、存档版本、奖励或任意内部命令；不能执行代码、读取文件或调用社交接口。
AI只选择自己的战利品，不自动捡真人主动扔下的装备。没有独立的好友、聊天、组队或交易机器人。
AI拥有正常新角色的初始资源，没有测试账号的高等级或额外货币。

## 独立服务器

单机进程内服务器和独立服务器共用开关。独立服务器示例：

```powershell
& "C:/Users/tomato/Downloads/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://scenes/server/dedicated_server.tscn -- --enable-ai-players --ai-config=res://config/ai_players.example.json
```

连接远端服务器的客户端不能替远端开启AI，也无需配置密钥。是否生成AI由运行服务器的人决定。
AI在世界快照中表现为普通远端角色，客户端主入口、HUD和地图控制器没有接入模型调用。
本版沿用现有远端角色的通用外观和身份标签，未另做AI换装外观或专属人物命名界面。
本版使用启动参数配置，没有增加默认勾选项或要求普通玩家填写AI资料。

## 存档、日志与关闭

AI使用 `local.ai_<id>` 身份与独立本地连接编号，真人继续使用原有 `player.*` 身份分配；AI先启动也不会占据 `player.1`。
角色进度通过原有权威仓储保存，与真人记录共享存档文件但身份隔离；没有新增真人必填字段，不需要清档。
AI计划单独保存为 `user://ai_players/memory/<id>.json`，通过低优先级文件队列异步写入。删除这些计划文件只遗忘计划，不删除角色装备。
Windows默认 `user://` 位于 `%APPDATA%/Godot/app_userdata/starhome_remake/`；若设置了用户目录覆盖，以Godot实际路径为准。

正常退出：取消在途HTTP，保存自己的角色、排空记忆队列，释放AI会话；不等待远程模型返回。
运行时开发接口 `OptionalAiPlayers.stop()` 可关闭模块而保留真人连接；普通用户下次去掉启动参数即可。
AI角色的记忆文件包含最近结果码；日志中的 `Optional AI players started` 表示已启动，`AI角色…已暂停` 表示预算或连续失败。
配置缺失/无效、密钥缺失只产生AI提示，不阻塞普通游戏。角色保存失败会明确报告，并退回原有断线保留/自动保存流程；不把保存失败伪装成成功。

## 工程边界与验证

代码位于 [scripts/server/optional_ai](../scripts/server/optional_ai/)。

| 模块 | 职责 |
| --- | --- |
| `AiPlayerSettings / AiPlayerAction` | 校验外部配置与函数调用，形成类型化对象 |
| `AiPlayerModule` | 角色生命周期、错峰调度、预算、失败退避与结果记录 |
| `AiWorldPort / AiAuthorityAdapter` | 有限观察与权威行动；只有适配器认识完整服务器 |
| `AiPlayerExecutor` | 接近、停止路径、持续开火及行动时限 |
| `AiDecisionProvider` | 可替换异步决策接口；当前有演示与Responses实现 |
| `AiPlayerMemory` | 独立有界记忆及后台写入 |

核心仅保留配置开关和条件动态安装入口；关闭时不加载AI脚本，不读取配置/环境密钥，不创建AI节点、HTTP请求、记忆线程或轮询器。
`main_hall`、领域模型、素材子模块和人类存档格式不依赖AI。客户端本地启动适配器只负责把命令行参数传给通用服务器配置。

测试已纳入两个总门禁入口。专项覆盖：默认关闭不加载、配置失败降级、独立身份持久化、真实移动/切图/采摘、开火耗能与冷却、物品归属、采矿装备约束、预算、重试暂停、过期决策、HTTP成功/失败/超时/取消、异步记忆及关闭清理。
当前Godot线程模式在无响应本机接口测试中曾阻塞超时取消；现使用非阻塞HTTP模式，该复现通过。参见 [Godot HTTPRequest接口](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)。

本轮新增7个专项共122项断言通过；既有6个登录/切图/驻留/存档回归共1137项断言通过，另完成真实OpenGL同场景显示及命令行启用后退出检查。
脚本零警告、架构与文档门禁通过；没有重新执行整个项目总测试集。分步记录见 [验收记录](verification/optional_ai_players_2026-10-15.json)。
