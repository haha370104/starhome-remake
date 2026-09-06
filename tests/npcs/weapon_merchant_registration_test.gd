extends SceneTree

const CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const ShopNpcModelScript := preload("res://scripts/domain/npcs/shop_npc.gd")

var failures := PackedStringArray()
var assertions := 0


## 验证两类武器商人只登记在荣耀版武器店地图。
func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	_expect(parsed is Dictionary, "大厅 NPC 配置应为字典")
	if not parsed is Dictionary:
		_finish()
		return
	var definition: Dictionary = {}
	var maps: Dictionary = parsed.get("maps", {})
	for raw_npc: Variant in maps.get("glory_nft_bl_weaponshop1", []):
		if raw_npc is Dictionary and String(raw_npc.get("id", "")) == "weapon_merchant":
			definition = raw_npc
			break
	_expect(not definition.is_empty(), "武器店应登记武器商人")
	_expect(not _contains_npc(parsed, "npcs", "weapon_merchant"), "基地大厅不应再生成武器商人")
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


## 判断指定 NPC 配置数组是否包含目标标识。
## [param parsed] 完整 NPC 配置。
## [param key] 要读取的顶层数组键。
## [param npc_id] 目标 NPC 标识。
## 返回是否找到该 NPC。
func _contains_npc(parsed: Dictionary, key: String, npc_id: String) -> bool:
	for value: Variant in parsed.get(key, []):
		if value is Dictionary and String(value.get("id", "")) == npc_id:
			return true
	return false


## 记录一条测试断言。
## [param condition] 条件是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试结果并结束进程。
func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_MERCHANT_REGISTRATION_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
