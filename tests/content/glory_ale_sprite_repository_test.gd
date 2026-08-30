extends SceneTree

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")

var failures: PackedStringArray = []
var assertions := 0


func _initialize() -> void:
	var packs = PackCatalogScript.new()
	_expect(
		packs.load_file("res://data/content/glory_sprite_content_packs_v1.json"),
		"精灵内容包目录应有效：%s" % "; ".join(packs.errors),
	)
	_expect(packs.pack_ids().size() == 3, "全量 ALE 应拆为三个精灵包")
	_expect(packs.mount_all(false), "精灵包应可挂载：%s" % "; ".join(packs.errors))
	var repository = RepositoryScript.new()
	_expect(repository.load_default(), "ALE 索引应有效：%s" % "; ".join(repository.errors))
	_expect(repository.size() == 13888, "ALE 索引数量不匹配")
	var adult := repository.resolve("../pic3/npc/CHN_2005_06_28_18_49_17_921.ale")
	_expect(not adult.is_empty(), "应按旧 FCC 相对路径解析奥姆虫移动动画")
	var animation := repository.load_animation(
		"../pic3/npc/CHN_2005_06_28_18_49_17_921.ale"
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


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
