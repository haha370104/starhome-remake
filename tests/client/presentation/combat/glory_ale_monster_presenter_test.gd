extends SceneTree

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")
const PresentationCatalogScript := preload(
	"res://scripts/content/glory_monster_presentation_catalog.gd"
)
const PresenterScript := preload(
	"res://scripts/client/presentation/combat/ale_combat_visual_presenter.gd"
)
const DeathEffectsScript := preload(
	"res://scripts/client/presentation/combat/monster_death_effect_controller.gd"
)
const AttackEffectsScript := preload(
	"res://scripts/client/presentation/combat/monster_attack_effect_controller.gd"
)

var failures := PackedStringArray()
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	var packs = PackCatalogScript.new()
	_expect(packs.load_file("res://data/content/glory_sprite_content_packs_v1.json"), "精灵包目录应可读")
	_expect(packs.mount_all(false), "精灵包应可挂载")
	var palette_packs = PackCatalogScript.new()
	_expect(palette_packs.load_file("res://data/content/glory_monster_palette_content_pack_v1.json"), "怪物调色板包目录应可读")
	_expect(palette_packs.mount_all(false), "怪物调色板包应可挂载")
	var repository = RepositoryScript.new()
	_expect(repository.load_default(), "ALE 仓储应加载")
	var catalog = PresentationCatalogScript.new()
	_expect(catalog.load_default(), "119 条怪物表现目录应加载")
	_expect(catalog.size() == 119, "怪物表现目录数量应为 119")
	var cold_gel_definition: Dictionary = catalog.definition_for_actor("glory_npc_005")
	_expect(String(cold_gel_definition.get("actions", {}).get("move", "")).begins_with("monster_palettes/"), "外置 ACT 变种应指向调色板运行包")
	var cold_gel_animation: Dictionary = repository.load_animation(String(cold_gel_definition["actions"]["move"]))
	_expect(not cold_gel_animation.is_empty(), "低温毒胶 ACT 变种应可惰性加载")
	var definition: Dictionary = catalog.definition_for_actor("glory_npc_128")
	_expect(not definition.is_empty(), "非首切 BOSS 应具备 ALE 表现定义")
	var presenter = PresenterScript.new()
	root.add_child(presenter)
	_expect(presenter.configure(repository, "glory_npc_128", definition) == OK, "BOSS 身体和阴影应从包中惰性加载")
	var body := presenter.get_node_or_null("Body") as Sprite2D
	var shadow := presenter.get_node_or_null("Shadow") as Sprite2D
	_expect(body != null and body.texture is AtlasTexture, "身体应显示包内 AtlasTexture")
	_expect(shadow != null and shadow.visible and shadow.texture is AtlasTexture, "源表阴影应随身体合成")
	var east_texture := body.texture
	presenter.set_direction(4)
	_expect(body.texture != east_texture, "八方向切换应选择另一组 ALE 帧")
	_expect(presenter.set_action(&"attack"), "攻击状态应消费 npcinfo 第三套动画")
	presenter.advance(0.2)
	_expect(presenter.current_action_id == &"attack", "攻击状态应持续到权威快照切换")
	var death_effects = DeathEffectsScript.new()
	root.add_child(death_effects)
	_expect(death_effects.configure({"monster_effects": {}}, presenter) == OK, "死亡特效控制器应配置")
	death_effects.configure_glory(repository, catalog)
	_expect(death_effects.present_death("boss.128", "glory_npc_128", Vector2.ZERO, 1), "BOSS 死亡 ALE 应播放")
	_expect(death_effects.active_effect_count() == 1, "生成目录死亡特效应进入活动队列")
	var attack_effects = AttackEffectsScript.new()
	root.add_child(attack_effects)
	_expect(attack_effects.configure({"monster_effects": {}}, presenter) == OK, "攻击特效控制器应配置")
	attack_effects.configure_glory(repository, catalog)
	_expect(attack_effects.present_attack({
		"attack_id": "boss.128.attack.1",
		"attack_archetype": "ranged_projectile",
		"combat_actor_id": "glory_npc_128",
		"origin": [0.0, 0.0],
		"target_position": [300.0, 0.0],
		"projectile_speed": 416.666667,
	}), "BOSS 弹体 ALE 应播放")
	_expect(attack_effects.active_projectile_count() == 1, "生成目录弹体应进入活动队列")
	death_effects.queue_free()
	attack_effects.queue_free()
	presenter.queue_free()
	if failures.is_empty():
		print("GLORY_ALE_MONSTER_PRESENTER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
