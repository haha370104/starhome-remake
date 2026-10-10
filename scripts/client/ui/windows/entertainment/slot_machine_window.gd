class_name SlotMachineWindow
extends ModernNavigationWindow

signal command_requested(command: Dictionary)
signal effect_requested(effect_id: String)

var _machine_id := ""
var _balance := 0
var _waiting := false
var _bet: SpinBox
var _balance_label: Label
var _result_label: Label
var _spin_button: Button
var _cells: Array[Label] = []
var _spin_tween: Tween


## 建立可下注的九格转轮，图案与奖金均以后续权威回包为准。
func _ready() -> void:
	build_modern_window(Vector2(590, 480), "娱乐大厅 · 幸运转轮")
	var machine := TextureRect.new()
	var machine_frame := AtlasTexture.new()
	machine_frame.atlas = preload("res://assets/world/entertainment/slot_machine/machine.png")
	machine_frame.region = WorldSlotMachine.VISIBLE_REGION
	machine.texture = machine_frame
	machine.position = Vector2(22, 67)
	machine.size = Vector2(190, 180)
	machine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	machine.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	machine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(machine)
	for row in 3:
		for column in 3:
			var panel := Panel.new()
			panel.position = Vector2(224 + column * 110, 72 + row * 72)
			panel.size = Vector2(100, 64)
			panel.add_theme_stylebox_override("panel", _surface_style("18303b", "687f82"))
			content_root.add_child(panel)
			var cell := make_label("?", Rect2(panel.position, panel.size))
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_theme_font_size_override("font_size", 23)
			cell.add_theme_color_override("font_color", Color("f0d88f"))
			_cells.append(cell)
	make_label("横、竖、斜三枚相同即中奖；彩7连线另加奖。", Rect2(26, 300, 540, 25))
	make_label("连线奖金：1+2+…+连线数；彩7同法额外计算。", Rect2(26, 328, 540, 25))
	_balance_label = make_label("金币：—", Rect2(26, 370, 205, 30))
	make_label("下注", Rect2(238, 370, 48, 30))
	_bet = SpinBox.new()
	_bet.position = Vector2(284, 365)
	_bet.size = Vector2(116, 36)
	_bet.min_value = SlotMachineRules.MIN_BET
	_bet.max_value = SlotMachineRules.MAX_BET
	_bet.step = 1
	_bet.value = 1
	content_root.add_child(_bet)
	_spin_button = make_button("拉杆", Rect2(422, 365, 142, 36), _spin)
	_style_button(_spin_button)
	_result_label = make_label("", Rect2(26, 417, 538, 42))
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_color_override("font_color", Color("f0d88f"))
	visibility_changed.connect(_on_visibility_changed)
	_update_controls()


## 打开指定地图机器并查询权威余额；重开保留上次下注额。
## [param machine_id] 被点选的机器标识。
func open_machine(machine_id: String) -> void:
	if _spin_tween != null:
		_spin_tween.kill()
	_machine_id = machine_id
	_waiting = true
	_result_label.text = ""
	show()
	move_to_front()
	_update_controls()
	command_requested.emit({"type": "query_slot_machine", "machine_id": machine_id})


## 只接受当前机器的权威结果，更新余额、九格图案和中奖明细。
## [param bundle] 面板会话验收后的服务端消息。
func apply_slot_bundle(bundle: Dictionary) -> void:
	var result: Variant = bundle.get("slot_machine")
	if not result is Dictionary or String(result.get("machine_id", "")) != _machine_id:
		return
	_waiting = false
	_balance = int(result.get("balance", 0))
	if result.get("symbols") is Array and (result.symbols as Array).size() == 9:
		effect_requested.emit("slot_spin")
		_waiting = true
		_spin_tween = create_tween()
		for _step in 10:
			_spin_tween.tween_callback(_shuffle_cells).set_delay(0.09)
		_spin_tween.tween_callback(_show_result.bind(result.duplicate(true)))
		_update_controls()
		return
	_update_controls()


## 在权威结算后揭示最终图案，不参与随机或金币计算。
## [param result] 已收到的服务端最终状态。
func _show_result(result: Dictionary) -> void:
	if _machine_id != String(result.get("machine_id", "")):
		return
	_waiting = false
	var payout := int(result.get("payout", 0))
	var bet := int(result.get("bet", 0))
	var symbols: Array = result.symbols
	for index in 9:
		var symbol := int(symbols[index])
		_cells[index].text = SlotMachineRules.SYMBOLS[symbol]
		_cells[index].add_theme_color_override("font_color", Color("ffda6f") if symbol == 0 else Color("e4edf4"))
	_result_label.text = "未中奖 · -%d 金币" % bet if payout == 0 else \
		"中奖 %d 线 / 彩7 %d 线 · 倍率 ×%d · +%d 金币" % [
			(result.get("winning_lines", []) as Array).size(), int(result.get("seven_lines", 0)),
			int(result.get("multiplier", 0)), payout - bet,
		]
	if payout > 0:
		effect_requested.emit("slot_win")
	_update_controls()


## 动画仅显示临时图案，结束后由服务端结果覆盖。
func _shuffle_cells() -> void:
	if not visible:
		return
	for cell: Label in _cells:
		cell.text = SlotMachineRules.SYMBOLS[randi_range(0, SlotMachineRules.SYMBOLS.size() - 1)]


## 按权威规则约束本地输入，再提交一次下注意图。
func _spin() -> void:
	if _waiting or _machine_id.is_empty():
		return
	_bet.apply()
	var bet := int(_bet.value)
	if bet > _balance:
		_result_label.text = "金币余额不足"
		return
	_waiting = true
	_result_label.text = "转轮转动中…"
	_update_controls()
	command_requested.emit({"type": "spin_slot_machine", "machine_id": _machine_id, "bet": bet})


## 背包金币变化时更新可下注状态。
## [param balance] 已提交到本地玩家投影的权威余额。
func set_balance(balance: int) -> void:
	_balance = balance
	_update_controls()


## 本窗口的权威命令被拒绝后恢复拉杆，并显示简短原因。
## [param code] 服务端错误码。[param message] 服务端可展示的说明。
func handle_rejection(code: StringName, message: String) -> void:
	if not visible or not _waiting or (not String(code).begins_with("slot_machine.") \
			and code != &"inventory.insufficient_currency"):
		return
	_waiting = false
	_result_label.text = message
	_update_controls()


## 避免关闭或切图后沿用旧机器的查询结果。
func _on_visibility_changed() -> void:
	if not visible:
		if _spin_tween != null:
			_spin_tween.kill()
		_machine_id = ""
		_waiting = false


## 同步余额文字和拉杆状态，避免重复提交。
func _update_controls() -> void:
	if _balance_label == null:
		return
	_balance_label.text = "金币：%d" % _balance
	_spin_button.disabled = _waiting or _balance < SlotMachineRules.MIN_BET
