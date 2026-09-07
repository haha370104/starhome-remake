class_name WeaponMerchantWindow
extends DraggableGameWindow

signal command_requested(command: Dictionary)

const REGULAR_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const BOLD_FONT := preload("res://assets/ui/fonts/legacy_panel_bold_font.tres")
const TextureResolverScript := preload(
	"res://scripts/client/presentation/items/item_presentation_texture_resolver.gd"
)

const WINDOW_SIZE := Vector2(530, 450)
const LEGACY_TEXT := Color("faf0c8")
const CYAN_TEXT := Color("70eaff")
const HOVER_COLOR := Color(1.0, 1.0, 0.0, 0.18)

var _mode := "buy"
var _merchant_id := "weapon_merchant"
var _commerce: Dictionary = {}
var _inventory_revision := -1
var _currency := 0
var _title_label: Label
var _column_header: Label
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _description_title: Label
var _description_body: Label
var _preview: TextureRect
var _currency_label: Label
var _task_root: Control
var _task_message: Label
var _task_progress: VBoxContainer
var _task_primary_button: Button
var _task_selector: OptionButton
var _selected_task_id := ""


## 创建原版 530×450 买卖窗；任务消息复用相同 MaxForm 外框。
func _ready() -> void:
	configure(WINDOW_SIZE, null, Vector2(502, 12))
	_build_chrome()
	_build_trade_view()
	_build_task_view()


## 打开指定武器商人的一个原版动作，并请求最新权威快照。
## [param mode] buy、sell 或普通武器商人才支持的 task。
## [param merchant_id] 当前 NPC 对应的权威商人标识。
func open_mode(mode: String, merchant_id := "weapon_merchant") -> void:
	_mode = mode if mode in ["buy", "sell", "task"] else "buy"
	_merchant_id = merchant_id
	_commerce = {}
	_selected_task_id = ""
	_inventory_revision = -1
	visible = true
	move_to_front()
	_render()
	command_requested.emit({"type": "query_weapon_merchant", "merchant_id": _merchant_id})


## 应用服务器随玩家面板一并返回的交易快照。
## [param bundle] 含 commerce 与 inventory 投影的权威面板数据。
func apply_commerce_bundle(bundle: Dictionary) -> void:
	var commerce_value: Variant = bundle.get("commerce", {})
	if not commerce_value is Dictionary:
		return
	var response_provider := String(commerce_value.get("merchant", {}).get("id", ""))
	if not response_provider.is_empty() and response_provider != _merchant_id:
		return
	_commerce = (commerce_value as Dictionary).duplicate(true)
	var inventory_value: Variant = bundle.get("inventory", {})
	if inventory_value is Dictionary:
		_inventory_revision = int((inventory_value as Dictionary).get("revision", -1))
		_currency = int((inventory_value as Dictionary).get("currency", 0))
	_render()


## 提供给自动化测试和窗口管理器的当前模式。
## 返回 buy、sell 或 task。
func current_mode() -> String:
	return _mode


## 创建免费版商店窗口的外框与标题区域。
func _build_chrome() -> void:
	var panel := Panel.new()
	panel.name = "LegacyMaxFormChrome"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(panel)

	_title_label = _label("Title", Vector2(34, 12), Vector2(462, 24), 16, BOLD_FONT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", CYAN_TEXT)


## 创建买卖模式共用的商品列表、说明和货币区域。
func _build_trade_view() -> void:
	_column_header = _label("ColumnHeader", Vector2(20, 56), Vector2(287, 20), 12, REGULAR_FONT)
	var list_frame := Panel.new()
	list_frame.name = "ItemListFrame"
	list_frame.position = Vector2(16, 84)
	list_frame.size = Vector2(295, 314)
	list_frame.add_theme_stylebox_override("panel", _inner_style())
	content_root.add_child(list_frame)
	_list_scroll = ScrollContainer.new()
	_list_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_frame.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list)

	var description_frame := Panel.new()
	description_frame.name = "DescriptionFrame"
	description_frame.position = Vector2(319, 84)
	description_frame.size = Vector2(195, 314)
	description_frame.add_theme_stylebox_override("panel", _inner_style())
	content_root.add_child(description_frame)
	_preview = TextureRect.new()
	_preview.position = Vector2(55, 14)
	_preview.size = Vector2(84, 88)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_frame.add_child(_preview)
	_description_title = _label_on(description_frame, "ItemTitle", Vector2(10, 108), Vector2(175, 24), 13, BOLD_FONT)
	_description_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description_body = _label_on(description_frame, "ItemDescription", Vector2(10, 136), Vector2(175, 164), 12, REGULAR_FONT)
	_description_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_currency_label = _label("Currency", Vector2(28, 416), Vector2(280, 18), 12, REGULAR_FONT)


## 创建循环任务的正文、进度与动作区域。
func _build_task_view() -> void:
	_task_root = Control.new()
	_task_root.name = "TaskMessage"
	_task_root.position = Vector2(38, 58)
	_task_root.size = Vector2(454, 352)
	content_root.add_child(_task_root)
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", _inner_style())
	_task_root.add_child(frame)
	_task_message = _label_on(frame, "Message", Vector2(22, 20), Vector2(410, 118), 13, REGULAR_FONT)
	_task_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_task_selector = OptionButton.new()
	_task_selector.position = Vector2(22, 12)
	_task_selector.size = Vector2(410, 28)
	_task_selector.add_theme_font_override("font", REGULAR_FONT)
	_task_selector.add_theme_font_size_override("font_size", 13)
	_task_selector.item_selected.connect(_select_task)
	frame.add_child(_task_selector)
	_task_progress = VBoxContainer.new()
	_task_progress.position = Vector2(22, 150)
	_task_progress.size = Vector2(410, 104)
	_task_progress.add_theme_constant_override("separation", 5)
	frame.add_child(_task_progress)
	_task_primary_button = _legacy_button("接受任务", Vector2(276, 292), Vector2(76, 28))
	_task_primary_button.pressed.connect(_request_task_action)
	frame.add_child(_task_primary_button)
	var cancel_button := _legacy_button("取消", Vector2(360, 292), Vector2(58, 28))
	cancel_button.pressed.connect(request_close)
	frame.add_child(cancel_button)


## 根据当前模式和最新权威快照刷新窗口内容。
func _render() -> void:
	if not is_node_ready():
		return
	var is_task := _mode == "task"
	_task_root.visible = is_task
	_column_header.visible = not is_task
	_list_scroll.get_parent().visible = not is_task
	_description_title.get_parent().visible = not is_task
	_currency_label.visible = not is_task
	if is_task:
		_render_task()
	else:
		_render_trade()


## 使用当前商人目录刷新买入或卖出商品列表。
func _render_trade() -> void:
	var merchant: Dictionary = _commerce.get("merchant", {})
	_title_label.text = String(merchant.get("display_name", "武器商人"))
	_column_header.text = "物品名称                 %s      数量" % ("售价" if _mode == "buy" else "收购")
	for child in _list.get_children():
		child.queue_free()
	_clear_description()
	var source: Array = _commerce.get("offers", []) if _mode == "buy" \
		else _commerce.get("sell_items", [])
	for value: Variant in source:
		if value is Dictionary:
			_list.add_child(_trade_row(value as Dictionary))
	_currency_label.text = "金币：%d" % _currency


## 创建一行可悬浮和点击的交易商品。
## [param entry] 服务端下发的安全商品投影。
## 返回带商品字段与交互信号的行容器。
func _trade_row(entry: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(273, 22)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color.TRANSPARENT
	row.add_theme_stylebox_override("panel", normal_style)
	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 2)
	row.add_child(fields)
	var name_label := _inline_label(String(entry.get("display_name", "未知物品")), 112)
	name_label.clip_text = true
	fields.add_child(name_label)
	var price_key := "price" if _mode == "buy" else "unit_price"
	fields.add_child(_inline_label(str(int(entry.get(price_key, 0))), 52, HORIZONTAL_ALIGNMENT_RIGHT))
	var amount := 1 if _mode == "buy" else int(entry.get("quantity", entry.get("amount", 1)))
	fields.add_child(_inline_label(str(amount), 36, HORIZONTAL_ALIGNMENT_RIGHT))
	var action := _legacy_button("购买" if _mode == "buy" else "出售", Vector2.ZERO, Vector2(54, 20))
	action.pressed.connect(_request_trade.bind(entry.duplicate(true)))
	fields.add_child(action)
	row.mouse_entered.connect(_on_row_entered.bind(row, entry.duplicate(true)))
	row.mouse_exited.connect(_on_row_exited.bind(row))
	return row


## 高亮悬浮商品并显示图标、说明、等级与价格。
## [param row] 当前商品行。
## [param entry] 当前商品投影。
func _on_row_entered(row: PanelContainer, entry: Dictionary) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = HOVER_COLOR
	row.add_theme_stylebox_override("panel", style)
	_description_title.text = String(entry.get("display_name", ""))
	var description := String(entry.get("description", ""))
	if _mode == "buy":
		description += "\n\n%d级装备\n售价：%d" % [
			int(entry.get("required_level", 0)), int(entry.get("price", 0)),
		]
	else:
		description += "\n\n收购价：%d" % int(entry.get("unit_price", 0))
	_description_body.text = description.strip_edges()
	var presentation: Dictionary = entry.get("presentation", {})
	var inventory_value: Variant = presentation.get("inventory", presentation)
	var resolved: Dictionary = TextureResolverScript.resolve(
		inventory_value as Dictionary if inventory_value is Dictionary else presentation
	)
	_preview.texture = resolved.get("texture") as Texture2D


## 清除离开商品行后的高亮背景。
## [param row] 已失去悬浮状态的商品行。
func _on_row_exited(row: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	row.add_theme_stylebox_override("panel", style)


## 把当前商品转换为只含稳定标识和 revision 的交易意图。
## [param entry] 被点击的商品投影。
func _request_trade(entry: Dictionary) -> void:
	if _inventory_revision < 0:
		return
	if _mode == "buy":
		command_requested.emit({
			"type": "buy_from_weapon_merchant",
			"merchant_id": _merchant_id,
			"definition_id": String(entry.get("definition_id", "")),
			"inventory_revision": _inventory_revision,
		})
	else:
		command_requested.emit({
			"type": "sell_to_weapon_merchant",
			"merchant_id": _merchant_id,
			"instance_id": String(entry.get("instance_id", "")),
			"quantity": 1,
			"inventory_revision": _inventory_revision,
		})


## 刷新普通武器商人的循环任务正文和材料进度。
func _render_task() -> void:
	var tasks: Array = _commerce.get("tasks", [])
	_task_selector.clear()
	var selected := 0
	for index in range(tasks.size()):
		_task_selector.add_item(String(tasks[index]["title"]))
		if String(tasks[index]["task_id"]) == _selected_task_id:
			selected = index
	if not tasks.is_empty():
		_task_selector.select(selected)
		_commerce["task"] = tasks[selected]
		_selected_task_id = String(tasks[selected]["task_id"])
	_task_selector.visible = tasks.size() > 1
	_task_message.position.y = 50 if _task_selector.visible else 20
	_task_message.size.y = 88 if _task_selector.visible else 118
	_title_label.text = String((_commerce.get("task", {}) as Dictionary).get("title", "循环任务"))
	for child in _task_progress.get_children():
		child.queue_free()
	var task: Dictionary = _commerce.get("task", {})
	var dialogue: Dictionary = task.get("dialogue", {})
	var exhausted := bool(task.get("exhausted", false))
	var accepted := bool(task.get("accepted", false))
	var can_turn_in := bool(task.get("ready_to_turn_in", false))
	var operation: Dictionary = _commerce.get("operation", {})
	var just_completed := String(operation.get("action", "")) == "turn_in_task" \
		and String(operation.get("task_id", "")) == String(task.get("task_id", ""))
	if exhausted:
		_task_message.text = String(dialogue.get("exhausted", "任务次数已经用尽。"))
	elif just_completed:
		_task_message.text = String(dialogue.get("complete", "任务已经完成。"))
	elif can_turn_in:
		_task_message.text = String(dialogue.get("turn_in", "材料已经齐备。"))
	else:
		_task_message.text = String(dialogue.get("offer", ""))
	var reward_names := PackedStringArray()
	for reward: Dictionary in task.get("next_milestone_rewards", []):
		reward_names.append("%s×%d" % [reward["display_name"], reward["quantity"]])
	if not reward_names.is_empty():
		_task_message.text += "\n下次里程碑奖励：" + "、".join(reward_names)
	if just_completed:
		var received := PackedStringArray()
		for reward: Dictionary in operation.get("milestone_rewards", []):
			received.append("%s×%d" % [reward["display_name"], reward["quantity"]])
		if not received.is_empty():
			_task_message.text += "\n本次获得：" + "、".join(received)
	for value: Variant in task.get("requirements", []):
		if not value is Dictionary:
			continue
		var requirement := value as Dictionary
		var progress := _inline_label("%s：%d / %d" % [
			String(requirement.get("display_name", "材料")),
			int(requirement.get("owned", 0)),
			int(requirement.get("required", 0)),
		], 390)
		progress.add_theme_color_override(
			"font_color", Color("8dff9e") if bool(requirement.get("complete", false)) else LEGACY_TEXT
		)
		_task_progress.add_child(progress)
	var completions := int(task.get("completions", 0))
	var maximum := int(task.get("maximum_completions", 0))
	if String(task.get("kind", "")) == "kill_training":
		_task_progress.add_child(_inline_label("今日接取：%d / %d　累计完成：%d" % [
			int(task.get("daily_accepted", 0)), int(task.get("daily_accept_limit", 0)), completions], 390))
		_task_progress.add_child(_inline_label("奖励：%s等级 +1" % String(task.get("title", "")).trim_suffix("训练"), 390))
	else:
		_task_progress.add_child(_inline_label("完成次数：%d / %d　报酬：%d 金币" % [
			completions, maximum, int(task.get("currency_reward", 0))], 390))
	_task_primary_button.text = "完成任务" if accepted else "接受任务"
	_task_primary_button.disabled = task.is_empty() or exhausted or (accepted and not can_turn_in)


## 五种训练共用原版任务窗，切换只读详情，不自动接取或重抽目标。
func _select_task(index: int) -> void:
	var tasks: Array = _commerce.get("tasks", [])
	if index < 0 or index >= tasks.size():
		return
	_selected_task_id = String(tasks[index]["task_id"])
	_render_task()


## 根据当前任务状态提交接受或交付意图。
func _request_task_action() -> void:
	var task: Dictionary = _commerce.get("task", {})
	if bool(task.get("accepted", false)):
		if _inventory_revision >= 0:
			command_requested.emit({
				"type": "turn_in_weapon_merchant_task",
				"task_id": String(task.get("task_id", "")),
				"merchant_id": _merchant_id,
				"inventory_revision": _inventory_revision,
			})
	else:
		command_requested.emit({
			"type": "accept_weapon_merchant_task",
			"task_id": String(task.get("task_id", "")),
			"merchant_id": _merchant_id,
		})


## 把交易说明区恢复到未选择商品的状态。
func _clear_description() -> void:
	_description_title.text = ""
	_description_body.text = "将鼠标移到物品上查看说明"
	_preview.texture = null


## 在窗口内容根节点创建统一文本控件。
## [param label_name] 节点名称。
## [param label_position] 窗口局部坐标。
## [param label_size] 控件尺寸。
## [param font_size] 字号。
## [param font] 字体资源。
## 返回已加入内容根节点的文本控件。
func _label(
	label_name: String, label_position: Vector2, label_size: Vector2,
	font_size: int, font: Font,
) -> Label:
	return _label_on(content_root, label_name, label_position, label_size, font_size, font)


## 在指定父节点创建统一文本控件。
## [param parent] 接收文本控件的父节点。
## [param label_name] 节点名称。
## [param label_position] 父节点局部坐标。
## [param label_size] 控件尺寸。
## [param font_size] 字号。
## [param font] 字体资源。
## 返回已加入父节点的文本控件。
func _label_on(
	parent: Node, label_name: String, label_position: Vector2, label_size: Vector2,
	font_size: int, font: Font,
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = label_position
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", LEGACY_TEXT)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## 创建商品行内固定宽度的文本字段。
## [param text] 显示内容。
## [param width] 字段宽度。
## [param alignment] 水平对齐方式。
## 返回配置完成的文本控件。
func _inline_label(text: String, width: float, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 20)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", REGULAR_FONT)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", LEGACY_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 创建免费版商店风格的文字按钮。
## [param text] 按钮文案。
## [param button_position] 父节点局部坐标。
## [param button_size] 按钮尺寸。
## 返回配置完成的按钮。
func _legacy_button(text: String, button_position: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = button_position
	button.custom_minimum_size = button_size
	button.size = button_size
	button.add_theme_font_override("font", REGULAR_FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", CYAN_TEXT)
	button.add_theme_color_override("font_hover_color", Color.YELLOW)
	button.add_theme_stylebox_override("normal", _button_style(Color("082542"), Color("247fac")))
	button.add_theme_stylebox_override("hover", _button_style(Color("123d5d"), Color("70eaff")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("041421"), Color.YELLOW))
	return button


## 创建商店主窗口的深蓝描边背景。
## 返回主窗口样式。
func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("00182df4")
	style.border_color = Color("45bee9")
	style.set_border_width_all(2)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 5
	return style


## 创建商店列表和说明区的半透明内框背景。
## 返回内框样式。
func _inner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("06111dcc")
	style.border_color = Color("1b5d7b")
	style.set_border_width_all(1)
	return style


## 创建指定颜色的商店按钮状态样式。
## [param background] 背景颜色。
## [param border] 描边颜色。
## 返回按钮状态样式。
func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	return style
