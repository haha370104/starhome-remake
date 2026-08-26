# starhome_remake 项目全局约定

## 素材版本

从 2026-08-26 起，所有新加入 `starhome_remake` 的素材统一以荣耀版为唯一正式来源：

- 版本名称：荣耀版
- 客户端映射名：`starhome_lz_ry`
- 唯一原始资源根：`../starhome_lz_ry_full/`
- 唯一解析资源根：`../starhome_lz_ry_full_parsed/`
- 原始全量资源：`../starhome_lz_ry_full/raw/`
- ALE 精灵图：`../starhome_lz_ry_full_parsed/ale_sprites/`
- FTC/FCC 解包结果：`../starhome_lz_ry_full_parsed/ftc_resources/`
- UTF-8 装备、配方、NPC 数据：`../starhome_lz_ry_full_parsed/catalogs_utf8/`

## 强制规则

1. 后续人物、NPC、怪物、场景、装备、物品、地图和 UI 素材都从荣耀版提取。
   素材检索只从上面的两个根目录开始，不把中间工作目录当作正式来源。
2. `starhome_lz_fr`（免费版）与 `starhome_jznp`（激战版）只用于格式研究和版本对比，不作为新增正式素材来源。
3. 如果荣耀版确实不存在所需素材，应先报告缺失和检索证据；没有用户明确许可，不得自动用其他版本替代。
4. 每次按需导入应在对应 manifest 或提交说明中记录荣耀版原始逻辑路径，避免只保留无法追溯的 PNG。
5. 工程内禁止沿用原客户端的素材名称和目录结构。`pic`、`pic2`、补丁批次、ALE 时间戳、哈希名和原窗口类名只能出现在 `source_*` 溯源字段中，不能成为运行时路径。导入时必须按 `业务类别 / 实体 / 变体 / 动作或状态` 重命名，例如 `monsters/om_adult/variants/toxic/attack/`、`ui/hud/top_menu/help/normal.png`。
6. 同一业务实体只保留一个正式目录；版本差异用 manifest 的来源信息表达，不得通过 `pic2`、`new`、`final` 一类目录继续叠补丁。
7. 本约定不自动追溯替换此前已经导入工程的素材版本；旧版本素材应在相关功能再次开发时有计划地迁移到荣耀版，但其工程内名称现在也必须遵守业务语义规范。

这份文件是后续开发与素材检索的项目级上下文。若对话中的临时猜测与本文件冲突，以用户最新明确指令为准。
