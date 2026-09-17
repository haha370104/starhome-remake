extends SceneTree

var checks := 0
var failures: Array[String] = []


## 遍历真实资格与材料通道，验证上限、原版失败档位和状态往返。
func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay/extra_attribute_rules_v1.json"))
	var parsed := ExtraAttributeRules.from_dictionary(data)
	_check(parsed.is_ok, "rules")
	var rules: ExtraAttributeRules = parsed.value
	for row: Dictionary in data.equipment:
		for id: String in row.channels:
			var channel: ExtraAttributeRules.Channel = rules.channels[id]
			var growth := ExtraAttributes.new()
			for index: int in channel.maximum:
				var result := growth.apply(row.definition_id, channel, rules, 0)
				_check(result.is_ok and result.value.success and growth.level(id) == index + 1, "accepted " + row.definition_id + id)
			_check(not growth.preview(row.definition_id, channel, rules).is_ok, "cap " + id)
			_check(is_equal_approx(growth.bonus(channel.attribute, rules), channel.maximum * channel.points), "exact cap value")
			var restored: ExtraAttributes = ExtraAttributes.restore(growth.to_dictionary()).value
			_check(restored.validate_for(row.definition_id, rules).is_ok and restored.level(id) == channel.maximum, "raw facts round trip")
	var channel := rules.material("extra_lifefluorite")
	var id := "recruit_tank"
	var early: ExtraAttributes = ExtraAttributes.restore({"levels": {channel.id: 9}}).value
	_check(early.apply(id, channel, rules, 0.999).value.actual_level == 10, "first ten guaranteed")
	_check(early.apply(id, channel, rules, 0.99).value.actual_level == 10, "mid failure preserves level")
	var late: ExtraAttributes = ExtraAttributes.restore({"levels": {channel.id: 20}}).value
	_check(late.apply(id, channel, rules, 0.99).value.actual_level == 19, "late failure loses one")
	_check(not late.validate_for("recruit_energy_cannon", rules).is_ok, "no transplant to cannon")
	_check(rules.allowed("recruit_energy_cannon").is_empty(), "original recruit cannon explicitly disabled")
	for raw: Variant in [{"levels": {"fluorite:3": -1}}, {"levels": {"fluorite:3": 0.1}}, {"levels": {"fluorite:3": 31}}, {"levels": {"fluorite:3": NAN}}, []]:
		_check(not ExtraAttributes.restore(raw).is_ok, "malformed state rejected")
	var forged: ExtraAttributes = ExtraAttributes.restore({"levels": {"foreign:1": 1}}).value
	_check(not forged.validate_for(id, rules).is_ok, "unknown channel rejected against catalog")
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay/extra_attribute_items_v1.json"))
	_check(items.definitions.size() == 12, "twelve original material types")
	for item: Dictionary in items.definitions:
		_check(rules.material(item.id) != null and ResourceLoader.exists(item.presentation.icon), "material identity and original image")
	print("Extra attribute model: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言结果。
## [param condition] 当前结果。
## [param label] 失败描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
