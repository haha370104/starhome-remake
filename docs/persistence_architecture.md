# 服务端权威状态持久化基座

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
4. `AuthoritativeAutosaveService` 每 3 秒从在线会话所属地图实例采集位置、朝向及战车资源，
   再通过仓储接口提交完整聚合；客户端只能发送意图，不能把生命、能量或坐标写进存档。

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
- 重连以 `character_id` 加载最后一次已提交聚合；未提交的内存修改不会进入恢复结果。
- 自动存档计时属于服务器应用层，默认间隔为 3 秒；断线宽限期结束和服务器退出前还会立即
  刷新一次。仓储不拥有计时器，也不会自行从表现节点读取状态。

## 3. 最小聚合模型

`PlayerStateRecord` 当前覆盖首个经济纵切所需的最小状态：

- 账户：稳定 ID、显示账户名、状态；认证密钥不进入该聚合。
- 角色：稳定 ID、显示名、聚合 revision、生命和经验。
- 背包：容量、独立 inventory revision、稳定 stack ID、定义 ID、数量和槽位。
- 装备：角色/战车 owner、业务槽位、实例 ID、定义 ID、耐久和强化等级。
- 战车：实例/定义 ID、战斗生命、储备能量、工作能量和输出功率。
- 位置：业务地图 ID、运行时地图实例、脚点、八向朝向和 checkpoint。

JSON 只存在于文件替身的信任边界。读取后立即转换为 `PlayerStateRecord`、
`InventoryStackRecord` 和 `EquipmentSlotRecord`；事务回调只接收隔离的类型化副本。

生产 SQL schema 将账户、角色、背包堆叠、装备槽、战车、位置和命令回执拆为独立表，并用
外键、唯一索引和 `CHECK` 约束保护最小结构不变量。`command_receipts` 为后续拾取、出售和制造
命令的幂等结果预留稳定落点。

## 4. 事务与恢复语义

仓储提供两种写入口：

- `save_player(state, expected_revision)`：乐观并发保存；revision 不匹配时稳定拒绝。
- `transact_player(character_id, operation)`：加载隔离副本，执行业务回调，验证完整聚合，
  一次提交并递增 revision。回调失败、验证失败或存储失败均不发布内存候选状态。

文件替身先写临时文件，再暂存旧快照为备份并替换主文件；启动时若主文件缺失而备份存在，
会恢复备份。该流程用于让测试可运行和暴露仓储边界，不替代 SQLite 的事务日志。

## 5. Migration 策略

- 文件替身当前 schema 为 1，并有确定性的 `0 -> 1` 文档迁移；不支持的未来版本会拒绝启动。
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
schema 表集合、schema 0 到 1 迁移、事务成功、回调回滚、过期 revision 拒绝，以及新仓储实
例重新打开后恢复背包、装备、战车和地图位置。

另一个端到端夹具验证权威服务器接线：2.99 秒时 revision 保持不变，满 3 秒后 revision 只
递增一次，并在新服务器实例中恢复 D04 位置、八向朝向、战车生命、储备能量和当前能量：

```powershell
& 'C:\Users\tomato\Downloads\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . `
  --script res://tests/server/persistence/authoritative_autosave_test.gd
```

目前未接入正式登录账号，临时会话仍以服务器分配的 `player.N` 作为角色标识；这只足以验证
单机和同一进程顺序重建。正式多人认证落地时，`open_session` 必须改为使用鉴权服务返回的稳定
`character_id`，自动存档与仓储接口无需随之改变。
