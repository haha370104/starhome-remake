class_name EquipmentMaintenancePanel
extends EquipmentProcessingPanel

var mode_selector: OptionButton


## 复用装备与材料选择界面，维护规则和命令仍由独立服务处理。
func _init() -> void:
	window_title = "装备 · 常规维护与速修"
	window_dimensions = Vector2(940, 670)
	material_title = "速修箱 · 背包"
	details_title = ""
	hint_text = "常规维护：背包装备，返回基地或生产区。\n电磁/光导箱修已装配装备，离子箱修背包装备。"
	summary_text = "维护前请核对耐久上限变化"
	snapshot_key = "equipment_maintenance"
	query_type = "query_equipment_maintenance"
	execute_type = "maintain_equipment"
	purchase_type = "buy_maintenance_tool"
	purchase_title = "速修工具 · 星际币"


## 在稳定的选择与确认组件上增加维护模式和工具购买。
func _ready() -> void:
	super()
	mode_selector = OptionButton.new()
	mode_selector.position = Vector2(578, 90)
	mode_selector.size = Vector2(338, 32)
	mode_selector.add_item("常规维护 / 服装修补")
	mode_selector.add_item("使用速修箱")
	mode_selector.add_item("补充弹药")
	mode_selector.item_selected.connect(_select_mode)
	content_root.add_child(mode_selector)
	execute_button.text = "执行维护"
	confirmation.title = "确认装备维护"


## 从工具右键进入时直接选择速修模式，仍需用户明确选择目标。
## [param id] 初始装备或工具实例。
## [param is_material] 是否为速修工具。
func focus_item(id: String = "", is_material: bool = false) -> void:
	if is_material:
		mode_selector.select(1)
		mode = "quick"
		execute_type = "quick_repair_equipment"
		execute_button.text = "使用速修箱"
	super(id, is_material)


## 接收独立维护快照并保持商品选择，其他装备窗口的消息只触发必要刷新。
## [param bundle] 同版本面板数据。
func apply_maintenance_bundle(bundle: Dictionary) -> void:
	apply_processing_bundle(bundle)


## 切换维护方式只改变意图，恢复数值由服务器预览。
## [param index] 用户选择的模式。
func _select_mode(index: int) -> void:
	mode = ["regular", "quick", "ammunition"][index]
	execute_type = ["maintain_equipment", "quick_repair_equipment", "refill_equipment_ammunition"][index]
	execute_button.text = ["执行维护", "使用速修箱", "补满弹药"][index]
	open_board()
