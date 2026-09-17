class_name VehiclePresetCommands
extends RefCounted

const COMMANDS := ["capture_vehicle_preset", "apply_vehicle_preset"]


## 在应用边界校验输入格式，方案装备只读取服务端当前装配，不接受客户端提供物品列表。
## [param player] 当前权威聚合。[param command] 保存或应用意图。[param now] 服务端时钟。
## 返回领域操作结果，应用仍由原玩家面板事务统一提交。
static func execute(player: Player, command: Dictionary, now: int) -> DomainResult:
	for key: String in ["index", "preset_revision", "loadout_revision"]:
		if not VehicleLoadoutPresets.valid_integer(command.get(key)): return _invalid()
	var index := int(command.index)
	if index >= VehicleLoadoutPresets.COUNT: return _invalid()
	if String(command.get("type")) == "capture_vehicle_preset":
		if not command.get("title") is String: return _invalid()
		if not player.vehicle_presets.at(index).is_empty() and command.get("confirmed") != true:
			return DomainResult.failure(&"presets.confirm_required", "覆盖已有方案需要确认")
		return player.vehicle_presets.capture(index, command.title, player.vehicle.loadout,
			int(command.preset_revision), int(command.loadout_revision))
	if not VehicleLoadoutPresets.valid_integer(command.get("inventory_revision")): return _invalid()
	return player.vehicle_presets.apply(player, index, now, int(command.preset_revision),
		int(command.inventory_revision), int(command.loadout_revision),
		bool(command.get("_authoritative_vehicle_combat_active", false)))


## 拒绝不完整或非整数输入，避免默认值意外指向第一套方案。
## 返回输入错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"presets.invalid", "装备方案命令参数无效")
