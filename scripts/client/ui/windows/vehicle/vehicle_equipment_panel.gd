class_name VehicleEquipmentPanel
extends DraggableGameWindow

signal command_requested(command: Dictionary)

const BACKGROUND := preload("res://assets/ui/windows/vehicle/background.png")

const STAT_LABELS := {
	"max_health": "最大生命",
	"health": "当前生命",
	"defense": "防御",
	"armor_front": "前装甲",
	"armor_rear": "后装甲",
	"armor_left": "左装甲",
	"armor_right": "右装甲",
	"speed": "速度",
	"energy_cannon_attack": "能量炮攻击",
	"missile_attack": "导弹攻击",
	"rocket_attack": "火箭攻击",
	"propulsion": "推动力",
	"output_power": "输出功率",
	"weight": "总重量",
	"self_repair_base": "基础自修",
	"self_repair_bonus": "自修加成",
	"extra_repair": "额外维修",
	"reserve_energy": "储备能量",
	"working_energy": "工作能量",
}

var _preview_root: Control
var _slot_root: VBoxContainer
var _stats_label: Label
var _inventory_revision := -1
var _loadout_revision := -1


## 创建荣耀版战车装备面板、预览层与属性区。
func _ready() -> void:
	configure(Vector2(604, 460), BACKGROUND, Vector2(570, 40))
	_preview_root = Control.new()
	_preview_root.name = "VehiclePreview"
	_preview_root.position = Vector2(3, 47)
	_preview_root.size = Vector2(405, 391)
	_preview_root.clip_contents = true
	_preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_preview_root)

	_slot_root = VBoxContainer.new()
	_slot_root.name = "EquippedSlots"
	_slot_root.position = Vector2(12, 58)
	_slot_root.size = Vector2(128, 310)
	_slot_root.add_theme_constant_override("separation", 2)
	content_root.add_child(_slot_root)

	_stats_label = Label.new()
	_stats_label.position = Vector2(452, 57)
	_stats_label.size = Vector2(140, 390)
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_stats_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	content_root.add_child(_stats_label)


## 应用权威 VehicleAssemblySnapshot 并按 z_layer 重建合成预览。
## [param snapshot] 服务端返回的装备、revision 与统一战车统计。
func apply_snapshot(snapshot: Dictionary) -> void:
	_loadout_revision = int(snapshot.get("revision", -1))
	for child in _preview_root.get_children():
		child.queue_free()
	for child in _slot_root.get_children():
		child.queue_free()
	var equipped: Array = snapshot.get("equipped", [])
	equipped.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("z_layer", 0)) < int(right.get("z_layer", 0))
	)
	for raw_equipment: Variant in equipped:
		if not raw_equipment is Dictionary:
			continue
		_add_preview_layer(raw_equipment)
		_add_slot_button(raw_equipment)
	_stats_label.text = _format_stats(snapshot.get("stats", {}))


## 同步背包 revision，使卸装命令可进行双 revision 乐观锁校验。
## [param inventory_revision] 当前权威背包 revision。
func set_inventory_revision(inventory_revision: int) -> void:
	_inventory_revision = inventory_revision


## 在预览区增加一层装备 dialog 图。
## [param equipment] 带 dialog_texture、anchor、origin 和 z_layer 的装备快照。
func _add_preview_layer(equipment: Dictionary) -> void:
	var texture_path := String(equipment.get("dialog_texture", ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return
	var anchor_value: Array = equipment.get("dialog_anchor", [205, 245])
	var origin_value: Array = equipment.get("dialog_origin", [0, 0])
	var texture := load(texture_path) as Texture2D
	var layer := TextureRect.new()
	layer.name = "Layer_%s" % String(equipment.get("definition_id", "equipment"))
	layer.texture = texture
	layer.position = Vector2(
		float(anchor_value[0]) + float(origin_value[0]),
		float(anchor_value[1]) + float(origin_value[1]),
	)
	layer.size = texture.get_size()
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_root.add_child(layer)


## 为已装备实例创建可双击卸载的槽位按钮。
## [param equipment] 装备快照。
func _add_slot_button(equipment: Dictionary) -> void:
	var button := Button.new()
	button.text = "%s：%s" % [
		String(equipment.get("location_name", "槽位")),
		String(equipment.get("display_name", "装备")),
	]
	button.custom_minimum_size = Vector2(128, 23)
	button.tooltip_text = "双击卸载"
	button.gui_input.connect(_on_slot_gui_input.bind(int(equipment.get("location", -1))))
	_slot_root.add_child(button)


## 处理装备槽位双击并提交卸载意图。
## [param event] Godot GUI 输入事件。
## [param location] 对应战车 Location。
func _on_slot_gui_input(event: InputEvent, location: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.double_click:
		command_requested.emit({
			"type": "unequip_vehicle_item",
			"location": location,
			"inventory_revision": _inventory_revision,
			"loadout_revision": _loadout_revision,
		})


## 将战车统计字典格式化成右侧属性文本。
## [param stats] 服务端计算的统一战车统计。
## 返回逐行中文属性文本。
func _format_stats(stats: Dictionary) -> String:
	var lines := PackedStringArray()
	for stat_id: String in STAT_LABELS:
		if stat_id == "reserve_energy":
			lines.append("储备能量：%.0f / %.0f" % [
				float(stats.get("reserve_energy", 0.0)),
				float(stats.get("reserve_energy_capacity", 0.0)),
			])
		elif stat_id == "working_energy":
			lines.append("工作能量：%.0f / %.0f" % [
				float(stats.get("working_energy", 0.0)),
				float(stats.get("working_energy_capacity", 0.0)),
			])
		else:
			lines.append("%s：%s" % [STAT_LABELS[stat_id], str(stats.get(stat_id, 0))])
	return "\n".join(lines)
