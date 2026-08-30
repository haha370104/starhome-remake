extends SceneTree

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")
const PresentationCatalogScript := preload(
	"res://scripts/content/glory_monster_presentation_catalog.gd"
)
const PresenterScript := preload(
	"res://scripts/client/presentation/combat/ale_combat_visual_presenter.gd"
)

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var packs = PackCatalogScript.new()
	_expect(packs.load_file("res://data/content/glory_sprite_content_packs_v1.json"), "精灵包目录应可读")
	_expect(packs.mount_all(false), "精灵包应可挂载")
	var repository = RepositoryScript.new()
	_expect(repository.load_default(), "ALE 仓储应加载")
	var catalog = PresentationCatalogScript.new()
	_expect(catalog.load_default(), "119 条怪物表现目录应加载")
	_expect(catalog.size() == 119, "怪物表现目录数量应为 119")
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
	presenter.queue_free()
	if failures.is_empty():
		print("GLORY_ALE_MONSTER_PRESENTER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
