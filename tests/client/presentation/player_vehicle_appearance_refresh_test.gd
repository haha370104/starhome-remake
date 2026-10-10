extends SceneTree

const CATALOG_PATH := "res://assets/characters/character_atlases.json"
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"


## 背包结算不重建战车图层；换装仍刷新真实外观。
func _initialize() -> void:
	var items := ItemCatalog.new()
	assert(items.initialize().is_ok)
	var character_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var avatar := PlayerWorldAvatar.new()
	root.add_child(avatar)
	assert(avatar.configure(
		CharacterFactory.build_character_set(character_catalog, "player"),
		manifest, "测试玩家", Color.WHITE, Vector2.ZERO,
	) == OK)
	var vehicle := PlayerVehicle.new({"vehicle_id": "appearance.test", "definition_id": "recruit_tank"})
	var chassis := items.create("glory_equipment_tank1000_27ae5e8059", {"instance_id": "chassis"})
	var cannon := items.create("glory_equipment_gun1000_c4c24e2500", {"instance_id": "cannon"})
	assert(chassis.is_ok and cannon.is_ok)
	assert(vehicle.loadout.restore(chassis.value).is_ok)
	assert(vehicle.loadout.restore(cannon.value).is_ok)
	assert(avatar.apply_vehicle_equipment(vehicle))
	var chassis_sprite: AnimatedSprite2D = avatar.combat_presenter._layers[&"chassis"]
	var weapon_sprite: AnimatedSprite2D = avatar.combat_presenter._layers[&"primary_weapon"]
	assert(avatar.apply_vehicle_equipment(vehicle))
	assert(avatar.combat_presenter._layers[&"chassis"] == chassis_sprite)
	assert(avatar.combat_presenter._layers[&"primary_weapon"] == weapon_sprite)
	var arm := items.create("glory_equipment_collector_ac947ee094", {"instance_id": "arm"})
	assert(arm.is_ok)
	assert(vehicle.loadout.equip(arm.value, 1, vehicle.loadout.revision).is_ok)
	assert(avatar.apply_vehicle_equipment(vehicle))
	assert(avatar.combat_presenter._layers[&"primary_weapon"] != weapon_sprite)
	print("PLAYER VEHICLE APPEARANCE REFRESH TEST PASSED")
	quit(0)
