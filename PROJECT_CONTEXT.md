# starhome_remake 项目全局约定

## 文档入口与维护

- 客户端重构与后续开发遵循 [工程规范](./docs/engineering_standards.md)，按状态所有权拆分，禁止用大型上下文对象或入口转发层替代模块边界。

- 新对话从 [项目交接](./docs/project_handoff.md) 开始，再读
  [复刻对齐方案](./docs/remake_alignment_plan.md) 与 [原客户端阅读指南](./docs/original_client_reading_guide.md)。
- 整体 review 从 [docs/review_guide.md](./docs/review_guide.md) 开始；全部文档分类见
  [docs/README.md](./docs/README.md)。实际目录与目标架构分开描述，不以计划当完成证明。
- 修改状态所有权、协议、保存、资源加载或玩法边界时，同步维护对应模块文档及 review 导航。
  逆向结论、复刻默认、未验证项分开标记；历史评审保留阶段和日期，不覆盖用户原始意见。
- 所有具名 GDScript 函数使用中文 `##` 注释：说明作用、`[param 参数名]`、非 void 返回值；
  抽象/权威/缓存等特殊设计额外写“设计：”。不能用重复函数名的模板文案代替契约说明。
- 新增测试区分“存在”“纳入总门禁”“本轮已通过”；不能拿旧报告宣称当前全绿。

## 素材版本

2026-09-15 用户授权接合器强化所需缺失素材少于3个时可参考现有素材补绘。本次仅加工石1项，
以 `remake_generated` 记录在 `assets/items/materials/processing_stone/manifest.json`，不冒充荣耀原图。

从 2026-08-26 起，除下述 HUD 唯一豁免外，所有新加入 `starhome_remake` 的素材统一以荣耀版为唯一正式来源：

- 版本名称：荣耀版
- 客户端映射名：`starhome_lz_ry`
- 唯一原始资源根：`../starhome_lz_ry_full/`
- 唯一解析资源根：`../starhome_lz_ry_full_parsed/`
- 原始全量资源：`../starhome_lz_ry_full/raw/`
- ALE 精灵图：`../starhome_lz_ry_full_parsed/ale_sprites/`
- 官网惰性资源缓存：`../starhome_lz_ry_full_parsed/official_lazy_cache/`
- FTC/FCC 解包结果：`../starhome_lz_ry_full_parsed/ftc_resources/`
- UTF-8 装备、配方、NPC 数据：`../starhome_lz_ry_full_parsed/catalogs_utf8/`

## 强制规则

1. 后续人物、NPC、怪物、场景、装备、物品、地图和非 HUD UI 素材都从荣耀版提取。
   素材检索只从上面的两个根目录及其 `official_lazy_cache` 开始，不把中间工作目录当作正式来源。
   `files_dir.dz` 不是官网资源全集；FCC 提供精确逻辑路径而本地未命中时，地图离线工具可向
   荣耀版官网同路径请求一次，通过文件头和实际解析校验后写入持久缓存。
2. UI 例外：顶部栏、底部控制栏/快捷栏、小地图边框和控制按钮可从 `starhome_lz_fr`（免费版）导入。2026-09-07 用户另指定免费版任务日志、商城和底栏系统菜单，并允许用户列表免费版回退；细节见 `docs/bottom_menu_windows.md`。边界以 `docs/free_hud_rendering.md` 第 1 节为准；小地图实际 JPG、未获准弹窗和全部非 UI 资源不在豁免内。
3. `starhome_jznp`（激战版）仍只用于格式研究和版本对比，不作为新增正式素材来源；免费版除上一条列出的窄范围 UI 外也同样如此。
4. 如果荣耀版清单、本地惰性缓存和官网精确路径均不存在所需的非 HUD 素材，应先报告缺失和
   检索证据；没有用户明确许可，不得自动用其他版本替代。官网恢复禁止模糊文件名猜测和跨版本回退。
5. 每次按需导入应在对应 manifest 或提交说明中记录原始发布版与原始逻辑路径，避免只保留无法
   追溯的 PNG；官网惰性恢复还必须记录 URL、HTTP 状态、字节数、MD5、SHA-256 和解析结果。
   HUD 免费版素材必须明确写 `source_release: starhome_lz_fr`。
6. 工程内禁止沿用原客户端的素材名称和目录结构。`pic`、`pic2`、补丁批次、ALE 时间戳、哈希名和原窗口类名只能出现在 `source_*` 溯源字段中，不能成为运行时路径。导入时必须按 `业务类别 / 实体 / 变体 / 动作或状态` 重命名，例如 `monsters/om_adult/variants/toxic/attack/`、`ui/hud/top_menu/help/normal.png`。
7. 同一业务实体只保留一个正式目录；版本差异用 manifest 的来源信息表达，不得通过 `pic2`、`new`、`final` 一类目录继续叠补丁。
8. 本约定不自动追溯替换此前已经导入工程的素材版本；HUD 在相关功能再次开发时迁移到免费版目标，其余旧素材仍有计划地迁移到荣耀版，并统一遵守业务语义命名。
9. 每完成一个可独立验收的模块或模块子步骤就提交 Git，不积攒跨模块大提交。单次提交最多改动 20 个文件，文本新增行与删除行之和最多 2000 行；二进制文件计入文件数。超过任一上限时，必须按可独立测试、可安全回退的子步骤继续拆分，不得通过合并无关改动、跳过测试或排除应提交文件规避限制。
10. 大型可再生成地图层按 `.gitattributes` 进入 Git LFS；小型角色、怪物、UI 精灵继续使用普通 Git。任何 `assets/` 下达到 5 MiB 的非 LFS 文件由 `tools/check_asset_size_policy.py` 拒绝，禁止通过全局 `*.png` 规则把所有小图推入 LFS。
11. 多人长期状态只由服务端仓储拥有。JSON 可作为只读定义或明确标注的开发快照，但不能冒充生产存档；领域/应用层只依赖 `PlayerStateRepository`，真实 SQLite 驱动通过端口接入，客户端和场景节点不得直接读写数据库。

## 代码评审后的架构约束

2026-08-27 代码评审确认：当前工程已有导航、网络契约、预测/插值、地图定义、HUD 组件和
权威地图实例等可用基础，但模块拆分尚未等同于状态所有权已经清晰。后续必须保留可运行大厅，
按下列边界渐进重构，不做一次性目录搬迁或整体重写：

1. `scripts/main_hall.gd` 已收敛为启动配置、依赖组装和生命周期入口。切图、战斗、世界交互、
   玩家投影分别由独立模块负责，禁止重新加入业务回调或测试兼容转发方法。
   实际结构与验证见 [客户端架构](./docs/client_architecture.md)。
2. 本地玩家的目标、路径、当前路径段、方向、预测序号和表现位置只能由
   `LocalPlayerController` 写入；权威校正必须同时取消或重算旧路线，入口脚本和 presenter
   不得形成多个位置写入者。
3. 活动地图的定义、导航、场景层、NPC、相机边界和 HUD 地图状态由
   `ActiveWorldController` 原子替换。`map_joined` 不能只更新会话 ID 而让画面继续停在旧地图。
4. 裸 `Dictionary` 只允许停留在 JSON 和 RPC 信任边界；通过验证后立即转换为类型化定义、
   命令或 bundle。模块内部不得把自由形态字典当作长期 API。
5. HUD 对外只暴露 `show_status`、`show_network_notice`、
   `show_npc_popup`、`set_map` 等语义 API 与业务信号；调用方不得持有或改写
   `Label`、弹窗、玩家点等内部控件。
6. NPC 已拆为 `NpcBase` 领域对象与 `NpcWorldView` 场景表现；商店/任务节点子类只选择对应领域
   子类，不得自行保存商品、任务进度或经济状态。后续有状态交互继续调用权威 action service；
   客户端 NPC 巡逻仍只是环境表现。
7. `AuthoritativeServer` 暂时保留兼容 facade，依次抽出地图迁移、会话、模拟循环和命令路由；
   RPC 适配、进程入口和领域事务不能继续汇入同一个类。
8. 地图按玩家驻留加载：启动只建轻量索引，玩家进入才建立导航/运行实例。最后一人离开、
   在途事务结清后停止空图模拟并释放导航，保留怪物生命、剩余矿量和掉落等领域状态。
   禁止为方便查询而恢复全图预加载；重连宽限期保留的玩家实体仍算驻留。
   具体边界和性能回归见 `docs/map_residency_and_performance.md`。
9. 两种模式运行时均只由 `AuthoritativeServer._physics_process` 推进模拟。
   进程内服务器先初始化再挂入传输节点，`_ready` 避免重复初始化；传输层不得再自动 tick。
   关闭时先断开引用、同步保存再 `queue_free()`，不得在信号回调中直接释放正在执行的对象。

架构重构严格按 `R0 → R8` 推进：冻结基线与提交门禁、组合回归测试、本地玩家单写入者、
活动地图原子切换、类型化数据入口、HUD 封装、服务端入口拆分、NPC 边界、资源缓存与场景化。
详细验收与每批边界见 `docs/development_roadmap.md` 和 `docs/code_review_2026-08-27.md`。

历史阶段记录（2026-08-28）：R0 的提交/LFS/函数文档门禁、R1 的客户端组合回归、R2 的
`LocalPlayerController` 单写入者和 R3 的 `ActiveWorldController` 原子地图切换已经完成；
D04 通过共享 `PlayerWorldAvatar` 投影为荣耀版新兵战车。服务端持久化已建立类型化聚合、仓储
接口、迁移 SQL 与开发文件实现，但生产 SQLite 适配器仍不得标记为完成。人物/背包/战车已
迁移为 `Player` 充血聚合，客户端 `CurrentPlayer` 与世界服装层共享同一
`CharacterEquipment`；怪物索敌、攻击、掉落及 AI 状态也已收回 `MonsterLifecycle`，禁止重新
引入平行的 `monster_runtime` 字典。

2026-09-14 当前能力、最近修复及仍有缺口统一维护在 `docs/project_handoff.md`；
商店、任务、制造已有权威服务，不能继续按早期计划描述为只有 UI。SQLite 和正式身份仍未完成。
文档链接与目录覆盖用 `python -X utf8 tools/check_documentation_links.py` 检查；不会运行文档中的命令。

提交前必须同时检查 `git diff --cached --name-only` 与 `git diff --cached --numstat`；素材批量
导入、离线解析产物、运行时代码和架构重构不得混入同一提交。
正式入口还需通过 `tools/check_gdscript_warnings.gd` 的零警告门禁（已接入项目检查脚本）。
不得全局关闭警告；接口信号等确有跨子类用途的静态检查误报，须逐项说明局部例外。

这份文件是后续开发与素材检索的项目级上下文。若对话中的临时猜测与本文件冲突，以用户最新明确指令为准。

## Git 仓库边界（2026-09-14）

代码、数据定义和工具归主仓库；所有运行素材及其导入设置归 `assets` 子模块。
素材 LFS 规则只在 `assets/.gitattributes` 维护；素材提交后须更新主仓库的 gitlink。
原版解包档案继续保存在本地仓库外。协作命令见[仓库组织](docs/repository_layout.md)。
