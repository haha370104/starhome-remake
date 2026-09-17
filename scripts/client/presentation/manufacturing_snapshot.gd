class_name ManufacturingSnapshot
extends RefCounted

class MaterialRow extends RefCounted:
	var title := ""
	var required := 0
	var owned := 0

class Recipe extends RefCounted:
	var id := ""
	var title := ""
	var level := 0
	var effective_level := 0
	var probability := 0.0
	var output := 1
	var experience := 0.0
	var quality := ""
	var available_batches := 0
	var materials: Array[MaterialRow] = []

	## 按服务端基础投影格式化选定次数和投入倍率，不结算或预测库存。
	## [param cycles] 界面中的总轮数。[param speed] 每轮投入倍率。
	## 返回含单轮、总计及基础经验的展示文本。
	func description(cycles: int, speed: int) -> String:
		var lines := PackedStringArray([title,
			"需求等级：%d（当前 %d）  成功率：%d%%" % [level, effective_level, roundi(probability * 100)],
			"每轮成功产量：%d　总计最多：%d" % [output * speed, output * speed * cycles],
			"每轮基础经验：%s（速度不增加经验）" % experience,
			quality, "", "材料                     持有 / 每轮 / 总计"])
		for material in materials:
			lines.append("%s　%d / %d / %d" % [material.title, material.owned, material.required * speed, material.required * speed * cycles])
		return "\n".join(lines)

var station_id := ""
var title := ""
var available := false
var inventory_revision := -1
var production := ProductionQueue.new()
var maximum_cycles := 1
var maximum_speed := 1
var cycle_milliseconds := 2000
var recipes: Array[Recipe] = []
var message := ""


## 在客户端协议边界一次解析生产、订单和同事务库存投影。
## [param bundle] 服务端玩家面板响应。
## 返回具名展示快照；缺少字段时按钮保持不可操作。
static func from_bundle(bundle: Dictionary) -> ManufacturingSnapshot:
	var snapshot := ManufacturingSnapshot.new()
	var payload: Dictionary = bundle.get("manufacturing", {})
	snapshot.station_id = String(payload.get("station_id", ""))
	snapshot.title = String(payload.get("display_name", "生产设施"))
	snapshot.available = bool(payload.get("available", false))
	snapshot.inventory_revision = int(bundle.get("inventory", {}).get("revision", -1))
	var restored := ProductionQueue.restore(payload.get("production", {}))
	if restored.is_ok: snapshot.production = restored.value
	else: snapshot.available = false
	var rules: Dictionary = payload.get("production_rules", {})
	snapshot.maximum_cycles = int(rules.get("maximum_cycles", 1))
	snapshot.maximum_speed = int(rules.get("maximum_speed", 1))
	snapshot.cycle_milliseconds = int(rules.get("cycle_milliseconds", 2000))
	var operation: Dictionary = payload.get("operation", {})
	snapshot.message = String(operation.get("message", ""))
	if operation.has("succeeded"):
		snapshot.message = "本轮生产成功" if bool(operation.succeeded) else "本轮制作失败，材料已消耗"
	for row: Dictionary in payload.get("recipes", []):
		var recipe := Recipe.new()
		recipe.id = String(row.get("recipe_id", ""))
		recipe.title = String(row.get("display_name", ""))
		recipe.level = int(row.get("required_skill_level", 0))
		recipe.effective_level = int(row.get("effective_skill_level", 0))
		recipe.probability = float(row.get("success_probability", 0))
		recipe.output = int(row.get("output_quantity", 1))
		recipe.experience = float(row.get("skill_experience", 0))
		recipe.quality = String(row.get("quality_description", ""))
		recipe.available_batches = int(row.get("available_batches", 0))
		for value: Dictionary in row.get("materials", []):
			var material := MaterialRow.new()
			material.title = String(value.get("display_name", "材料"))
			material.required = int(value.get("required", 0))
			material.owned = int(value.get("owned", 0))
			recipe.materials.append(material)
		snapshot.recipes.append(recipe)
	return snapshot


## 按稳定配方身份恢复选择，刷新后不会误选列表中其他位置。
## [param id] 选中的配方身份。
## 返回匹配行或空引用。
func recipe_by_id(id: String) -> Recipe:
	for recipe in recipes:
		if recipe.id == id: return recipe
	return null
