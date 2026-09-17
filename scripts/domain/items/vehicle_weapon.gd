class_name VehicleWeapon
extends VehicleEquipment

var base_attack: int
var working_energy_per_shot: float
var attack_range: float
var attack_interval_seconds: float


## 初始化拥有攻击、能耗、射程和冷却行为的战车武器。
## [param definition] 武器配置定义。
## [param state] 存档中的武器实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	refresh_processed_stats()


## 同步攻击和射程加工；不改变武器的冷却与能耗。
func refresh_processed_stats() -> void:
	base_attack = maxi(0, int(stat("base_attack", 0)))
	working_energy_per_shot = maxf(0.0, float(stat("working_energy_per_shot", 0.0)))
	attack_range = maxf(0.0, float(stat("range", 0.0)))
	attack_interval_seconds = maxf(0.0, float(stat("attack_interval_seconds", 0.0)))


## 查询武器的战斗业务类型，供装配计算、HUD 和世界表现共享。
## 返回能量炮、导弹或火箭的模式标识；未知武器返回空字符串。
func combat_mode() -> String:
	match _device_kind:
		"energy_cannon": return "energy_cannon"
		"missile_weapon": return "missile"
		"rocket_weapon": return "rocket_launcher"
	if equipment_location == 1:
		return "energy_cannon"
	return String({"starter_missile": "missile", "starter_rocket_launcher": "rocket_launcher"}.get(definition_id, ""))
