class_name PlayerErrorMessages
extends RefCounted

const MESSAGES := {
	"mining.arm_required": "请先在战车主装置槽装备采掘臂，能量炮不能采矿",
	"mining.arm_broken": "采掘臂已损坏，请先修理",
	"mining.arm_skill_too_low": "采矿技能等级不足，无法使用这件采掘臂",
	"mining.skill_too_low": "采矿技能等级不足，无法采集这种矿物",
	"mining.out_of_range": "与矿物的距离不合适，请调整位置后再采集",
	"mining.source_missing": "没有选中可采集的矿物",
	"mining.source_depleted": "这处矿物已被采完",
	"mining.not_available": "当前地图不能采矿",
	"mining.stale_command": "采矿操作已过期，请重新选择矿物",
	"movement.no_propulsion": "未安装可用推进器，战车无法移动",
	"equipment.chassis_change_forbidden_in_field": "野外地图中不能更换战车",
	"equipment.chassis_change_requires_empty_loadout": "更换战车前请先卸下其他战车装备",
	"equipment.chassis_required": "请先装备战车，再安装其他装备",
	"equipment.chassis_required_for_field": "未装备战车，无法进入野外地图",
	"equipment.primary_weapon_required_for_field": "请先安装主炮或采掘臂，再进入野外地图",
	"equipment.location_rejected": "这件装备不能安装到该位置",
	"equipment.slot_empty": "该装备槽已为空，请刷新后重试",
	"equipment.revision_conflict": "装备状态已经更新，请重试",
	"inventory.revision_conflict": "背包状态已经更新，请重试",
	"inventory.no_space": "背包空间不足，请先整理背包",
	"inventory.duplicate_item": "物品入账编号冲突，本次操作未完成，请重试",
	"inventory.capacity_exceeded": "背包已满，请先腾出空间",
	"inventory_full": "背包已满，请先腾出空间",
	"inventory.item_not_found": "物品已不存在，请刷新背包后重试",
	"inventory.insufficient_quantity": "物品数量不足",
	"inventory.invalid_quantity": "请输入有效的物品数量",
	"inventory.item_locked": "该物品已锁定，无法操作",
	"inventory.item_not_tradeable": "该物品不可出售或交易",
	"inventory.invalid_position": "这个位置不能放置物品",
	"inventory.out_of_bounds": "物品超出背包边界，请换一个位置",
	"commerce.insufficient_currency": "金币不足，无法购买",
	"commerce.item_not_offered": "该商人不出售这件物品",
	"commerce.merchant_missing": "该商人当前不可用",
	"manufacturing.material_missing": "材料不足，无法生产",
	"manufacturing.skill_insufficient": "生产技能等级不足",
	"manufacturing.station_unavailable": "当前地图没有该生产设施",
	"manufacturing.station_invalid": "该生产设施当前不可用",
	"manufacturing.recipe_missing": "该工作台没有此配方",
	"manufacturing.recipe_invalid": "该配方暂不可用",
	"quest.already_accepted": "已经接取该任务，请先完成当前任务",
	"quest.not_accepted": "请先接取任务",
	"quest.requirements_missing": "任务条件尚未完成",
	"quest.exhausted": "该任务的完成次数已达上限",
	"quest.daily_limit": "今日该任务的接取次数已达上限，请明天再来",
	"quest.no_targets": "当前等级暂无可用任务目标",
	"quest.skill_maximum": "该技能已满级，无法领取升级奖励",
	"quest.wrong_map": "请前往任务发布者所在地图办理",
	"combat.weapon_not_equipped": "未装备对应武器，无法开火",
	"combat.weapon_cooldown": "武器尚未冷却，请稍候",
	"combat.insufficient_working_energy": "工作能量不足，请等待恢复",
	"combat.insufficient_power_output": "战车输出功率不足，无法使用该武器",
	"combat.target_too_close": "目标距离太近，无法攻击",
	"combat.target_already_dead": "目标已被击败",
	"combat.target_required": "请先选择攻击目标",
	"combat.vehicle_destroyed": "战车已损毁，请先返回基地修复",
	"combat.self_repair_not_needed": "战车生命已满，无需自维修",
	"combat.self_repair_unavailable": "当前战车不能使用自维修",
	"combat.repair_skill_insufficient": "维修技能等级不足",
	"combat.not_available": "当前地图不能进行战斗",
	"combat.invalid_aim": "请选择有效的攻击位置",
	"loot.not_found": "掉落物已被拾取或消失",
	"loot.out_of_range": "距离掉落物太远，请靠近后拾取",
	"unauthenticated_peer": "尚未连接到游戏服务器，请重新连接",
	"session_map_unavailable": "当前地图暂不可用，请重新进入游戏",
	"protocol_version_mismatch": "客户端版本不匹配，请更新游戏",
	"content_version_mismatch": "游戏资源版本不匹配，请更新资源",
	"connection.failed": "无法连接服务器，请检查连接后重试",
	"map.load_failed": "地图加载失败，请检查游戏资源后重试",
}


## 将协议错误映射为面向玩家的中文，未知错误也不得泄露英文或内部路径。
## [param code] 稳定错误码；不按英文错误句子匹配。
## [param detail] 原始诊断信息；仅纯中文业务提示可保留细节。
## 返回中文提示，日志仍由调用边界保留原始错误码与原文。
static func describe(code: StringName, detail: String = "") -> String:
	if _is_player_chinese(detail):
		return detail.strip_edges()
	var key := String(code)
	if MESSAGES.has(key):
		return MESSAGES[key]
	if key.ends_with("revision_conflict"):
		return "角色状态已经更新，请重试"
	if key.contains("session") or key.contains("connection") or key.contains("peer"):
		return "连接状态已变化，请重新连接游戏"
	if key.contains("map") or key.contains("transition"):
		return "暂时无法切换地图，请稍后重试"
	if key.begins_with("persistence.") or key.begins_with("storage."):
		return "角色数据暂时无法保存，请稍后重试"
	var actions := {"mining": "采矿", "combat": "战斗操作", "inventory": "背包操作", "equipment": "装备操作", "commerce": "交易", "quest": "任务操作", "manufacturing": "生产", "loot": "拾取"}
	var category := key.get_slice(".", 0)
	if actions.has(category):
		return "%s暂时失败，请稍后重试" % actions[category]
	return "操作暂时无法完成，请稍后重试"


## 判断服务端详情是否为可直接展示的简短中文业务提示。
## [param detail] 原始文本；混合英文、资源路径和技术字段均交回错误码映射。
## 返回包含中文且没有拉丁字母、路径分隔符的结果。
static func _is_player_chinese(detail: String) -> bool:
	if detail.length() > 200 or detail.contains("/") or detail.contains("\\"):
		return false
	var has_chinese := false
	for index in range(detail.length()):
		var character := detail.unicode_at(index)
		if (character >= 65 and character <= 90) or (character >= 97 and character <= 122):
			return false
		has_chinese = has_chinese or (character >= 0x3400 and character <= 0x9fff)
	return has_chinese
