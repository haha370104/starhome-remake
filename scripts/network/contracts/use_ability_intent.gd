class_name UseAbilityIntent
extends RefCounted

const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_instance_id",
	&"ability_id",
	&"target_entity_id",
	&"input_sequence",
]

var map_instance_id: String
var ability_id: String
var target_entity_id: String
var input_sequence: int


## 创建一个只表达技能选择与目标实体的客户端意图。
## [param requested_map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_ability_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_target_entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：攻击力、射程、能耗、命中与伤害均不进入客户端意图，由服务端状态推导。
func _init(
	requested_map_instance_id: String,
	requested_ability_id: String,
	requested_target_entity_id: String,
	requested_input_sequence: int,
) -> void:
	map_instance_id = requested_map_instance_id
	ability_id = requested_ability_id
	target_entity_id = requested_target_entity_id
	input_sequence = requested_input_sequence


## 使用网络信任边界的同一规则验证当前实例。
func validate():
	var result = from_dictionary(to_dictionary())
	return Result.ok(self) if result.is_ok else result


## 将技能意图序列化为严格的四字段字典。
## 返回该函数计算、查询或操作得到的结果。
func to_dictionary() -> Dictionary:
	return {
		"map_instance_id": map_instance_id,
		"ability_id": ability_id,
		"target_entity_id": target_entity_id,
		"input_sequence": input_sequence,
	}


## 执行 `from_dictionary` 对应的模块操作。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：精确字段白名单会拒绝客户端夹带伤害、坐标、射程、能耗或冷却。
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "use ability intent")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(
		source, ALLOWED_FIELDS, "use ability intent"
	)
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_instance_id")
	if not map_result.is_ok:
		return map_result
	var ability_result = Validation.require_identifier(source, &"ability_id")
	if not ability_result.is_ok:
		return ability_result
	var target_result = Validation.require_identifier(source, &"target_entity_id")
	if not target_result.is_ok:
		return target_result
	var sequence_result = Validation.require_integer(
		source, &"input_sequence", Protocol.MIN_SEQUENCE, Protocol.MAX_SEQUENCE
	)
	if not sequence_result.is_ok:
		return sequence_result
	return Result.ok(load("res://scripts/network/contracts/use_ability_intent.gd").new(
		map_result.value,
		ability_result.value,
		target_result.value,
		sequence_result.value,
	))
