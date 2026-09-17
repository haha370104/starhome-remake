extends SceneTree

var checks := 0
var failures: Array[String] = []


## 检查原版弹药容量、存档、补弹费用、实际射击和加工扩容。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "catalog and fixture")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.map_id = "yian_harbor_hall_floor_1"
	player.inventory.currency = 100000
	var rocket: Equipment = items.create("starter_rocket_launcher", {"instance_id": "rocket"}).value
	_check(rocket.ammunition_capacity() == 100 and rocket.magazine.remaining == 100, "original full magazine")
	player.vehicle.loadout.restore(rocket)
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	var module := AuthoritativeCombatModule.new()
	module.configure(20, 72)
	_check(module.register_vehicle(player.entity_id, "test.map", Vector2.ZERO, loadout.assembly, loadout.weapons).is_ok, "actor")
	var actor: Dictionary = module.actors[player.entity_id]
	var condition: EquipmentConditionLoadout = actor.equipment_condition
	var intent := UseAbilityIntent.new("test.map", "rocket_launcher.primary", Vector2(200, 0), 1).to_dictionary()
	_check(module.handle_weapon_attack(player.entity_id, intent).is_ok, "accepted rocket")
	_check(condition.ammunition_for("rocket").remaining == 99, "one round consumed")
	intent.input_sequence = 2
	_check(not module.handle_weapon_attack(player.entity_id, intent).is_ok, "cooldown rejected")
	_check(condition.ammunition_for("rocket").remaining == 99 and rocket.magazine.remaining == 100, "no double consumption or shared aggregate")
	var state: PlayerStateRecord = mapper.to_record(player).value
	EquipmentConditionCapture.apply(state, condition.snapshot())
	player = mapper.to_domain(state).value
	rocket = player.vehicle.loadout.at(13)
	_check(rocket.magazine.remaining == 99, "ammo persist round trip")
	var quote := PlayerAmmunitionActions.preview(player, "rocket", items.maintenance_rules)
	_check(quote.is_ok and quote.value.currency == 1, "original one coin per rocket")
	var revision := player.inventory.revision
	_check(PlayerAmmunitionActions.refill(player, "rocket", revision, items.maintenance_rules).is_ok, "refill")
	_check(rocket.magazine.remaining == 100 and player.inventory.currency == 99999, "exact refill and fee")
	_check(not PlayerAmmunitionActions.refill(player, "rocket", revision, items.maintenance_rules).is_ok, "replay rejected")
	_check(not PlayerAmmunitionActions.preview(player, "rocket", items.maintenance_rules).is_ok, "full rejected")
	rocket.magazine.remaining = 0
	player.map_id = "d03_field_zone"
	_check(not PlayerAmmunitionActions.preview(player, "rocket", items.maintenance_rules).is_ok, "field refill rejected")
	player.map_id = "yian_harbor_hall_floor_1"
	rocket.locked = true
	_check(not PlayerAmmunitionActions.preview(player, "rocket", items.maintenance_rules).is_ok, "locked rejected")
	rocket.locked = false
	player.inventory.currency = 0
	_check(not PlayerAmmunitionActions.refill(player, "rocket", player.inventory.revision, items.maintenance_rules).is_ok and rocket.magazine.remaining == 0, "unaffordable no refill")
	var empty_loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	module.refresh_achievement_loadout(player.entity_id, empty_loadout)
	module.advance_ticks(60, false)
	intent.input_sequence = 3
	var before: float = actor.vehicle_state.working_energy
	var empty := module.handle_weapon_attack(player.entity_id, intent)
	_check(not empty.is_ok and empty.error_code == &"ammunition.empty" and actor.vehicle_state.working_energy == before, "empty magazine cannot fire or spend energy")
	var enhanced := items.create("starter_rocket_launcher", {"instance_id": "enhanced", "processing": {"version": 1, "increments": {"ammunition_capacity": 10}}, "magazine": {"remaining": 3}})
	_check(enhanced.is_ok and enhanced.value.ammunition_capacity() == 110 and enhanced.value.magazine.remaining == 3, "capacity processing preserves rounds")
	_check(not items.create("starter_missile", {"instance_id": "bad", "magazine": {"remaining": 1000}}).is_ok, "overcapacity rejected")
	for raw: Variant in [{"remaining": -2}, {"remaining": 2.5}, {"remaining": INF}, []]:
		_check(not WeaponMagazine.restore(raw).is_ok, "malformed state rejected")
	print("Equipment ammunition: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言。
## [param condition] 结果。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
