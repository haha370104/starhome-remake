extends SceneTree

var checks := 0
var failures := 0


## 覆盖五类记忆的提取快照、目录资格、非法成长和晶石裂纹绑定。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "目录初始化")
	var rules := catalog.memory_rules
	_check(rules.profiles.size() == 184, "原版装备范围")
	var seen := {}
	for profile: EquipmentMemoryRules.Profile in rules.profiles.values():
		for kind: int in profile.extract_types:
			var item: VehicleEquipment = catalog.create(profile.definition_id, {"instance_id": "source"}).value
			var payload := {}
			match kind:
				1:
					var processed := catalog.processing_rules.profile(item.definition_id)
					var attribute: String = processed.attributes.keys()[0]
					payload = {"processing": {"increments": {attribute: 1}}}
				3, 4:
					var levels := {}
					for channel: String in catalog.extra_attribute_rules.allowed(item.definition_id):
						if channel.begins_with("fluorite:" if kind == 3 else "brilliant:"): levels[channel] = 1
					payload = {"extra_attributes": {"levels": levels}}
				5: payload = {"strengthening": {"level": 1}}
				6:
					item.sockets.settle_open(0, true, "")
					item.sockets.inlay(0, catalog.create("bright_health_crystal", {"instance_id": "crystal", "bound": true, "crystal_cracks": 2}).value)
					payload = {"vehicle_sockets": item.sockets.to_dictionary()}
			payload["instance_id"] = "source"
			var recreated := catalog.create(profile.definition_id, payload)
			_check(recreated.is_ok, "来源实例有效")
			if not recreated.is_ok: continue
			var captured := EquipmentMemory.capture(recreated.value, kind)
			_check(captured.is_ok, "提取有成长的类型 " + str(kind))
			if not captured.is_ok: continue
			var semantic: String = {1: "processing", 3: "fluorite", 4: "brilliant", 5: "strengthening", 6: "sockets"}[kind]
			var module := catalog.create("equipment_memory_" + semantic, {"instance_id": "module", "equipment_memory": captured.value.to_dictionary()})
			_check(module.is_ok and module.value.memory.to_dictionary() == captured.value.to_dictionary(), "记忆目录恢复一致")
			_check(not catalog.create("low_grade_gel", {"equipment_memory": captured.value.to_dictionary()}).is_ok, "非模块不能藏成长")
			if kind == 6:
				_check(module.value.memory.sockets.slot_at(0).cracks == 2 and module.value.memory.sockets.slot_at(0).bound, "晶石裂纹绑定完整")
			seen[kind] = true
	_check(seen.size() == 5, "五类均被实际覆盖")
	for invalid: Variant in [[], {"version": 2}, {"version": 1, "source_definition_id": "recruit_tank", "module_type": 7}, {"version": 1, "source_definition_id": "recruit_tank", "module_type": 5, "payload": {"level": 0}}]:
		_check(not EquipmentMemory.restore(invalid).is_ok, "拒绝空载伪装或非法记录")
	var mixed := {"version": 1, "source_definition_id": "recruit_tank", "module_type": 3, "payload": {"levels": {"brilliant:3": 1}}}
	_check(not EquipmentMemory.restore(mixed).is_ok, "萤石模块不能装耀石")
	print("Equipment memory model: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## 累计独立行为断言。
## [param condition] 期望结果。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
