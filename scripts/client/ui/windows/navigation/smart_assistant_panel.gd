class_name SmartAssistantPanel
extends ModernNavigationWindow

signal settings_changed(values: Dictionary)
signal journal_requested
signal presets_requested
var toggles: Dictionary[String, CheckButton] = {}
var threshold: HSlider
var threshold_label: Label
var status: Label
var energy_choice: OptionButton
var food_choice: OptionButton
var energy_threshold: HSlider
var physical_threshold: HSlider
var _energy_label: Label
var _physical_label: Label
var _energy_id := ""
var _food_id := ""
var _inventory: Inventory


## 创建使用共享字体和窗口壳的智脑设置；所有自动功能默认关闭。
func _ready() -> void:
	build_modern_window(Vector2(680, 658), "智脑系统")
	var labels := {"enabled": "启用智脑", "gun_missile_mode": "炮导模式：每0.5秒切换能量炮 / 导弹",
		"auto_attack": "站定时自动攻击当前武器射程内的怪物",
		"auto_pickup": "自动拾取身边掉落物", "auto_repair": "低生命时自助维修",
		"auto_energy": "自动使用指定能量包", "auto_food": "自动使用指定食品 / 修复器"}
	var index := 0
	for key: String in labels:
		var toggle := CheckButton.new()
		toggle.text = labels[key]
		if key == "gun_missile_mode":
			toggle.tooltip_text = "需装备能量炮和任意已启用导弹。连续点击可轮流开火；各自冷却及导弹锁定仍生效。"
		toggle.position = Vector2(24, 52 + index * 36)
		toggle.size = Vector2(632, 32)
		toggle.toggled.connect(func(_value: bool) -> void: _changed())
		content_root.add_child(toggle)
		toggles[key] = toggle
		index += 1
	threshold_label = make_label("自维修 / 即时回血阈值：50%", Rect2(24, 316, 338, 28))
	threshold = _slider(Vector2(398, 323), 50)
	make_label("能量包", Rect2(24, 359, 110, 28))
	energy_choice = _choice(Vector2(138, 356), true)
	_energy_label = make_label("储备能量阈值：30%", Rect2(24, 398, 330, 28))
	energy_threshold = _slider(Vector2(398, 405), 30)
	make_label("食品 / 修复器", Rect2(24, 445, 130, 28))
	food_choice = _choice(Vector2(168, 442), false)
	_physical_label = make_label("体力阈值：50%", Rect2(24, 484, 330, 28))
	physical_threshold = _slider(Vector2(398, 491), 50)
	status = make_label("未启用", Rect2(24, 530, 632, 28))
	status.clip_text = true
	var help := make_label("食品效果到期也会补给；同类冷却、锁定及能量包批量规则照常生效。\n设置自动保存；死亡、切图或重登后需手动启用。", Rect2(24, 568, 632, 42))
	help.add_theme_font_size_override("font_size", 14)
	make_button("PVE 击毁记录", Rect2(476, 614, 180, 32), journal_requested.emit)
	make_button("战车装备方案", Rect2(272, 614, 180, 32), presets_requested.emit)


## 创建10%到90%的资源阈值输入。
## [param at] 位置。[param initial] 默认百分比。
## 返回已连接设置回调的滑块。
func _slider(at: Vector2, initial: int) -> HSlider:
	var slider := HSlider.new()
	slider.position = at
	slider.size = Vector2(258, 24)
	slider.min_value = 10
	slider.max_value = 90
	slider.step = 10
	slider.value = initial
	slider.value_changed.connect(func(_value: float) -> void: _changed())
	content_root.add_child(slider)
	return slider


## 创建按定义身份选择的补给清单，未选择时不会自动代选。
## [param at] 位置。[param energy_pack] 是否为能量包清单。
## 返回可读且有溢出省略的下拉框。
func _choice(at: Vector2, energy_pack: bool) -> OptionButton:
	var choice := OptionButton.new()
	choice.position = at
	choice.size = Vector2(656 - at.x, 32)
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	choice.fit_to_longest_item = false
	choice.item_selected.connect(func(index: int) -> void:
		if energy_pack: _energy_id = String(choice.get_item_metadata(index))
		else: _food_id = String(choice.get_item_metadata(index))
		_changed()
	)
	content_root.add_child(choice)
	return choice


## 将保存的偏好投影到控件，避免初始化时反向写配置。
## [param values] 已规范化的用户偏好。
func apply_settings(values: Dictionary) -> void:
	for key: String in toggles:
		toggles[key].set_pressed_no_signal(bool(values.get(key, false)))
	threshold.set_value_no_signal(float(values.get("repair_threshold", 0.5)) * 100)
	energy_threshold.set_value_no_signal(float(values.get("energy_threshold", 0.3)) * 100)
	physical_threshold.set_value_no_signal(float(values.get("physical_threshold", 0.5)) * 100)
	_energy_id = String(values.get("energy_definition_id", ""))
	_food_id = String(values.get("food_definition_id", ""))
	_update_labels()
	if _inventory != null: apply_supplies(_inventory)


## 用最新背包刷新可用品，只更新显示，不触发设置保存或消耗。
## [param inventory] 同事务当前库存投影。
func apply_supplies(inventory: Inventory) -> void:
	_inventory = inventory
	_fill_choice(energy_choice, true, _energy_id)
	_fill_choice(food_choice, false, _food_id)


## 按物品类型去重清单，缺失的已选类型继续保留，避免耗尽后误用其他物品。
## [param choice] 目标清单。[param energy_pack] 类型过滤。[param selected] 已选定义身份。
func _fill_choice(choice: OptionButton, energy_pack: bool, selected: String) -> void:
	choice.clear()
	choice.add_item("未选择（不会自动使用）")
	choice.set_item_metadata(0, "")
	var found := selected.is_empty()
	var seen: Dictionary = {}
	for item: GameItem in _inventory.items():
		if not item is ConsumableItem or seen.has(item.definition_id): continue
		var consumable := item as ConsumableItem
		if (consumable.energy > 0) != energy_pack: continue
		seen[item.definition_id] = true
		var index := choice.item_count
		choice.add_item(item.display_name)
		choice.set_item_metadata(index, item.definition_id)
		if item.definition_id == selected:
			choice.select(index)
			found = true
	if not found:
		choice.add_item("已选类型暂不在背包中")
		choice.set_item_metadata(choice.item_count - 1, selected)
		choice.select(choice.item_count - 1)


## 显示控制器提供的运行状态，不向外暴露文字控件的写入细节。
## [param message] 当前运行或暂停原因。
func show_status(message: String) -> void:
	status.text = message
	status.tooltip_text = message


## 发布用户设置并同步阈值文字，物品类型的身份不依赖列表序号。
func _changed() -> void:
	if physical_threshold == null: return
	var values: Dictionary = {"repair_threshold": threshold.value / 100.0,
		"energy_threshold": energy_threshold.value / 100.0, "physical_threshold": physical_threshold.value / 100.0,
		"energy_definition_id": _energy_id, "food_definition_id": _food_id}
	for key: String in toggles: values[key] = toggles[key].button_pressed
	_update_labels()
	settings_changed.emit(values)


## 同步三个阈值标签，不在文字模板中保存规则数值。
func _update_labels() -> void:
	threshold_label.text = "自维修 / 即时回血阈值：%d%%" % int(threshold.value)
	_energy_label.text = "储备能量阈值：%d%%" % int(energy_threshold.value)
	_physical_label.text = "体力阈值：%d%%" % int(physical_threshold.value)
