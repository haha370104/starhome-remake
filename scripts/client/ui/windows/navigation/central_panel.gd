class_name CentralPanel
extends EquipmentProcessingPanel

var equip_button: Button
var unequip_button: Button
var _chips: Array = []
var _inspected_chip := ""
var _loadout_revision := -1
var _evolved := false


## 配置角色芯片和圣焱装配的专用窗口，沿用现有工坊确认、供给和窗口堆叠。
func _init() -> void:
	window_title = "中枢控制器 · 桥接与圣焱装备"
	window_dimensions = Vector2(940, 740)
	material_title = "桥接芯片 · 点击查看能力"
	hint_text = "芯片使用模块激活或升级；全部3级后可进化核心。\n圣焱装置使用独立槽位，升阶前请先卸下。原版玩家专属技能本次暂缓。"
	snapshot_key = "central_workshop"
	query_type = "query_central"
	execute_type = "change_central"
	purchase_type = "buy_central"
	purchase_title = "中枢模块、圣焱装备与成长材料 · 星际币"
	purchase_quantity_limit = 20


## 保留三列可滚动信息，六个芯片使用原版图标，装备与卸下各自提交明确意图。
func _ready() -> void:
	super()
	for child: Node in content_root.get_children():
		if child is Label and child.text == "装备 · 已装配 / 背包": child.text = "背包模块 / 圣焱装备"
		if child is Label and child.text == hint_text:
			child.position = Vector2(24, 665)
			child.size = Vector2(890, 55)
	material_list.fixed_icon_size = Vector2i(40, 40)
	material_list.max_text_lines = 2
	material_list.add_theme_constant_override("v_separation", 13)
	equip_button = make_button("装备所选装置", Rect2(24, 528, 260, 40), _install)
	unequip_button = make_button("卸下所选装置", Rect2(298, 528, 260, 40), _uninstall)
	_style_button(equip_button)
	_style_button(unequip_button)
	equip_button.disabled = true
	unequip_button.disabled = true
	execute_button.text = "使用模块 / 提升阶数"
	confirmation.title = "确认中枢操作"
	confirmation.dialog_autowrap = true


## 先接收永久芯片事实，再使用通用报价列表，二者不共享同一快照键。
## [param bundle] 同事务面板快照。
func apply_processing_bundle(bundle: Dictionary) -> void:
	if bundle.get("central_workshop") is Dictionary:
		_chips = bundle.central_workshop.chips
		_evolved = bool(bundle.central_workshop.evolved)
		_loadout_revision = int(bundle.get("vehicle", {}).get("revision", -1))
	super(bundle)
	if not bundle.get("central_workshop") is Dictionary: return
	var core := "圣焱型 · 六个装置槽已解锁" if _evolved else "%d级 · 全部芯片3级可进化" % int(bundle.central_workshop.core_grade)
	_summary.text = "星际币：%d　　中枢：%s" % [int(bundle.central_workshop.currency), core]
	_update_install_buttons()
	if not _inspected_chip.is_empty(): _show_chip()


## 在中间列按角色状态展示芯片，其他列表沿用工坊的实例与图标规则。
## [param listing] 列表。[param rows] 数据。[param id] 当前身份。[param equipment] 是否为目标列表。
func _fill_list(listing: ItemList, rows: Array, id: String, equipment: bool) -> void:
	if listing != material_list:
		super(listing, rows, id, equipment)
		return
	listing.clear()
	for chip: Dictionary in _chips:
		var status := "未激活" if int(chip.grade) == 0 else "%d级 · %s" % [int(chip.grade), "生效" if chip.active else "部件不足"]
		listing.add_item("%s\n%s" % [chip.display_name, status], load(String(chip.icon)))
		listing.set_item_tooltip(listing.item_count - 1, String(chip.summary))
		if chip.id == _inspected_chip: listing.select(listing.item_count - 1)


## 检查芯片只改变阅读选择，不把芯片伪装成可消费背包物品。
## [param index] 六类芯片索引。
func _select_material(index: int) -> void:
	if index < 0 or index >= _chips.size(): return
	_inspected_chip = String(_chips[index].id)
	_id = ""
	equipment_list.deselect_all()
	_show_chip()
	_update_install_buttons()


## 切回实际背包目标并请求真实报价。
## [param index] 目标列表索引。
func _select_equipment(index: int) -> void:
	_inspected_chip = ""
	material_list.deselect_all()
	super(index)


## 从背包右键定位实际目标，材料分档不会替代装备身份。
## [param id] 实例身份。[param is_material] 兼容统一工坊导航的参数。
func focus_item(id: String = "", is_material: bool = false) -> void:
	_inspected_chip = ""
	super(id, is_material)


## 展示能力适用范围并关闭不相关的执行按钮。
func _show_chip() -> void:
	for chip: Dictionary in _chips:
		if chip.id == _inspected_chip:
			details.text = String(chip.summary) + "\n\n使用对应一级模块激活，二/三级模块可提升已激活的低级芯片。\n全部六类3级后使用中枢进化晶体。"
	_preview = {"can_execute":false}
	execute_button.disabled = true


## 按当前服务器装配状态开放两个互斥的装置操作。
func _update_install_buttons() -> void:
	equip_button.disabled = true
	unequip_button.disabled = true
	for row: Dictionary in _equipment:
		if row.instance_id != _id or not bool(row.get("central_eligible", false)): continue
		equip_button.disabled = bool(row.installed) or not _evolved or bool(row.locked)
		unequip_button.disabled = not bool(row.installed) or bool(row.locked)


## 提交安装所选圣焱装置。
func _install() -> void:
	_change_installation(true)


## 提交卸下所选圣焱装置。
func _uninstall() -> void:
	_change_installation(false)


## 复用现有装配事务，具体资格和背包容量仍由服务器重验。
## [param install] 是否安装。
func _change_installation(install: bool) -> void:
	for row: Dictionary in _equipment:
		if row.instance_id != _id or not bool(row.get("central_eligible", false)): continue
		command_requested.emit({"type":"equip_vehicle_item" if install else "unequip_vehicle_item", "instance_id":_id,
			"location":int(row.equipment_location), "inventory_revision":_revision, "loadout_revision":_loadout_revision})
		return


## 固定用户确认的模块消费或单阶材料费用。
func _ask() -> void:
	super()
	_pending["confirmed"] = true
