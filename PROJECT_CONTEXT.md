# starhome_remake 项目全局约定

## 素材版本

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
2. 唯一例外：顶部栏、底部控制栏/快捷栏、小地图边框和控制按钮可从 `starhome_lz_fr`（免费版）导入，边界以 `docs/free_hud_rendering.md` 第 1 节为准。小地图实际 JPG、弹窗内容和全部非 HUD 资源不在豁免内。
3. `starhome_jznp`（激战版）仍只用于格式研究和版本对比，不作为新增正式素材来源；免费版除上一条列出的 HUD 外也同样如此。
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

1. `scripts/main_hall.gd` 当前仍实际持有地图、交互、HUD 和联机会话接缝，不能描述为
   “只做编排”。本地移动状态已在 R2 抽出；目标是让入口最终只负责启动配置、依赖组装和
   `ClientApplication` 生命周期。
2. 本地玩家的目标、路径、当前路径段、方向、预测序号和表现位置只能由
   `LocalPlayerController` 写入；权威校正必须同时取消或重算旧路线，入口脚本和 presenter
   不得形成多个位置写入者。
3. 活动地图的定义、导航、场景层、NPC、相机边界和 HUD 地图状态由
   `ActiveWorldController` 原子替换。`map_joined` 不能只更新会话 ID 而让画面继续停在旧地图。
4. 裸 `Dictionary` 只允许停留在 JSON 和 RPC 信任边界；通过验证后立即转换为类型化定义、
   命令或 bundle。模块内部不得把自由形态字典当作长期 API。
5. HUD 对外只暴露 `show_movement_status`、`show_network_notice`、
   `show_npc_interaction`、`set_map` 等语义 API 与业务信号；调用方不得持有或改写
   `Label`、弹窗、玩家点等内部控件。
6. NPC 已拆为 `NpcBase` 领域对象与 `NpcWorldView` 场景表现；商店/任务节点子类只选择对应领域
   子类，不得自行保存商品、任务进度或经济状态。后续有状态交互继续调用权威 action service；
   客户端 NPC 巡逻仍只是环境表现。
7. `AuthoritativeServer` 暂时保留兼容 facade，依次抽出地图迁移、会话、模拟循环和命令路由；
   RPC 适配、进程入口和领域事务不能继续汇入同一个类。

架构重构严格按 `R0 → R8` 推进：冻结基线与提交门禁、组合回归测试、本地玩家单写入者、
活动地图原子切换、类型化数据入口、HUD 封装、服务端入口拆分、NPC 边界、资源缓存与场景化。
详细验收与每批边界见 `docs/development_roadmap.md` 和 `docs/code_review_2026-08-27.md`。

截至 2026-08-28，R0 的提交/LFS/函数文档门禁、R1 的客户端组合回归、R2 的
`LocalPlayerController` 单写入者和 R3 的 `ActiveWorldController` 原子地图切换已经完成；
D04 通过共享 `PlayerWorldAvatar` 投影为荣耀版新兵战车。服务端持久化已建立类型化聚合、仓储
接口、迁移 SQL 与开发文件实现，但生产 SQLite 适配器仍不得标记为完成。人物/背包/战车已
迁移为 `Player` 充血聚合，客户端 `CurrentPlayer` 与世界服装层共享同一
`CharacterEquipment`；怪物索敌、攻击、掉落及 AI 状态也已收回 `MonsterLifecycle`，禁止重新
引入平行的 `monster_runtime` 字典。

提交前必须同时检查 `git diff --cached --name-only` 与 `git diff --cached --numstat`；素材批量
导入、离线解析产物、运行时代码和架构重构不得混入同一提交。

这份文件是后续开发与素材检索的项目级上下文。若对话中的临时猜测与本文件冲突，以用户最新明确指令为准。
