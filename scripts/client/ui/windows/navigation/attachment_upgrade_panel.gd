class_name AttachmentUpgradePanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

const EFFECTS := {"energy_cannon_attack": "能量炮攻击", "rocket_attack": "火箭炮攻击", "missile_attack": "导弹攻击",
	"max_health": "战车生命", "speed": "移动速度", "mining_time_ms": "采掘时间缩短（毫秒）", "radar": "侦测数值（雷达玩法暂未开放）"}
var listing: ItemList
var details: RichTextLabel
var upgrade_button: Button
var confirmation: ConfirmationDialog
var _summary: Label
var _icon: TextureRect
var _rows: Array = []
var _selected_id := ""
var _inventory_revision := -1
var _loadout_revision := -1
var _pending: Dictionary = {}


## 创建接合器强化窗口，展示自有实例、材料缺口和升级前后效果。
func _ready() -> void:
	build_modern_window(Vector2(840, 580), "接合器强化")
	_summary = make_label("读取装备中…", Rect2(24, 58, 650, 30))
	_style_button(make_button("刷新", Rect2(716, 55, 100, 32), open_board))
	make_label("背包与已装配接合器", Rect2(24, 105, 280, 26))
	listing = ItemList.new()
	listing.position = Vector2(24, 140)
	listing.size = Vector2(290, 360)
	listing.add_theme_constant_override("v_separation", 10)
	listing.item_selected.connect(_select)
	content_root.add_child(listing)
	_icon = TextureRect.new()
	_icon.position = Vector2(334, 104)
	_icon.size = Vector2(56, 56)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content_root.add_child(_icon)
	details = RichTextLabel.new()
	details.position = Vector2(334, 172)
	details.size = Vector2(480, 328)
	content_root.add_child(details)
	make_label("成功率 100% · 每次升一级 · 消耗材料与星际币", Rect2(24, 528, 575, 28))
	upgrade_button = make_button("强化一级", Rect2(664, 522, 152, 36), _request_upgrade)
	_style_button(upgrade_button)
	upgrade_button.disabled = true
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认接合器强化"
	confirmation.ok_button_text = "确认强化"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(_confirm_upgrade)
	add_child(confirmation)


## 打开后查询服务器当前装备及材料，界面不保存任何成长状态。
func open_board() -> void:
	command_requested.emit({"type": "query_attachment_upgrades"})


## 应用同一事务的背包、战车版本及强化可用性，保持选择的实例。
## [param bundle] 服务端面板组合快照。
func apply_upgrade_bundle(bundle: Dictionary) -> void:
	if not bundle.get("attachment_upgrades") is Dictionary:
		return
	_inventory_revision = int(bundle.inventory.revision)
	_loadout_revision = int(bundle.vehicle.revision)
	var snapshot: Dictionary = bundle.attachment_upgrades
	_summary.text = "星际币：%d  ·  新式最高 +5 / 旧式最高 +4" % int(snapshot.currency)
	_rows = snapshot.items
	listing.clear()
	upgrade_button.disabled = true
	_icon.texture = null
	details.text = "请选择要强化的接合器。" if not _rows.is_empty() else "暂无接合器，可在商城购买后再来强化。"
	for row: Dictionary in _rows:
		listing.add_item("[%s] %s +%d" % ["已装配" if row.installed else "背包", row.display_name, int(row.upgrade_level)])
		if String(row.instance_id) == _selected_id:
			listing.select(listing.item_count - 1)
			_select(listing.item_count - 1)
	if snapshot.operation.get("action", "") == "attachment_upgrade":
		notice_requested.emit("强化成功，接合器提升至 +%d" % int(snapshot.operation.target_level))


## 展示当前实例的属性预览、全部材料需求与服务器给出的拒绝原因。
## [param index] 当前列表索引。
func _select(index: int) -> void:
	var row: Dictionary = _rows[index]
	_selected_id = String(row.instance_id)
	_icon.texture = ItemPresentationTextureResolver.resolve(row.get("presentation", {})).get("texture")
	details.text = "%s +%d\n" % [row.display_name, int(row.upgrade_level)]
	if row.has("target_level"):
		var effect := String(row.stats.get("attachment_effect", ""))
		details.text += "%s：%d → %d\n\n材料（拥有 / 需要）：\n" % [EFFECTS.get(effect, effect), row.effect_before, row.effect_after]
		for requirement: Dictionary in row.requirements:
			details.text += "%s：%d / %d%s\n" % [requirement.display_name, int(requirement.owned), int(requirement.quantity), "  缺少" if requirement.owned < requirement.quantity else ""]
		details.text += "\n星际币消耗：%d\n商城材料参考总价：%d 紫晶\n强化仅扣材料与金币，不再扣紫晶。" % [int(row.currency_cost), int(row.premium_cost)]
		if int(row.durability) <= 0:
			details.text += "\n装备已损坏：强化不会修复耐久，修复后属性才生效。"
	if not String(row.reason).is_empty():
		details.text += "\n\n" + String(row.reason)
	upgrade_button.disabled = not bool(row.can_upgrade)
	upgrade_button.tooltip_text = String(row.reason)


## 展示精确的单级消耗并捕获当前版本，取消不产生服务端操作。
func _request_upgrade() -> void:
	if upgrade_button.disabled or listing.get_selected_items().is_empty():
		return
	var row: Dictionary = _rows[listing.get_selected_items()[0]]
	_pending = {"type": "upgrade_attachment", "instance_id": row.instance_id,
		"inventory_revision": _inventory_revision, "loadout_revision": _loadout_revision}
	confirmation.dialog_text = "%s：+%d → +%d\n" % [row.display_name, int(row.upgrade_level), int(row.target_level)]
	for requirement: Dictionary in row.requirements:
		confirmation.dialog_text += "%s ×%d\n" % [requirement.display_name, int(requirement.quantity)]
	confirmation.dialog_text += "星际币：%d\n成功率100%%，不额外扣紫晶。" % int(row.currency_cost)
	confirmation.popup_centered(Vector2i(470, 360))


## 提交已确认实例与版本；价格、目标等级、材料数量均由服务端决定。
func _confirm_upgrade() -> void:
	if _pending.is_empty():
		return
	upgrade_button.disabled = true
	var command := _pending.duplicate()
	_pending.clear()
	command_requested.emit(command)
