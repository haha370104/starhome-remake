class_name SmartAssistantPolicy
extends RefCounted

var enabled := false
var auto_attack := false
var gun_missile_mode := false
var auto_pickup := false
var auto_repair := false
var repair_threshold := 0.5
var auto_energy := false
var auto_food := false
var energy_definition_id := ""
var food_definition_id := ""
var energy_threshold := 0.3
var physical_threshold := 0.5


## 应用用户偏好；无效阈值夹紧，不能改变服务端技能和距离限制。
## [param values] 设置面板或本地配置的偏好。
func apply(values: Dictionary) -> void:
	enabled = bool(values.get("enabled", false))
	auto_attack = bool(values.get("auto_attack", false))
	gun_missile_mode = bool(values.get("gun_missile_mode", false))
	auto_pickup = bool(values.get("auto_pickup", false))
	auto_repair = bool(values.get("auto_repair", false))
	auto_energy = bool(values.get("auto_energy", false))
	auto_food = bool(values.get("auto_food", false))
	energy_definition_id = String(values.get("energy_definition_id", ""))
	food_definition_id = String(values.get("food_definition_id", ""))
	repair_threshold = _threshold(values.get("repair_threshold", 0.5), 0.5)
	energy_threshold = _threshold(values.get("energy_threshold", 0.3), 0.3)
	physical_threshold = _threshold(values.get("physical_threshold", 0.5), 0.5)


## 序列化用户选择；开关不会增加战斗能力。
## 返回可持久化的设置副本。
func snapshot() -> Dictionary:
	return {"enabled": enabled, "auto_attack": auto_attack, "auto_pickup": auto_pickup,
		"auto_repair": auto_repair, "repair_threshold": repair_threshold, "gun_missile_mode": gun_missile_mode,
		"auto_energy": auto_energy, "auto_food": auto_food, "energy_definition_id": energy_definition_id,
		"food_definition_id": food_definition_id, "energy_threshold": energy_threshold, "physical_threshold": physical_threshold}


## 炮导模式只交替选择实际装配的能量炮与导弹，不自动开火或改写冷却。
## [param selected] 当前HUD动作。
## [param loadout] 当前玩家已装配的装置，背包物品不参与判断。
## 返回下一武器动作；开关关闭、装配不符或选中其他动作时为空。
func next_attack_weapon(selected: String, loadout: VehicleLoadout) -> String:
	if not enabled or not gun_missile_mode or loadout == null or selected not in ["energy_cannon", "missile"]:
		return ""
	var primary := loadout.at(1)
	var tactical := loadout.at(13)
	if primary == null or primary.primary_device_kind() != "energy_cannon" or tactical == null:
		return ""
	if not tactical is VehicleWeapon or (tactical as VehicleWeapon).combat_mode() != "missile":
		return ""
	return "missile" if selected == "energy_cannon" else "energy_cannon"


## 根据当前资源和用户指定类型选择一次补给，返回手动使用所需实例身份，不计算消费数量。
## [param player] 同事务玩家投影。[param vehicle] 最新权威战斗资源。[param now] 当前显示时钟。
## 返回可尝试使用的实例身份；未选择、锁定、耗尽、冷却或无需补给时为空。
func next_supply(player: Player, vehicle: Dictionary, now: int) -> String:
	if not enabled or player == null or player.health <= 0 or int(vehicle.get("health", 0)) <= 0: return ""
	var reserve := float(vehicle.get("reserve_energy", 0))
	var capacity := float(vehicle.get("reserve_energy_capacity", 0))
	if auto_energy and capacity > 0 and reserve < capacity and reserve <= capacity * energy_threshold:
		var pack := _supply(player.inventory, energy_definition_id, true)
		if pack != null and player.food_status.can_eat(pack, now).is_ok: return pack.instance_id
	if auto_food:
		var food := _supply(player.inventory, food_definition_id, false)
		if food != null and player.food_status.can_eat(food, now).is_ok and _food_needed(food, player.food_status, vehicle, now):
			return food.instance_id
	return ""


## 查找指定类型的健全堆叠，允许同类型换堆，不替换成其他食物。
## [param inventory] 当前背包。[param definition_id] 用户选定类型。[param energy_pack] 是否要求能量包。
## 返回未锁定的可用品，或空引用。
func _supply(inventory: Inventory, definition_id: String, energy_pack: bool) -> ConsumableItem:
	if definition_id.is_empty(): return null
	for item: GameItem in inventory.items():
		if item.definition_id != definition_id or item.locked or not item is ConsumableItem: continue
		var consumable := item as ConsumableItem
		if (consumable.energy > 0) == energy_pack: return consumable
	return null


## 只在体力不足、选定食品有已到期效果或需要即时回血时补给，仍生效的效果不反复刷新。
## [param food] 指定食品。[param status] 体力与有效增益。[param vehicle] 权威战车生命。[param now] 显示时钟。
## 返回是否存在实际补给需要。
func _food_needed(food: ConsumableItem, status: FoodStatus, vehicle: Dictionary, now: int) -> bool:
	var needed := food.physical > 0 and status.physical < 100 and status.physical <= physical_threshold * 100
	for effect: FoodEffect in food.effects:
		if effect.kind == 19:
			needed = needed or int(vehicle.get("health", 0)) <= float(vehicle.get("max_health", 1)) * repair_threshold
			continue
		var active := false
		for existing: FoodEffect in status.active:
			if existing.kind == effect.kind and existing.expires_at > now: active = true
		needed = needed or not active
	return needed


## 拒绝非法本地阈值，NaN或无限值不会漏入每帧决策。
## [param value] 本地配置或界面值。[param fallback] 缺失时的默认阈值。
## 返回0.1至0.9的有限比例。
func _threshold(value: Variant, fallback: float) -> float:
	if not value is int and not value is float: return fallback
	return clampf(float(value), 0.1, 0.9) if is_finite(float(value)) else fallback


## 根据真实快照判断是否需要触发与 Z 相同的自维修。
## [param vehicle] 服务器战车状态。
## 返回未在维修且血量低于阈值时为真。
func needs_repair(vehicle: Dictionary) -> bool:
	return enabled and auto_repair and int(vehicle.get("health", 0)) > 0 \
		and int(vehicle.get("health", 0)) < float(vehicle.get("max_health", 1)) * repair_threshold \
		and not bool(vehicle.get("self_repair_active", false))


## 从当前快照中选择半径内最近的目标，排除死怪和无效坐标。
## [param rows] 怪物或掉落快照数组。
## [param origin] 当前本地位置。
## [param radius] 用户动作允许尝试的半径。
## [param require_alive] 是否排除生命为零的怪物。
## 返回选中行；无目标时为空。
func nearest(rows: Array, origin: Vector2, radius: float, require_alive: bool) -> Dictionary:
	var best: Dictionary = {}
	var distance := radius
	for row: Dictionary in rows:
		if require_alive and int(row.get("health", 0)) <= 0:
			continue
		var point: Array = row.get("position", [])
		if point.size() != 2:
			continue
		var candidate := Vector2(float(point[0]), float(point[1]))
		var current := origin.distance_to(candidate)
		if candidate.is_finite() and current <= distance:
			distance = current
			best = row
	return best
