class_name ClothingEnhancementPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var clothes_list: ItemList
var stones_list: ItemList
var details: RichTextLabel
var enhance_button: Button
var synthesize_button: Button
var reset_button: Button
var transfer_button: Button
var confirmation: ConfirmationDialog
var transfer_target: OptionButton
var _summary: Label
var _clothes: Array = []
var _stones: Array = []
var _targets := PackedStringArray()
var _selected_id := ""
var _stone_id := ""
var _inventory_revision := -1
var _preview: Dictionary = {}
var _pending: Dictionary = {}


## 创建独立人物强化窗口，材料、装备和精确预览各自拥有固定区域。
func _ready() -> void:
	build_modern_window(Vector2(940, 630), "人物装备强化")
	_summary = make_label("读取装备与材料…", Rect2(24, 56, 710, 26))
	_style_button(make_button("刷新", Rect2(816, 52, 100, 32), open_board))
	make_label("人物装备 · 已穿 / 背包", Rect2(24, 98, 264, 24))
	make_label("强化材料 · 品质 / 等级", Rect2(302, 98, 264, 24))
	make_label("效果与消耗预览", Rect2(586, 98, 326, 24))
	clothes_list = _make_list(Rect2(24, 132, 264, 340), _select_clothing)
	stones_list = _make_list(Rect2(302, 132, 264, 392), _select_stone)
	details = RichTextLabel.new()
	details.position = Vector2(586, 132)
	details.size = Vector2(330, 392)
	details.bbcode_enabled = true
	details.add_theme_constant_override("line_separation", 4)
	content_root.add_child(details)
	make_label("宝石迁移到同部位空装备", Rect2(24, 478, 264, 24))
	transfer_target = OptionButton.new()
	transfer_target.position = Vector2(24, 508)
	transfer_target.size = Vector2(264, 32)
	transfer_target.clip_text = true
	transfer_target.item_selected.connect(func(_index: int) -> void: transfer_button.disabled = transfer_target.selected <= 0)
	content_root.add_child(transfer_target)
	transfer_button = make_button("迁移宝石", Rect2(24, 548, 126, 34), _request_transfer)
	reset_button = make_button("重置路线", Rect2(162, 548, 126, 34), _request_reset)
	synthesize_button = make_button("合成材料", Rect2(302, 548, 264, 34), _request_synthesis)
	enhance_button = make_button("刻印 / 镶嵌", Rect2(586, 548, 330, 34), _request_enhancement)
	for button: Button in [transfer_button, reset_button, synthesize_button, enhance_button]:
		_style_button(button)
		button.disabled = true
	var hint := make_label("同类前缀、宝石最多生效2件；同类特性只生效最高1件。穿着后影响战车。", Rect2(24, 594, 892, 22))
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("87a9bb"))
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认人物强化操作"
	confirmation.ok_button_text = "确认"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(_confirm)
	add_child(confirmation)
	visibility_changed.connect(func() -> void:
		if not visible:
			confirmation.hide()
			_pending.clear())


## 生成统一图标、字体和间距的滚动清单。
## [param rect] 清单矩形。
## [param selected] 选择事件处理器。
## 返回已加入内容层的清单。
func _make_list(rect: Rect2, selected: Callable) -> ItemList:
	var listing := ItemList.new()
	listing.position = rect.position
	listing.size = rect.size
	listing.fixed_icon_size = Vector2i(36, 36)
	listing.add_theme_constant_override("v_separation", 8)
	listing.add_theme_constant_override("h_separation", 8)
	listing.add_theme_stylebox_override("panel", _surface_style("0b1620", "304b5e"))
	listing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	listing.item_selected.connect(selected)
	content_root.add_child(listing)
	return listing


## 打开后拉取当前选择的服务端预览，不在客户端计算收费或扣材料。
func open_board() -> void:
	enhance_button.disabled = true
	command_requested.emit({"type": "query_clothing_enhancement", "instance_id": _selected_id, "stone_id": _stone_id})


## 从背包操作进入并记住物品，列表到达后按身份定位。
## [param id] 自有服装或强化石实例。
## [param is_stone] 是否选择强化材料。
func focus_item(id: String, is_stone: bool) -> void:
	if is_stone:
		_stone_id = id
	else:
		_selected_id = id
	open_board()


## 消费同一事务的所有清单与预览，选择刷新不再次派发请求。
## [param bundle] 服务端组合面板快照。
func apply_enhancement_bundle(bundle: Dictionary) -> void:
	if not bundle.get("clothing_enhancement") is Dictionary:
		return
	_inventory_revision = int(bundle.inventory.revision)
	var snapshot: Dictionary = bundle.clothing_enhancement
	_summary.text = "星际币：%d   ·   词条六档品质   ·   宝石逐段镶嵌，上限15段" % int(snapshot.currency)
	_clothes = snapshot.clothes
	_stones = snapshot.stones
	_preview = snapshot.preview
	if String(snapshot.operation.get("action", "")) == "transfer_clothing_gems":
		_selected_id = String(snapshot.operation.get("instance_id", _selected_id))
	_fill_list(clothes_list, _clothes, _selected_id, true)
	_fill_list(stones_list, _stones, _stone_id, false)
	_render_selection()
	var action := String(snapshot.operation.get("action", ""))
	if action != "query_clothing_enhancement":
		notice_requested.emit("人物强化操作已完成，属性和材料已同步。")


## 按实例恢复选择，缺失的物品不自动切换为另一件。
## [param listing] 目标清单。
## [param rows] 同版本物品数据。
## [param selected_id] 上次选择身份。
## [param is_clothing] 是否显示穿着位置与前后缀。
func _fill_list(listing: ItemList, rows: Array, selected_id: String, is_clothing: bool) -> void:
	listing.clear()
	for row: Dictionary in rows:
		var label := String(row.display_name)
		if is_clothing:
			label = ("[已穿] " if row.installed else "[背包] ") + EnhancementText.title(label, row.enhancement)
		else:
			label += " ×%d" % int(row.quantity)
		listing.add_item(label, ItemPresentationTextureResolver.resolve(row.presentation).get("texture"))
		listing.set_item_tooltip(listing.item_count - 1, label)
		if String(row.instance_id) == selected_id:
			listing.select(listing.item_count - 1)


## 选择人物装备并请求权威前后效果。
## [param index] 当前装备行。
func _select_clothing(index: int) -> void:
	_selected_id = String(_clothes[index].instance_id)
	open_board()


## 选择材料并请求权威适用性。
## [param index] 当前材料行。
func _select_stone(index: int) -> void:
	_stone_id = String(_stones[index].instance_id)
	open_board()


## 展示当前状态、材料用途、升级预览和可操作性。
func _render_selection() -> void:
	var clothing := _selected(_clothes, _selected_id)
	var stone := _selected(_stones, _stone_id)
	details.text = ""
	if not clothing.is_empty():
		details.append_text("[color=#8edee8]%s[/color]\n%s\n\n" % [EnhancementText.title(String(clothing.display_name), clothing.enhancement), EnhancementText.describe(clothing.enhancement)])
		if not clothing.get("suppressed", []).is_empty():
			details.append_text("[color=#efc67a]有同类更强装备，此件部分效果暂不生效。[/color]\n")
	if not stone.is_empty():
		details.append_text("[color=#efc67a]%s[/color]\n%s\n\n" % [stone.display_name, EnhancementText.stone_description(stone)])
	if _preview.has("after"):
		details.append_text("[color=#8edee8]应用后[/color]\n%s\n\n消耗：材料 ×1、%d 星际币\n" % [EnhancementText.describe(_preview.after), int(_preview.currency_cost)])
		if bool(_preview.get("wastes_rank", false)):
			details.append_text("[color=#efc67a]高级宝石也只增加1段，多余等级不会保留。[/color]\n")
	if not String(_preview.get("reason", "")).is_empty():
		details.append_text("\n" + String(_preview.reason))
	enhance_button.disabled = not bool(_preview.get("can_enhance", false))
	synthesize_button.disabled = stone.is_empty() or not bool(stone.get("can_synthesize", false))
	synthesize_button.text = "合成材料" if stone.is_empty() else "%d合1 · %d 星际币" % [int(stone.synthesis_count), int(stone.synthesis_price)]
	reset_button.disabled = clothing.is_empty() or int(clothing.enhancement.get("gem_stage", 0)) == 0
	transfer_button.disabled = true
	transfer_target.clear()
	_targets.clear()
	transfer_target.add_item("选择迁移目标")
	_targets.append("")
	if not reset_button.disabled:
		for row: Dictionary in _clothes:
			if row.instance_id != _selected_id and row.character_slot == clothing.character_slot and int(row.enhancement.get("gem_stage", 0)) == 0 and not row.locked:
				transfer_target.add_item(String(row.display_name) + (" [已穿]" if row.installed else " [背包]"))
				_targets.append(String(row.instance_id))


## 查找当前行，不依赖刷新前的数组位置。
## [param rows] 同类物品集合。
## [param id] 当前选择实例。
## 返回匹配行或空字典。
func _selected(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row.instance_id) == id:
			return row
	return {}


## 确认单次刻印，替换词条和高级宝石消耗均明确展示。
func _request_enhancement() -> void:
	if enhance_button.disabled:
		return
	_ask("enhance_clothing", "消耗当前材料1个和 %d 星际币。\n词条会替换原来的同槽词条；宝石仅增加1段。\n\n%s" % [int(_preview.currency_cost), EnhancementText.describe(_preview.after)])


## 确认材料合成，下一档内容由服务端根据原料身份确定。
func _request_synthesis() -> void:
	var stone := _selected(_stones, _stone_id)
	if stone.is_empty() or synthesize_button.disabled:
		return
	_ask("synthesize_enhancement", "消耗 %s ×%d 和 %d 星际币，获得同类下一档材料1个。" % [stone.display_name, int(stone.synthesis_count), int(stone.synthesis_price)])


## 显式确认无返还重置，不允许误点直接消耗。
func _request_reset() -> void:
	if not reset_button.disabled:
		_ask("reset_clothing_gems", "消耗1000 星际币，清空此装备全部宝石段数。\n前后缀保留，已镶嵌宝石不返还。")


## 确认同部位迁移，说明来源清空和实际费用。
func _request_transfer() -> void:
	if transfer_target.selected <= 0:
		return
	var row := _selected(_clothes, _selected_id)
	_ask("transfer_clothing_gems", "将宝石路线迁移至 %s。\n消耗 %d 星际币，来源宝石路线清空；双方词条保留。" % [transfer_target.get_item_text(transfer_target.selected), int(row.enhancement.gem_stage) * 500])
	_pending.source_id = _selected_id
	_pending.instance_id = _targets[transfer_target.selected]


## 捕获预览对应的物品版本，等待一次明确确认；后台存档不应使预览失效。
## [param action] 领域操作身份。
## [param message] 精确的消耗说明。
func _ask(action: String, message: String) -> void:
	_pending = {"type": action, "instance_id": _selected_id, "stone_id": _stone_id,
		"inventory_revision": _inventory_revision}
	confirmation.dialog_text = message
	confirmation.popup_centered(Vector2i(550, 350))


## 提交已确认意图，成功与否由权威服务返回。
func _confirm() -> void:
	if _pending.is_empty():
		return
	var command := _pending.duplicate()
	_pending.clear()
	enhance_button.disabled = true
	synthesize_button.disabled = true
	command_requested.emit(command)
