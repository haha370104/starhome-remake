class_name CrystalSourceCore
extends GameItem

var cracks := 0
var profile: CrystalSourceRules.Core


## 初始化已由目录验证的专属核心；与普通晶石裂纹分别保存。
## [param definition] 核心定义。[param state] 实例事实。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	cracks = int(state.get("crystal_source_cracks", 0))


## 限制同色同级同裂纹同绑定的核心合并，禁止堆叠洗裂纹。
## [param other] 候选物品。
## 返回是否兼容。
func can_stack_with(other: GameItem) -> bool:
	return other is CrystalSourceCore and cracks == other.cracks and super(other)


## 拆分保留裂纹、类型和规则，不改变来源堆叠。
## [param new_id] 服务端新身份。[param amount] 拆出数量。
## 返回独立核心物品。
func copy_stack(new_id: String, amount: int) -> GameItem:
	var result := CrystalSourceCore.new(_definition, {"instance_id": new_id, "quantity": amount,
		"bound": bound, "locked": locked, "container_id": container_id, "crystal_source_cracks": cracks,
		"position_px": [position_px.x, position_px.y], "footprint_px": [footprint_px.x, footprint_px.y]})
	result.profile = profile
	return result


## 为快照和提示框导出完整裂纹与专属用途。
## 返回只读物品视图。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["crystal_source_cracks"] = cracks
	view["crystal_source_core"] = true
	view["description"] = description + "\n裂纹：%d / 3" % cracks
	if profile != null:
		view.description += "\n%s +%d" % [{"energy_cannon_attack": "能量炮攻击", "max_health": "战车生命", "missile_attack": "导弹攻击"}[profile.attribute], profile.bonus]
	return view
