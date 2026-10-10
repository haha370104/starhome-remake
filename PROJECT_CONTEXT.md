# starhome_remake 项目全局约定

## 文档入口与维护

- 客户端重构与后续开发遵循 [工程规范](./docs/engineering_standards.md)，按状态所有权拆分，禁止用大型上下文对象或入口转发层替代模块边界。

- 需要查阅项目历史背景时，从 [项目交接](./docs/project_handoff.md) 开始，再读
  [复刻对齐方案](./docs/remake_alignment_plan.md) 与 [原客户端阅读指南](./docs/original_client_reading_guide.md)。
- 整体 review 从 [docs/review_guide.md](./docs/review_guide.md) 开始；全部文档分类见
  [docs/README.md](./docs/README.md)。实际目录与目标架构分开描述，不以计划当完成证明。
- 修改状态所有权、协议、保存、资源加载或玩法边界时，按下文“文档维护”规则处理对应模块文档及 review 导航。
  逆向结论、复刻默认、未验证项分开标记；历史评审保留阶段和日期，不覆盖用户原始意见。
- 所有具名 GDScript 函数使用中文 `##` 注释：说明作用、`[param 参数名]`、非 void 返回值；
  抽象/权威/缓存等特殊设计额外写“设计：”。不能用重复函数名的模板文案代替契约说明。
- 新增测试区分“存在”“纳入总门禁”“本轮已通过”；不能拿旧报告宣称当前全绿。

## 素材版本

2026-09-17 用户确认“用免费版补吧，另外看看其他受击特效是不是也缺了”。本轮允许用免费版
原图补齐怪物命中特效，导入22段已核对 ALE，包含甲壳奥姆虫7帧爆炸；荣耀已有的可用效果保留。
逐项来源、哈希和映射证据见 `data/gameplay/glory/monster_hit_effects_v1.json` 及各素材目录的
`import_metadata.json`。此授权只覆盖怪物命中特效；服务端原始索引未证实的对应关系明确标为推断，
不按相似名称在运行时回退，不能把怪物身体动画当命中特效。范围与剩余9项见
[命中特效全量审计](docs/monster_hit_effect_audit.md)。

2026-09-17 用户批准人物装备前缀、特性与宝石系统，并要求新增强化材料自行绘制或采用免费素材。
本次采用内置 image_gen 原创像素印刻与宝石图，统一记录 `source_release: remake_generated`，
保存在 `assets/items/enhancement/`。六档前后缀各有独立生成图；固定属性宝石以属性图案和等级标记区分。
此授权仅覆盖本次新增强化材料，不替换现有原版素材；各业务目录 manifest 保存提示词、原图哈希及尺寸整理方式。

2026-09-17 用户确认使用已预览的免费版贪狼千级、千级帝王、圣诞及龙腾新兵战车素材补齐6款底盘，
包含对应背包、装备面板与世界表现；有跨版本差异的面板图仍按用户逐项选择。
用户另授权对所有历史缺失素材检索免费版及新激战版并比较；两版均存在且不同的素材必须提供对照供用户决定。
2026-09-17 用户进一步授权“有候选的全部接入”：全部188条候选均可使用；相同候选优先免费版，
仅激战版有的使用激战版，已有差异选择继续采用免费版。30组免费版重复路径内容完全相同，按服装源码选用pic2来源。
该授权覆盖本轮明确恢复清单，不自动替换已有荣耀素材。每项恢复记录真实发布版、原路径、哈希和用户选择，
运行时通过 `data/content/recovered_sprite_runtime_index_v1.json` 的显式映射加载，禁止按同名文件自动回退。

2026-09-15 用户授权接合器强化所需缺失素材少于3个时可参考现有素材补绘。本次仅加工石1项，
以 `remake_generated` 记录在 `assets/items/materials/processing_stone/manifest.json`，不冒充荣耀原图。

从 2026-08-26 起，除下述 HUD 唯一豁免外，所有新加入 `starhome_remake` 的素材统一以荣耀版为唯一正式来源：

- 版本名称：荣耀版
- 客户端映射名：`starhome_lz_ry`

迁移前的目录记录如下，路径不再作为当前资源依赖：

- 唯一原始资源根：`../starhome_lz_ry_full/`
- 唯一解析资源根：`../starhome_lz_ry_full_parsed/`
- 原始全量资源：`../starhome_lz_ry_full/raw/`
- ALE 精灵图：`../starhome_lz_ry_full_parsed/ale_sprites/`
- 官网惰性资源缓存：`../starhome_lz_ry_full_parsed/official_lazy_cache/`
- FTC/FCC 解包结果：`../starhome_lz_ry_full_parsed/ftc_resources/`
- UTF-8 装备、配方、NPC 数据：`../starhome_lz_ry_full_parsed/catalogs_utf8/`

当前目录边界：

- 工程外原始资源根：`../starhome_lz_ry_full/raw/`（本地归档，不属于主仓库）
- 清单外荣耀原件：`../starhome_lz_ry_full/unindexed_raw/`（与 `raw/` 分开归档，不属于主仓库）
- 开发及运行精灵：`assets/glory/sprites/`；其他运行素材也统一在 `assets/`
- 原档索引和常规审计需要的少量 FTC/CSV 证据：`data/source_evidence/glory/`
- `starhome_lz_ry_full_parsed/` 是可重建的离线处理缓存，不是长期资源源。

## 强制规则

1. 后续人物、NPC、怪物、场景、装备、物品、地图和非 HUD UI 素材都从荣耀版提取。
   素材检索先查工程外原档和 `assets/` 中已物化的资源，不把中间工作目录当作正式来源。
   `files_dir.dz` 不是官网资源全集；FCC 提供精确逻辑路径而本地未命中时，地图离线工具可向
   荣耀版官网同路径请求一次，通过文件头和实际解析校验后将原件归档到 `unindexed_raw/`。
2. UI 例外：顶部栏、底部控制栏/快捷栏、小地图边框和控制按钮可从 `starhome_lz_fr`（免费版）导入。2026-09-07 用户另指定免费版任务日志、商城和底栏系统菜单，并允许用户列表免费版回退；细节见 `docs/bottom_menu_windows.md`。边界以 `docs/free_hud_rendering.md` 第 1 节为准；小地图实际 JPG、未获准弹窗和全部非 UI 资源不在豁免内。
3. `starhome_jznp`（激战版）仍只用于格式研究和版本对比，不作为新增正式素材来源；免费版除上一条列出的窄范围 UI 外也同样如此。
4. 如果荣耀版清单、本地清单外原件和官网精确路径均不存在所需的非 HUD 素材，应先报告缺失和
   检索证据；没有用户明确许可，不得自动用其他版本替代。官网恢复禁止模糊文件名猜测和跨版本回退。
5. 每次按需导入应在对应 manifest 或提交说明中记录原始发布版与原始逻辑路径，避免只保留无法
   追溯的 PNG；官网惰性恢复还必须记录 URL、HTTP 状态、字节数、MD5、SHA-256 和解析结果。
   HUD 免费版素材必须明确写 `source_release: starhome_lz_fr`。
6. 工程内禁止沿用原客户端的素材名称和目录结构。`pic`、`pic2`、补丁批次、ALE 时间戳、哈希名和原窗口类名只能出现在 `source_*` 溯源字段中，不能成为运行时路径。导入时必须按 `业务类别 / 实体 / 变体 / 动作或状态` 重命名，例如 `monsters/om_adult/variants/toxic/attack/`、`ui/hud/top_menu/help/normal.png`。
7. 同一业务实体只保留一个正式目录；版本差异用 manifest 的来源信息表达，不得通过 `pic2`、`new`、`final` 一类目录继续叠补丁。
8. 本约定不自动追溯替换此前已经导入工程的素材版本；HUD 在相关功能再次开发时迁移到免费版目标，其余旧素材仍有计划地迁移到荣耀版，并统一遵守业务语义命名。
9. 每完成一个可独立验收的模块或模块子步骤就提交 Git，不积攒跨模块大提交。单次提交最多改动 20 个文件，文本新增行与删除行之和最多 2000 行；二进制文件计入文件数。超过任一上限时，必须按可独立测试、可安全回退的子步骤继续拆分，不得通过合并无关改动、跳过测试或排除应提交文件规避限制。
10. 开发运行资源统一物化在 `assets/`，由 `data/content/content_materialization_manifest_v1.json` 记录来源 ZIP、文件数和校验值；荣耀原始档案在项目上级目录 `../starhome_lz_ry_full/`，其他离线中间产物可位于临时工作区，不重新引入 `assets/` 子模块。
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
新增或修改当前有效文档链接时，可用 `python -X utf8 tools/check_documentation_links.py` 检查；历史来源链接缺失不触发批量修复，也不运行文档中的命令。

提交前必须同时检查 `git diff --cached --name-only` 与 `git diff --cached --numstat`；素材批量
导入、离线解析产物、运行时代码和架构重构不得混入同一提交。
正式入口还需通过 `tools/check_gdscript_warnings.gd` 的零警告门禁（已接入项目检查脚本）。
不得全局关闭警告；接口信号等确有跨子类用途的静态检查误报，须逐项说明局部例外。

这份文件是后续开发与素材检索的项目级上下文。若对话中的临时猜测与本文件冲突，以用户最新明确指令为准。

## 文档维护

- `docs/` 默认是按需查阅的历史证据库，不作为每次开发都要同步更新的项目说明书；不要为一次代码改动遍历或改写整个文档群。
- 日常只维护与实际行为有关的入口、工程约束和 `TODO.md`。模块文档仅在长期契约、素材来源或不可从代码与数据直接看出的事实发生实质变化时修改；保留作者原有表述，不添加重复的进度和测试流水账。
- 旧文档中的阶段状态、数量和通过记录须核对当前源码、清单与运行结果。过时内容不必逐篇追改；需要引用时注明其历史范围。

## 当前目录边界

- `starhome-remake/` 是 Godot 4.7.2 项目。运行时资源统一在项目根 `assets/`，代码使用 `res://assets/...`；本轮仅恢复资源根名称，不改变展开加载与私有素材的版本关联方式。`assets/` 被 Git 忽略，物化来源及校验见 `data/content/content_materialization_manifest_v1.json`。
- `starhome-recovery/` 存恢复索引、审计记录和跨版本缓存。荣耀版原档位于主项目上级目录的 `../starhome_lz_ry_full/raw/`，已取得的免费版和激战版原档分别位于 `../starhome_lz_fr_full/raw/`、`../starhome_jznp_full/raw/`；三者均位于工程外。荣耀下载索引和常规检查证据位于 `data/source_evidence/glory/`，地图恢复证据位于 `data/source_evidence/glory/map_recovery/`，解码精灵位于 `assets/glory/sprites/`。按需导入器从 raw 临时解码，不要求保留相邻的 `_parsed`、地图解析缓存或荣耀 FCC 来源树。
- 恢复工具以主仓库 `tools/recovery/` 的版本化实现为准；ALE/FCC 按需解码入口分别见 `tools/recovery/source_workspace.py`、`tools/recovery/fcc_workspace.py`。跨版本路径由 `tools/recovery/cross_release_paths.py` 管理，可用 `STARHOME_RECOVERY_ROOT` 或 `STARHOME_CROSS_RELEASE_ROOT` 覆盖。

## 素材与来源

- 正式素材以荣耀版为基线。免费版 HUD 和已经明确批准的跨版本补图有各自限定范围，见 `PROJECT_CONTEXT.md`、`data/import/recovered_asset_selections_v1.json` 和来源审计。先查荣耀版源与现有映射；不要按相似名称、模糊路径或视觉猜测替换素材。
- 跨版本恢复以 173 项 selection 为边界；现有 188 条运行时恢复引用包含先前 15 条。`remote_checks.json` 是审计证据，不是图像。按选定的精确路径和哈希核对原 ALE，无须为少量目标重建两个完整版本。
- 只对已确定的官方路径执行所需下载；不要探测官方更新源。保留原档、索引、解密结果、解析结果和来源哈希，不用空 ZIP、占位图或伪造资源掩盖缺口。导入产物使用业务命名，原版路径留在来源字段。
- 按“运行时引用 -> 素材来源 -> 现有生成器 -> `assets/` 输出”查缺口。优先修正 producer 和映射，再重新物化并验证；不要逐条手写大量 PNG/TRES。

## 恢复格式要点

- `files_dir.dz` 是 FTC1；经 `fkernel.dll` 的 `UnCode` 后直接得到资源索引文本。FTC! 常再包含 CAB。索引路径按 GBK 字节和前缀压缩规则解析，下载后按索引 MD5 校验。
- ALE/RLE0/AEX 使用 `tools/recovery/sprites/ale_sprite.py` 和批处理工具。AEX 三段 payload 的磁盘顺序为 `size3 -> size1 -> size2`；不要引入第二份 decoder。空帧容器可能是合法占位。
- 地图从 FCC、导航、图层、场景物件和专用小地图生成；`partial` 要按各层问题判断，不能等同整张地图失效。PKH 的 Linux 解包器在 `tools/recovery/maps/pkh_unpack.py`。
- Godot 初次运行前先做 editor 导入，建立脚本类缓存。地图成品使用 Godot 原生纹理导入；已有资源树可先运行 `python3 tools/build_glory_map_content_packs.py --prepare-import` 调整忽略范围，无需重建地图。`assets/glory/sprites/` 和调色板仍以 `.gdignore` 排除，通过现有素材仓储读取。

## 修改与验证

- 开始前看 `git status`、当前定义和生成脚本，保留已有工作区改动。`data/` 中的索引、清单与实际 `assets/` 文件要一起核对；历史完成数字不是当前验证结果。
- 测试仅在必要时增加最小有效覆盖, 不必要时不加测试。资源修复至少核对文件及来源哈希、Godot 实际纹理加载和主场景首个真实错误；区分静态审计、headless 运行与可见画面检查。
- 修改素材来源、状态所有权或运行边界时，按上述规则只更新受影响的有效文档。未证实的映射保留缺口，记录到 `TODO.md`。
