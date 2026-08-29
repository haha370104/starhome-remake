class_name SkillLevelPanel
extends DraggableGameWindow

const BACKGROUND := preload("res://assets/ui/windows/skills/background.png")
const LEGACY_PANEL_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const TEXT_COLOR := Color("faf0c8")
const HEADER_Y := 15.0
const FIRST_ROW_Y := 40.0
const ROW_STEP := 25.0

var _rows: Array[Dictionary] = []


## 创建旧客户端技能等级窗口的固定像素布局。
## 设计：这是普通可拖动游戏窗口而非 Popup，不会在窗口外拦截地图移动和战斗输入。
func _ready() -> void:
	configure(Vector2(240, 375), BACKGROUND, Vector2(208, 19))
	_create_header("技能名称", Vector2(20, HEADER_Y), Vector2(72, 18))
	_create_header("技能等级", Vector2(95, HEADER_Y), Vector2(70, 18))
	_create_header("当前经验", Vector2(167, HEADER_Y), Vector2(66, 18))
	for index in SkillBook.ORDERED_SKILLS.size():
		_rows.append(_create_row(index))


## 应用权威人物快照中的技能视图。
## [param skills_value] 固定顺序的技能快照数组。
func apply_skills(skills_value: Variant) -> void:
	if not skills_value is Array:
		return
	var skills: Array = skills_value
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		if index >= skills.size() or not skills[index] is Dictionary:
			_set_row_visible(row, false)
			continue
		_set_row_visible(row, true)
		var skill: Dictionary = skills[index]
		(row["name"] as Label).text = String(skill.get("display_name", "未知"))
		var base_level := int(skill.get("base_level", 0))
		var bonus := int(skill.get("equipment_bonus", 0))
		(row["level"] as Label).text = "%d%s" % [
			base_level,
			" +%d" % bonus if bonus > 0 else "",
		]
		var maximum := bool(skill.get("maximum_level", false))
		var percentage := int(skill.get(
			"progress_percent",
			mini(99, floori(float(skill.get("progress_ratio", 0.0)) * 100.0)),
		))
		(row["experience"] as Label).text = "100%" if maximum else "%d%%" % percentage
		var current_exp := float(skill.get("experience", 0)) \
			+ float(skill.get("fractional_experience", 0.0))
		var threshold := int(skill.get("next_level_experience", 0))
		var tooltip := "已达到最高等级" if maximum else "当前经验：%.2f / %d" % [
			current_exp, threshold,
		]
		for label_key: String in ["name", "level", "experience"]:
			(row[label_key] as Label).tooltip_text = tooltip


## 创建一列标题文字。
## [param text] 标题内容。
## [param label_position] 原客户端局部坐标。
## [param label_size] 标题占用尺寸。
func _create_header(text: String, label_position: Vector2, label_size: Vector2) -> void:
	var label := _create_label(label_position, label_size)
	label.text = text
	label.add_theme_color_override("font_color", Color("f5e7ad"))


## 创建一条技能行的三列标签。
## [param index] 技能稳定顺序索引。
## 返回名称、等级和经验标签的映射。
func _create_row(index: int) -> Dictionary:
	var y := FIRST_ROW_Y + float(index) * ROW_STEP
	return {
		"name": _create_label(Vector2(20, y), Vector2(72, 18)),
		"level": _create_label(Vector2(95, y), Vector2(70, 18)),
		"experience": _create_label(Vector2(167, y), Vector2(66, 18)),
	}


## 创建统一的技能窗口文字标签。
## [param label_position] 标签左上角局部坐标。
## [param label_size] 标签像素尺寸。
## 返回已加入内容层的 Label。
func _create_label(label_position: Vector2, label_size: Vector2) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_override("font", LEGACY_PANEL_FONT)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	content_root.add_child(label)
	return label


## 统一切换一条技能行的可见性。
## [param row] 三列标签映射。
## [param visible_value] 是否显示。
func _set_row_visible(row: Dictionary, visible_value: bool) -> void:
	for label_key: String in ["name", "level", "experience"]:
		(row[label_key] as Label).visible = visible_value
