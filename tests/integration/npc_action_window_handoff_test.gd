extends SceneTree

const HallScene := preload("res://scenes/main_hall.tscn")
const FacilityScript := preload("res://scripts/client/world/world_facility_interaction.gd")
const ShopScript := preload("res://scripts/npcs/shop_npc.gd")
const FactoryScript := preload("res://scripts/characters/character_factory.gd")

var failures := PackedStringArray()
var commands: Array[Dictionary] = []


## 延迟执行真实菜单到业务窗口的交接，避免在场景树初始化中挂载大厅。
func _initialize() -> void:
	call_deferred("_run")


## 验证同步关闭菜单清空交互对象后，制造和商店窗口仍保留正确的标题与请求标识。
## 设计：使用真实 HUD 信号、主场景处理器和窗口管理器；关闭自动联机以隔离个人存档。
func _run() -> void:
	var hall := HallScene.instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	hall.game_window_manager.command_dispatched.connect(_record_command)
	var facilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/world/manufacturing_facilities_v1.json"
	))
	for map_id: String in facilities["maps"]:
		var definition: Dictionary = facilities["maps"][map_id][0]
		var facility := FacilityScript.new()
		_expect(facility.configure(definition) == OK, "生产设施应成功配置")
		hall.add_child(facility)
		_click_action(hall, facility, 0)
		_expect(hall.game_window_manager.manufacturing_window.visible, "制造菜单应打开生产窗口")
		_expect(hall.game_window_manager.manufacturing_window.station_id() == facility.station_id,
			"生产窗口应绑定被点击设施的类型")
		_expect(hall.hint_label.text == "正在使用%s" % facility.display_name,
			"关闭菜单后仍应显示正确的设施名称")
		_expect(not commands.is_empty() and commands[-1].get("station_id") == facility.station_id,
			"制造查询应携带被点击设施的类型")
		facility.free()
	for definition: Dictionary in hall.npc_catalog["maps"]["glory_nft_bl_weaponshop1"]:
		var merchant := ShopScript.new()
		merchant.configure_npc(FactoryScript.build_character_set(
			hall.character_catalog, definition["appearance"]
		), definition, hall.navigation)
		hall.add_child(merchant)
		var actions: Array = merchant.get_interaction_data()["actions"]
		for index in range(actions.size()):
			_click_action(hall, merchant, index)
			_expect(hall.game_window_manager.weapon_merchant_window.visible, "商人菜单应打开交易窗口")
			_expect(hall.game_window_manager.weapon_merchant_window.current_mode() == actions[index]["id"],
				"交易窗口应采用被点击的买卖或任务模式")
			_expect(hall.hint_label.text == "正在与%s交互" % definition["name"],
				"关闭菜单后仍应显示正确的商人名称")
			_expect(not commands.is_empty() and commands[-1].get("merchant_id") == merchant.npc_id,
				"商店查询应保留普通或特殊武器商人的身份")
			_expect(not merchant.interaction_active, "关闭菜单应解除商人选中状态")
		merchant.free()
	var command_count := commands.size()
	hall.hud.npc_action_requested.emit("manufacture")
	_expect(commands.size() == command_count, "没有活动对象时应忽略迟到的菜单动作")
	hall.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("NPC_ACTION_WINDOW_HANDOFF_OK")
	quit(0 if failures.is_empty() else 1)


## 打开真实交互菜单并发出按钮点击，覆盖关闭信号的同步重入。
## [param hall] 已初始化且禁用自动联机的主场景。
## [param target] 本次点击的生产设施或商人。
## [param action_index] 当前菜单内的动作按钮序号。
func _click_action(hall: Node2D, target: Node2D, action_index: int) -> void:
	hall._show_npc_popup(target)
	commands.clear()
	hall.hint_label.text = "等待菜单操作"
	hall.hud.popup_actions.get_child(action_index).pressed.emit()
	_expect(hall.active_npc == null, "关闭菜单应同步清空当前交互对象")
	_expect(not hall.hud.popup.visible, "打开业务窗口后上下文菜单应关闭")
	_expect(commands.size() == 1, "一次菜单动作应只发出一条权威查询")


## 记录窗口通过统一管理器发出的命令，验证关闭菜单后身份参数仍然正确。
## [param command] 待发送至权威服务的查询意图。
func _record_command(command: Dictionary) -> void:
	commands.append(command.duplicate(true))


## 收集行为断言失败，使测试在脚本异常中断动作回调后仍能报告错误。
## [param condition] 当前行为约束是否成立。
## [param message] 失败时输出的说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
