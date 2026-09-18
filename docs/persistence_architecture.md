# 服务端权威状态持久化基座

文档定位：当前开发仓储与生产接缝；整体 review 见[评审导读](./review_guide.md)。

## 1. 当前能力结论

本机 `Godot_v4.7.2-stable_win64` 运行时不包含 SQLite 类、单例或已安装 GDExtension。运行时
探测结果为 `classes=[]`、`singleton=false`。因此当前工程不能宣称已具备 SQLite 落盘能力，
也不能用 JSON 文件冒充生产数据库。

本轮交付分为四个明确边界：

1. `PlayerStateRepository` 是服务端应用层可依赖的仓储接口，领域与网络层都不接触 SQL。
2. `SqliteDriverPort` 定义未来真实驱动必须提供的参数化执行、查询和事务能力；
   `001_initial.sql` 固定生产 schema。
3. `FilePlayerStateRepository` 是无外部依赖的开发/测试替身，用于验证迁移、聚合事务、revision
   冲突和断线重载。它使用可恢复的临时文件替换协议，但不具备 SQLite 的并发、WAL 或完整
   ACID 保证，禁止作为生产多人服存档。
4. 实际游戏默认每 60 秒采集位置、朝向、战车资源与最新角色状态，交给低优先级后台线程写盘；
   正常退出等待最新快照完成。普通事务即时更新内存，客户端仍只能发送意图。

## 2026-09-18：单机延迟存档策略

用户明确接受异常强杀时丢失最近几分钟进度，因此实际服务器创建的文件仓储启用后台模式。
装备、背包、钱包、掉落及技能升级仍进行同步内存事务与版本校验，成功回包表示内存提交成功；
不再每个经济操作或升级都序列化整份文件并等待磁盘。直接创建文件仓储的离线工具、显式注入的
测试仓储保留同步接口，游戏默认配置为60秒检查点，可由 `--autosave-interval-seconds` 调整。

`BackgroundFileWriter` 使用独立 `Thread.PRIORITY_LOW` 线程。主线程在检查点生成隔离的完整数据，
后台负责 JSON 编码、临时文件写入、刷新及备份替换。同路径尚未执行的旧快照会被最新快照替换，
在途文件由单个工作线程顺序完成，旧任务不会晚于最新存档覆盖它。游戏线程不等待普通检查点。

正常退出先采集最新状态，通过后台写入完成屏障后才返回保存回执、释放角色；失败保留角色及原
事务版本供重试。场景退出和无场景树的服务释放都会回收文件线程。系统强杀不增加补救流程；
下次启动保留既有 `.bak` 恢复逻辑。60秒是目标检查点间隔，磁盘长期繁忙或失败时并非最大丢失窗口。

专项验证慢盘下继续入队、快照合并与隔离、版本冲突、定时采集、退出失败不改状态、重试成功与重启读取。
本轮帧耗时及完整回归记录见[开炮与后台写入报告](verification/firing_background_io_2026-09-18.json)。

## 2. 状态所有权与依赖方向

```text
server application/use case
        |
        v
PlayerStateRepository
   |                  |
   v                  v
SQLite repository   FilePlayerStateRepository
   |                  (development/test only)
   v
SqliteDriverPort -> approved GDExtension adapter
```

- 网络层只提供已鉴权的会话身份和命令，不提交 SQL、账户 ID 或权威数值。
- 领域模块只计算状态；应用用例在一次仓储事务中加载、调用领域规则并提交完整聚合。
- 适配器负责序列化、迁移、乐观 revision 和持久提交，不在数据库触发器中隐藏玩法规则。
- 同进程重连以 `character_id` 加载最新已提交的内存聚合；进程重启以最后完成的磁盘快照恢复。
- 自动存档计时属于服务器应用层，实际游戏默认 60 秒；正常退出和服务器收尾等待磁盘完成。
  仓储不拥有游戏计时器，也不会自行从表现节点读取状态。

## 3. 最小聚合模型

`PlayerStateRecord` 当前覆盖首个经济纵切所需的最小状态：

- 账户：稳定 ID、显示账户名、状态；认证密钥不进入该聚合。
- 角色：稳定 ID、显示名、聚合 revision、生命、综合等级，以及按稳定技能 ID 保存的基础等级、
  当前等级经验和小数经验余量。
- 背包：容量、独立 inventory revision、稳定实例 ID、定义 ID、数量、容器、像素位置、占用矩形、
  锁定/绑定和耐久；旧 `slot_index` 只用于 schema 1 向后兼容。
- 装备：角色/战车 owner、业务槽位、荣耀客户端 Location、实例 ID、定义 ID、耐久和强化等级。
- 战车：实例/定义 ID、战斗生命、储备能量、工作能量和输出功率。
- 位置：业务地图 ID、运行时地图实例、脚点、八向朝向和 checkpoint。

JSON 只存在于文件替身的信任边界。读取后立即转换为 `PlayerStateRecord`、
`InventoryStackRecord` 和 `EquipmentSlotRecord`；事务回调只接收隔离的类型化副本。

生产 SQL schema 将账户、角色、人物技能、背包堆叠、装备槽、战车、位置和命令回执拆为独立表，并用
外键、唯一索引和 `CHECK` 约束保护最小结构不变量。`command_receipts` 为后续拾取、出售和制造
命令的幂等结果预留稳定落点。

商店/任务/制造现已存在权威用例，但持久化 `command_receipts` 仍是生产目标，不能混淆。
2026-09-14 修复了采矿周期编号跨服务器重启与旧矿石实例冲突；原存档无需清空，
详见 [采矿身份修复](mining_equipment_and_player_messages.md)。此修复不等于全部经济操作已具备崩溃安全幂等。

## 4. 事务与恢复语义

仓储提供两种写入口：

- `save_player(state, expected_revision)`：乐观并发保存；revision 不匹配时稳定拒绝。
- `transact_player(character_id, operation)`：加载隔离副本，执行业务回调，验证完整聚合，
  一次提交并递增 revision。回调或验证失败不发布内存候选。后台磁盘失败不撤销已经确认的游戏事务，
  下一检查点会重试最新状态。正常退出通过 `save_player_durable` 等待写盘，失败不采用退出候选。

面板换装由 `AuthoritativePlayerPanelService` 先在自动存档服务的隔离副本上执行，再调用
`commit_player_state` 一次提交。人物、背包与战车快照只在提交成功后成组发布；背包 revision、
战车 loadout revision 或玩家聚合 revision 过期时不会产生部分修改。详细边界见
`docs/player_panels_architecture.md`。

文件替身先写临时文件，再暂存旧快照为备份并替换主文件；启动时若主文件缺失而备份存在，
会恢复备份。该流程用于让测试可运行和暴露仓储边界，不替代 SQLite 的事务日志。

## 5. Migration 策略

- 文件替身当前 schema 为 2，并有确定性的 `0 -> 1 -> 2` 文档迁移；第二步把整数技能等级升级为
  完整成长状态，并把旧角色的综合等级下限规范为 10。不支持的未来版本会拒绝启动。
- SQLite migration 使用递增的 `data/server/persistence/migrations/NNN_name.sql` 文件，并在
  `schema_migrations` 表记录已应用版本。
- 真实 SQLite 适配器必须在 `BEGIN IMMEDIATE` 内逐个应用缺失 migration，成功后提交；失败
  回滚并拒绝服务启动。生产部署迁移前还必须由 bootstrap 创建可恢复备份。

## 6. 真正 SQLite 驱动的后续接缝

接入获准的 Godot SQLite GDExtension 后，需要新增一个实现 `SqliteDriverPort` 的薄适配器和一
个 `PlayerStateRepository` 的 SQLite 实现。完成标志不是“能打开数据库”，而是：

1. 所有值使用参数绑定，不拼接客户端或领域字符串。
2. 启动设置 `foreign_keys=ON`、合理的 `busy_timeout`，并按部署策略启用 WAL。
3. 聚合保存、inventory revision、命令回执在同一 `BEGIN IMMEDIATE` 事务中提交。
4. 临时真实 `.sqlite3` 集成测试覆盖 migration、回滚、revision 冲突、关闭后重开和进程恢复。
5. 专用服务器导出包包含对应平台的驱动二进制；缺驱动时启动失败，不回退到文件替身。

## 7. 自动验证

```powershell
& 'C:\Users\tomato\Downloads\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . `
  --script res://tests/server/persistence/player_state_persistence_test.gd
```

测试在工作区创建唯一 `.tmp` 数据库快照并在结束时删除，覆盖：运行时 SQLite 能力声明、SQL
schema 表集合、schema 0 到 2 迁移、事务成功、回调回滚、过期 revision 拒绝，以及新仓储实
例重新打开后恢复背包、装备、战车和地图位置。

另一个端到端夹具验证权威服务器接线：2.99 秒时 revision 保持不变，满 3 秒后 revision 只
递增一次，并在新服务器实例中恢复 D04 位置、八向朝向、战车生命、储备能量和当前能量：

```powershell
& 'C:\Users\tomato\Downloads\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . `
  --script res://tests/server/persistence/authoritative_autosave_test.gd
```

目前未接入正式登录账号，`AuthoritativeServer.open_session()` 仍按连接顺序分配
`player.N` 并用它加载存档。默认路径为 `user://server/player_states.json`，可用
`--player-state-store=` 隔离测试。相同路径下重启后按相同顺序创建角色能恢复对应记录，
但这不是稳定的账号归属：不同玩家调换连接顺序可能接管不同记录，不能用于正式多人身份。
正式认证落地时必须使用鉴权服务返回的稳定 `character_id`，同时处理旧开发身份的迁移。

战斗地面掉落使用“地图实例 + 模块初始化时生成的128位随机命名空间 + 单调序号”作为稳定实例编号。
每份掉落从生成、快照、拾取预检到背包入账始终复用同一编号；模块重建或服务器重启时更换命名空间，
避免怪物编号、死亡代数和计数器复位后与旧背包实例冲突。编号生成不消耗玩法随机序列，旧存档不需迁移。
背包仍拒绝真正重复的实例；入账失败保留地面物品，入账成功再移除，同一物品的后续拾取返回不存在。
专项 `tests/server/combat/loot_pickup_authority_test.gd` 已纳入总门禁，覆盖旧编号、同帧连续拾取、
真实仓储重启、跨模块身份、满包重试和另一账号重复拾取。

地图休眠保存的怪物血量、矿量和地面掉落目前只在服务端进程内保留；不在玩家文件快照中，
也没有世界数据库重启恢复能力。详见[地图驻留](./map_residency_and_performance.md)。
