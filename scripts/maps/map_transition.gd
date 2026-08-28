class_name MapTransition
extends RefCounted

enum Kind {
	STANDARD,
	MULTI_CHOICE,
	CLIENT_POINT,
	CLIENT_LINE,
}

var transition_id: StringName
var kind: Kind = Kind.STANDARD
var enabled := true
var label := ""
var source_anchor := Vector2.ZERO
var approach_point := Vector2.ZERO
var destination_map_id: StringName
var destination_legacy_code := ""
var destination_entry_number := 0
var destination_landing_point := Vector2.ZERO
var has_destination_landing_point := false
var external_target := false
var presentation: Dictionary = {}
var source_audit: Dictionary = {}


## 执行 `destination_key` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func destination_key() -> String:
	if not destination_map_id.is_empty():
		return String(destination_map_id)
	return destination_legacy_code.to_lower()


## 执行 `kind_name` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func kind_name() -> String:
	match kind:
		Kind.MULTI_CHOICE:
			return "multi_choice"
		Kind.CLIENT_POINT:
			return "client_point"
		Kind.CLIENT_LINE:
			return "client_line"
		_:
			return "standard"
