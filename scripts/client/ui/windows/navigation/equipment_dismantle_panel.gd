class_name EquipmentDismantlePanel
extends EquipmentProcessingPanel


## 配置拆解预览和原版返还材料，规则与随机结果由服务器拥有。
func _init() -> void:
	window_title = "装备 · 拆解"
	material_title = "可能返还 · 每种最大数量"
	details_title = "概率与销毁后果"
	hint_text = "仅支持原表15款绿色及以上品质装备。\n制造可获得品质装备；先转移需要保留的成长。"
	summary_text = "一次抽取一档结果 · 所有结果都会消耗装备"
	snapshot_key = "equipment_dismantle"
	query_type = "query_equipment_dismantle"
	execute_type = "dismantle_equipment"


## 将材料栏设为只读，防止把结果预览误认为可手选产物。
func _ready() -> void:
	super()
	material_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material_list.focus_mode = Control.FOCUS_NONE
	execute_button.text = "拆解装备"
	confirmation.title = "确认拆解：装备和全部晶石、成长永久消失"
	confirmation.dialog_autowrap = true


## 捕获预览后明确提交销毁确认，取消不执行。
func _ask() -> void:
	super()
	_pending["confirm_destruction"] = true
