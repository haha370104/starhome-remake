extends SceneTree

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")

var failures: PackedStringArray = []
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	_expect(bool(RuntimeContentBootstrap.mount_default().get("ok", false)), "恢复内容包与默认内容包应能一起挂载")
	var packs = PackCatalogScript.new()
	_expect(
		packs.load_file("res://data/content/glory_sprite_content_packs_v1.json"),
		"精灵内容包目录应有效：%s" % "; ".join(packs.errors),
	)
	_expect(packs.pack_ids().size() == 3, "裁剪应保留现有精灵包入口")
	_expect(packs.mount_all(false), "精灵包应可挂载：%s" % "; ".join(packs.errors))
	var repository = RepositoryScript.new()
	_expect(repository.load_default(), "ALE 索引应有效：%s" % "; ".join(repository.errors))
	_expect(repository.size() == 2339, "仓储应只登记当前运行配置引用的动画")
	_expect(repository.resolve("spaceplayer/pic/space_destroy/01").is_empty(), "未接入的原版界面应移出运行包")
	var recovered: Array = JsonConfigLoader.load_dictionary(RepositoryScript.DEFAULT_RECOVERED_INDEX_PATH).value.sprites
	for row: Dictionary in recovered:
		var restored: Dictionary = repository.load_animation(row.logical_id)
		_expect(restored.get("source_release") == row.source_release, "跨版本恢复不能冒充荣耀来源")
		_expect(restored.get("frames", []).size() == int(row.frame_count), "恢复的背包、面板、世界帧均可加载")
	_expect(repository.resolve("pic3/equip/body/monarchtank").frames_path != repository.resolve("pic2/equip/body/monarchtank").frames_path, "已存在的荣耀帝王不能被千级帝王替换")
	var adult := repository.resolve("../monster_palettes/om_adult_standard/move.ale")
	_expect(not adult.is_empty(), "应按相对路径解析当前奥姆虫调色板动画")
	var animation := repository.load_animation(
		"../monster_palettes/om_adult_standard/move.ale"
	)
	_expect(not animation.is_empty(), "奥姆虫动画应能从包内加载")
	if not animation.is_empty():
		_expect(animation["frames"].size() == int(adult["frame_count"]), "帧数量必须匹配索引")
		_expect(animation["frames"][0]["texture"] is AtlasTexture, "动画帧应引用包内图集")
		_expect(animation["frames"][0]["size"].x > 0.0, "动画帧尺寸必须为正")
	var bare := repository.resolve("130-1.ale", "pic3/npc")
	_expect(not bare.is_empty() and String(bare["logical_id"]).begins_with("pic3/npc/"), "NPC 裸文件名应按前缀解析")
	_expect(repository.resolve("missing.ale").is_empty(), "未知 ALE 不得产生伪资源")
	if failures.is_empty():
		print("GLORY_ALE_SPRITE_REPOSITORY_OK (%d assertions)" % assertions)
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
