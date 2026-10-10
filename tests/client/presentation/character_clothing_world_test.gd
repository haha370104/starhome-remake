extends SceneTree

const CATALOG_PATH := "res://assets/characters/character_atlases.json"
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"


## 验证无袖衫使用已导入的荣耀人物外观，卸下时隐藏服装层。
func _initialize() -> void:
	var items := ItemCatalog.new()
	assert(items.initialize().is_ok)
	var shirt_result := items.create("male_sleeveless_shirt", {"instance_id": "shirt"})
	assert(shirt_result.is_ok)
	var shirt := shirt_result.value as Clothing
	var character_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var combat_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var avatar := PlayerWorldAvatar.new()
	root.add_child(avatar)
	assert(avatar.configure(
		CharacterFactory.build_character_set(character_catalog, "player"),
		combat_manifest, "测试人物", Color.WHITE, Vector2.ZERO,
	) == OK)

	var equipment := CharacterEquipment.new()
	assert(equipment.restore(shirt).is_ok)
	assert(avatar.apply_character_equipment(equipment, character_catalog))
	assert(avatar.human_character.equipment.visible)
	var frames: SpriteFrames = avatar.human_character.equipment.sprite_frames
	assert(frames.get_frame_texture(&"stand_6", 0).get_size().x > 0)
	assert(avatar.apply_character_equipment(equipment, character_catalog))
	assert(avatar.human_character.equipment.sprite_frames == frames)

	assert(equipment.unequip("upper_body").is_ok)
	assert(avatar.apply_character_equipment(equipment, character_catalog))
	assert(not avatar.human_character.equipment.visible)
	print("CHARACTER CLOTHING WORLD TEST PASSED")
	quit(0)
