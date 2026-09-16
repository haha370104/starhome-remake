class_name ItemDefinitionAliases
extends RefCounted

# 仅收录已由原版同类名、图像和用途确认的重复身份，不做任意同名物品合并。
const LEGACY_TO_CANONICAL := {
	"item:material:02ff69f031b5": "low_grade_gel",
	"item:material:fc4cebd5d85b": "low_grade_biosilicon",
	"item:material:b80499528adf": "low_grade_quadruped_shell",
	"item:material:e07b300afb44": "low_grade_energy_catalyst",
	"item:material:dc2a516b5a42": "low_grade_energy_pack",
}


## 将历史占位材料身份转换为已有正式物品身份，未知 ID 原样保留。
## [param definition_id] 存档、配方或目录中的物品定义标识。
## 返回可在掉落、任务、制造和背包之间通用的稳定身份。
static func canonical(definition_id: String) -> String:
	return String(LEGACY_TO_CANONICAL.get(definition_id, definition_id))
