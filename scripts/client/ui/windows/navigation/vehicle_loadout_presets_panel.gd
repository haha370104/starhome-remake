class_name VehicleLoadoutPresetsPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)
var choices: Array[Button] = []
var title_edit: LineEdit
var details: RichTextLabel
var status: Label
var capture_button: Button
var apply_button: Button
var confirmation: ConfirmationDialog
var _presets := VehicleLoadoutPresets.new()
var _player: Player
var _selected := 0
var _pending_capture: Dictionary = {}
var _remaining := 0.0
var _received_at := 0
var _awaiting := false
var _query_elapsed := 0.0


## 组合四套方案、完整槽位清单、覆盖确认与冷却提示。
func _ready() -> void:
	build_modern_window(Vector2(840, 580), "战车装备方案")
	make_label("保存当前装配，之后一键切换整套设备。每次成功切换间隔30秒。", Rect2(24, 54, 792, 28))
	for index in VehicleLoadoutPresets.COUNT:
		var button := make_button("方案%d · 未保存" % (index + 1), Rect2(24 + index * 200, 96, 192, 36), _select.bind(index))
		_style_button(button)
		button.toggle_mode = true
		choices.append(button)
	choices[0].set_pressed_no_signal(true)
	make_label("方案名称", Rect2(24, 158, 100, 28))
	title_edit = LineEdit.new()
	title_edit.position = Vector2(126, 154)
	title_edit.size = Vector2(464, 36)
	title_edit.max_length = 24
	title_edit.text = "方案1"
	content_root.add_child(title_edit)
	capture_button = make_button("将当前装备存为此方案", Rect2(610, 154, 206, 36), _capture)
	_style_button(capture_button)
	details = RichTextLabel.new()
	details.position = Vector2(24, 218)
	details.size = Vector2(792, 254)
	details.text = "此方案尚未保存。装配好战车后，点击上方按钮保存。"
	details.selection_enabled = true
	content_root.add_child(details)
	status = make_label("正在读取装备方案", Rect2(24, 477, 792, 28))
	status.clip_text = true
	var help := make_label("方案未记录的装备会卸回背包；装备必须仍在背包或战车上。\n野外不能换底盘；锁定、背包容量与武器冷却照常生效。", Rect2(24, 520, 580, 42))
	help.add_theme_font_size_override("font_size", 14)
	apply_button = make_button("应用此方案", Rect2(630, 520, 186, 38), _apply)
	_style_button(apply_button)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "覆盖装备方案"
	confirmation.ok_button_text = "覆盖保存"
	confirmation.cancel_button_text = "保留原方案"
	confirmation.confirmed.connect(_confirm_capture)
	confirmation.canceled.connect(func() -> void: _pending_capture.clear())
	add_child(confirmation)
	visibility_changed.connect(func() -> void:
		if not visible:
			confirmation.hide()
			_pending_capture.clear()
	)
	_refresh_actions()


## 打开窗口后读取同一权威投影，不从本地偏好推测方案或冷却。
func open_board() -> void:
	show()
	_query_elapsed = 0
	command_requested.emit({"type": "query"})


## 同步实际方案和玩家投影；频繁资源刷新不会覆盖用户正在输入的新名称。
## [param bundle] 权威同事务消息。[param player] 已更新的唯一玩家投影。
func apply_bundle(bundle: Dictionary, player: Player) -> void:
	if not bundle.get("vehicle_presets") is Dictionary: return
	var parsed := VehicleLoadoutPresets.restore(bundle.vehicle_presets)
	if not parsed.is_ok: return
	var first := _player == null
	_player = player
	_presets = parsed.value
	_remaining = maxf(0.0, float(_presets.ready_at) - float(bundle.get("preset_server_time", Time.get_unix_time_from_system())))
	_received_at = Time.get_ticks_msec()
	_awaiting = false
	for index in choices.size():
		choices[index].text = "方案%d · %s" % [index + 1, "未保存" if _presets.at(index).is_empty() else "已保存"]
	_show_selection(first)


## 用本地经过时间平滑显示服务端冷却，只读轮询恢复失败请求后的操作状态。
## [param delta] 当前渲染帧时长。
func _process(delta: float) -> void:
	if not visible: return
	_query_elapsed += delta
	if _query_elapsed >= 2.0:
		_query_elapsed = 0
		command_requested.emit({"type": "query"})
	_refresh_actions()


## 选择用户明确点击的方案，不自动寻找其他可用装备或替换缺失物品。
## [param index] 被点击的四套方案序号。
func _select(index: int) -> void:
	_selected = index
	for choice in choices.size(): choices[choice].set_pressed_no_signal(choice == index)
	_show_selection(true)


## 展示槽位和物品可用性；文本只作提示，最终兼容与库存校验仍由服务器执行。
## [param replace_title] 首次载入或用户切换方案时允许填入保存的标题。
func _show_selection(replace_title: bool) -> void:
	var preset := _presets.at(_selected)
	if replace_title: title_edit.text = String(preset.get("name", "方案%d" % (_selected + 1)))
	var lines := PackedStringArray()
	for row: Dictionary in preset.get("slots", []):
		var item: GameItem = _player.inventory.find(String(row.instance_id)) if _player != null else null
		if item == null and _player != null:
			for equipment: VehicleEquipment in _player.vehicle.loadout.items():
				if equipment.instance_id == String(row.instance_id): item = equipment
		var availability := "不在背包或战车中" if item == null else ("已锁定" if item.locked else "可用")
		lines.append("%s：%s    ·    %s" % [EquipmentSlotRegistry.display_name(int(row.location)), row.display_name, availability])
	details.text = "\n\n".join(lines) if not lines.is_empty() else "此方案尚未保存。装配好战车后，点击上方按钮保存。"
	_refresh_actions()


## 根据权威冷却和请求状态更新操作提示，不以按钮状态替代服务端校验。
func _refresh_actions() -> void:
	if apply_button == null: return
	var seconds := maxi(0, ceili(_remaining - float(Time.get_ticks_msec() - _received_at) / 1000.0))
	status.text = "正在读取装备方案" if _player == null else ("等待服务器处理" if _awaiting else ("切换冷却：%d秒" % seconds if seconds > 0 else "切换就绪"))
	capture_button.disabled = _player == null or _awaiting
	apply_button.disabled = _player == null or _presets.at(_selected).is_empty() or seconds > 0 or _awaiting


## 捕获当前查看版本的保存意图，覆盖已有方案时先显示明确确认。
func _capture() -> void:
	if _player == null or _awaiting: return
	var title := title_edit.text.strip_edges()
	if title.is_empty():
		notice_requested.emit("请填写方案名称")
		return
	_pending_capture = _command("capture_vehicle_preset")
	_pending_capture.title = title
	if _presets.at(_selected).is_empty():
		_confirm_capture()
		return
	confirmation.dialog_text = "用当前实际战车装备覆盖「%s」？\n只更新方案记录，不移动装备。" % String(_presets.at(_selected).name)
	confirmation.popup_centered(Vector2i(540, 180))


## 提交已经由用户确认的那套方案与版本，不能随之后的选择变化。
func _confirm_capture() -> void:
	if _pending_capture.is_empty(): return
	var command := _pending_capture.duplicate(true)
	_pending_capture.clear()
	command.confirmed = true
	_send(command)


## 发送一次整套换装请求，客户端不逐件移动装备。
func _apply() -> void:
	if _player != null and not apply_button.disabled: _send(_command("apply_vehicle_preset"))


## 以当前同事务版本创建最小操作意图。
## [param kind] 捕获或应用方案操作。
## 返回具体方案与三个资源版本。
func _command(kind: String) -> Dictionary:
	return {"type": kind, "index": _selected, "preset_revision": _presets.revision,
		"inventory_revision": _player.inventory.revision, "loadout_revision": _player.vehicle.loadout.revision}


## 在同步或异步回包前锁住本面板重复提交，失败通过下一次查询恢复。
## [param command] 经过用户选择的完整意图。
func _send(command: Dictionary) -> void:
	_awaiting = true
	_query_elapsed = 0
	_refresh_actions()
	command_requested.emit(command)
