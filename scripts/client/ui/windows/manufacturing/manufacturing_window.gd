class_name ManufacturingWindow
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var recipe_list: ItemList
var details: RichTextLabel
var cycles: SpinBox
var speed: SpinBox
var start_button: Button
var pause_button: Button
var cancel_button: Button
var progress: ProgressBar
var confirmation: ConfirmationDialog
var _facility: Label
var _order_label: Label
var _status: Label
var _station_id := "tailoring"
var _snapshot: ManufacturingSnapshot
var _recipe_id := ""
var _waiting := false
var _pending: Dictionary = {}
var _remaining := 0.0
var _poll_elapsed := 0.0


## 组合配方、投入预览和订单控制，客户端只展示进度、不发放生产结果。
func _ready() -> void:
	build_modern_window(Vector2(840, 650), "批量生产")
	_facility = make_label("正在读取设施…", Rect2(24, 58, 790, 26))
	recipe_list = ItemList.new()
	recipe_list.position = Vector2(24, 96)
	recipe_list.size = Vector2(294, 358)
	recipe_list.add_theme_stylebox_override("panel", _surface_style("0b1620", "304b5e"))
	recipe_list.add_theme_constant_override("v_separation", 9)
	recipe_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	recipe_list.item_selected.connect(_select_recipe)
	content_root.add_child(recipe_list)
	details = RichTextLabel.new()
	details.position = Vector2(338, 98)
	details.size = Vector2(478, 258)
	details.text = "选择配方查看材料与产量"
	content_root.add_child(details)
	make_label("运行次数", Rect2(338, 376, 100, 28))
	cycles = _number(Vector2(450, 372), 10000)
	make_label("生产速度", Rect2(596, 376, 100, 28))
	speed = _number(Vector2(700, 372), 10)
	make_label("速度提高每轮投入和产量；经验仍按一轮计算。", Rect2(338, 420, 478, 30)).add_theme_font_size_override("font_size", 14)
	_order_label = make_label("暂无生产订单", Rect2(24, 474, 792, 28))
	_order_label.clip_text = true
	progress = ProgressBar.new()
	progress.position = Vector2(24, 510)
	progress.size = Vector2(792, 22)
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", _surface_style("0b1620", "304b5e"))
	progress.add_theme_stylebox_override("fill", _surface_style("397f99", "63c5d6"))
	content_root.add_child(progress)
	_status = make_label("每轮结束时扣料；取消保留已完成成果。", Rect2(24, 542, 792, 26))
	_status.clip_text = true
	start_button = make_button("开始生产", Rect2(24, 594, 164, 34), _start)
	pause_button = make_button("暂停", Rect2(202, 594, 164, 34), _control)
	cancel_button = make_button("取消订单", Rect2(380, 594, 164, 34), _ask_cancel)
	for button: Button in [start_button, pause_button, cancel_button,
		make_button("刷新", Rect2(700, 594, 116, 34), _query)]: _style_button(button)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "取消生产订单"
	confirmation.ok_button_text = "取消剩余轮次"
	confirmation.cancel_button_text = "继续保留"
	confirmation.confirmed.connect(_confirm_cancel)
	confirmation.canceled.connect(func() -> void: _pending.clear())
	add_child(confirmation)
	visibility_changed.connect(_dismiss_confirmation)
	_update_actions()


## 创建带整数限制的投入输入框，手工键入值会在开始前正式提交到控件。
## [param at] 局部位置。[param maximum] 初始上限，后续以权威配置覆盖。
## 返回输入框。
func _number(at: Vector2, maximum: int) -> SpinBox:
	var input := SpinBox.new()
	input.position = at
	input.size = Vector2(116, 36)
	input.min_value = 1
	input.max_value = maximum
	input.step = 1
	input.value_changed.connect(func(_value: float) -> void: _show_recipe())
	content_root.add_child(input)
	return input


## 打开设施并拉取订单；已有别处订单时转为该订单的查看和取消入口。
## [param requested_station_id] 实际设施声明的类型。
func open_station(requested_station_id: String) -> void:
	_station_id = requested_station_id
	_snapshot = null
	_recipe_id = ""
	visible = true
	move_to_front()
	_query()


## 提交只读查询，运行时推送之外低频校正剩余时间和地点限制。
func _query() -> void:
	_waiting = true
	_update_actions()
	command_requested.emit({"type": "query_production", "station_id": _station_id})


## 将协议转换为具名展示快照，恢复配方选择并保留尚未提交的次数和速度。
## [param bundle] 同一事务的制造与背包响应。
func apply_manufacturing_bundle(bundle: Dictionary) -> void:
	_snapshot = ManufacturingSnapshot.from_bundle(bundle)
	_station_id = _snapshot.station_id
	_waiting = false
	_poll_elapsed = 0
	cycles.max_value = _snapshot.maximum_cycles
	speed.max_value = _snapshot.maximum_speed
	_facility.text = _snapshot.title + ("　· 每轮 %.1f 秒" % (_snapshot.cycle_milliseconds / 1000.0) if _snapshot.available else "　· 请返回原设施地图后继续")
	var order := _snapshot.production.order
	if order != null and _recipe_id.is_empty(): _recipe_id = order.recipe_id
	recipe_list.clear()
	for recipe in _snapshot.recipes:
		var index := recipe_list.add_item("%3d级　%s" % [recipe.level, recipe.title])
		recipe_list.set_item_tooltip(index, recipe.title)
		if recipe.id == _recipe_id: recipe_list.select(index)
	_remaining = float(order.remaining_milliseconds) if order != null else 0.0
	if order == null:
		_order_label.text = "暂无生产订单；材料在每轮结束时扣除。"
	else:
		var selected := _snapshot.recipe_by_id(order.recipe_id)
		_order_label.text = "%s　%d / %d轮　速度%d　%s" % [selected.title if selected != null else "生产", order.completed, order.cycles, order.speed, "已暂停" if order.paused else "进行中"]
	_status.text = order.pause_reason if order != null and order.paused else _snapshot.message
	if _status.text.is_empty(): _status.text = "关闭窗口不会停止生产；离开设施、断线或重登后暂停。"
	_status.tooltip_text = _status.text
	_show_recipe()
	_update_progress()


## 向设施交互测试与窗口管理器公开当前绑定设施。
## 返回稳定设施类型。
func station_id() -> String:
	return _station_id


## 保存选择的配方身份而非列表位置。
## [param index] 用户点选的可见行。
func _select_recipe(index: int) -> void:
	if _snapshot == null or index < 0 or index >= _snapshot.recipes.size(): return
	_recipe_id = _snapshot.recipes[index].id
	_show_recipe()


## 根据权威基础数值格式化当前输入的单轮与整单预览。
func _show_recipe() -> void:
	if _snapshot == null or speed == null: return
	var recipe := _snapshot.recipe_by_id(_recipe_id)
	details.text = recipe.description(int(cycles.value), int(speed.value)) if recipe != null else "选择配方查看材料与产量"
	_update_actions()


## 根据快照、操作等待和地点决定按钮状态；服务端仍完整校验。
func _update_actions() -> void:
	if start_button == null: return
	var order := _snapshot.production.order if _snapshot != null else null
	var recipe := _snapshot.recipe_by_id(_recipe_id) if _snapshot != null else null
	start_button.disabled = _waiting or _snapshot == null or not _snapshot.available or _snapshot.inventory_revision < 0 or order != null or recipe == null or recipe.available_batches < int(speed.value)
	pause_button.text = "继续生产" if order != null and order.paused else "暂停"
	pause_button.disabled = _waiting or order == null or (order.paused and not _snapshot.available)
	cancel_button.disabled = _waiting or order == null


## 发送开始订单意图；已完成的查询不代替服务端版本、材料和地点检查。
func _start() -> void:
	cycles.apply()
	speed.apply()
	_show_recipe()
	if start_button.disabled: return
	_submit({"type": "start_production", "station_id": _station_id, "recipe_id": _recipe_id,
		"cycles": int(cycles.value), "speed": int(speed.value), "inventory_revision": _snapshot.inventory_revision,
		"production_revision": _snapshot.production.revision})


## 对当前订单发送暂停或继续，不改变材料与已完成次数。
func _control() -> void:
	if pause_button.disabled: return
	_submit({"type": "resume_production" if _snapshot.production.order.paused else "pause_production",
		"production_revision": _snapshot.production.revision})


## 保存待取消订单的版本并明确未完成轮次的处理。
func _ask_cancel() -> void:
	if cancel_button.disabled: return
	var order := _snapshot.production.order
	_pending = {"type": "cancel_production", "production_revision": _snapshot.production.revision, "confirm_cancel": true}
	confirmation.dialog_text = "已完成%d / %d轮。\n取消剩余%d轮？未完成轮次尚未扣料，已完成的产物和经验保留。" % [order.completed, order.cycles, order.cycles - order.completed]
	confirmation.popup_centered(Vector2i(540, 170))


## 只提交一次已审阅的订单版本，期间新订单不能被旧确认取消。
func _confirm_cancel() -> void:
	if _pending.is_empty(): return
	var command := _pending.duplicate(true)
	_pending.clear()
	_submit(command)


## 发送意图并在失败无快照时追加只读恢复；不预测库存或订单成功。
## [param command] 已构造的语义命令。
func _submit(command: Dictionary) -> void:
	_waiting = true
	_update_actions()
	command_requested.emit(command)
	if _waiting: _query()


## 仅在可见时平滑显示服务器剩余时间，每三秒查询校正，不自行推进已完成次数。
## [param delta] 展示帧经过时间。
func _process(delta: float) -> void:
	if not visible or _snapshot == null: return
	_poll_elapsed += delta
	var order := _snapshot.production.order
	if order != null and not order.paused:
		_remaining = maxf(0, _remaining - delta * 1000)
		_update_progress()
	if _poll_elapsed >= 3:
		_poll_elapsed = 0
		_query()


## 更新当前一轮的进度条，归零等待权威消息，不显示预测产物。
func _update_progress() -> void:
	var order := _snapshot.production.order
	progress.value = 100.0 * (1.0 - _remaining / order.cycle_milliseconds) if order != null else 0.0
	progress.tooltip_text = "当前轮进度；完成情况以服务器入账为准"


## 关闭窗口时撤销尚未确认的取消意图，订单仍由服务器执行。
func _dismiss_confirmation() -> void:
	if not visible:
		_pending.clear()
		if confirmation != null: confirmation.hide()
