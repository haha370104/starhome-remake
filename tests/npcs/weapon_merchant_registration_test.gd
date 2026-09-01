extends SceneTree

const CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const ShopNpcModelScript := preload("res://scripts/domain/npcs/shop_npc.gd")

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	_expect(parsed is Dictionary, "大厅 NPC 配置应为字典")
	if not parsed is Dictionary:
		_finish()
		return
	var definition: Dictionary = {}
	for raw_npc: Variant in parsed.get("npcs", []):
		if raw_npc is Dictionary and String(raw_npc.get("id", "")) == "weapon_merchant":
			definition = raw_npc
			break
	_expect(not definition.is_empty(), "大厅应登记武器商人")
	var merchant = ShopNpcModelScript.new()
	var configured: DomainResult = merchant.configure(definition)
	_expect(configured.is_ok, "武器商人领域模型应可配置")
	if configured.is_ok:
		var interaction: Dictionary = merchant.interaction_data()
		var ids := PackedStringArray()
		for action: Dictionary in interaction.actions:
			ids.append(String(action.get("id", "")))
		_expect(ids == PackedStringArray(["buy", "sell", "task"]), "菜单应依次为买、卖、中级任务")
	_finish()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_MERCHANT_REGISTRATION_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
