extends SceneTree

const BootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")
const CatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const MapLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")

var failures := PackedStringArray()
var assertions := 0


## 验证所有地图分类与种群覆盖，并抽样真正的服务端出生及补充。
func _initialize() -> void:
	if not BootstrapScript.mount_default().ok:
		push_error("荣耀内容包挂载失败")
		quit(1)
		return
	var loaded = CatalogScript.load_default()
	_expect(loaded.is_ok, "怪物目录必须可加载")
	if not loaded.is_ok:
		_finish()
		return
	var catalog = loaded.value
	var directory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/glory_map_directory_v1.json"))
	var field_count := 0
	for map_id: String in directory["definitions"]:
		var definition = MapLoaderScript.new().load_file(directory["definitions"][map_id])
		_expect(definition != null, "%s 地图定义应有效" % map_id)
		if definition == null:
			continue
		var population = catalog.monster_lifecycles_for_map(map_id, map_id + ".test")
		_expect(population.is_ok, "%s 种群应可生成" % map_id)
		if not population.is_ok:
			continue
		if definition.category != &"field":
			_expect(population.value.is_empty(), "%s 非野外不能刷怪" % map_id)
			continue
		field_count += 1
		_expect(population.value.size() == 100, "%s 初始数量必须为 100" % map_id)
		var counts := {}
		for monster: Dictionary in population.value:
			counts[monster["species_id"]] = int(counts.get(monster["species_id"], 0)) + 1
			_expect(monster["map_instance_id"] == map_id + ".test", "怪物必须属于当前地图实例")
			_expect(not Vector2(monster["position"]).is_finite(), "目录不能强行指定固定刷怪簇")
		var amounts: Array = counts.values()
		_expect(int(amounts.max()) - int(amounts.min()) <= 1, "%s 等权种群数量差不超过一只" % map_id)
		_expect(catalog.monster_replenishment_count(map_id, 49) == 20, "少于50只补20只")
		_expect(catalog.monster_replenishment_count(map_id, 79) == 10, "少于80只补10只")
		_expect(catalog.monster_replenishment_count(map_id, 99) == 1, "补量不能突破100只")
	_expect(field_count == 460, "运行定义应包含460张野外图")
	_expect(catalog.monster_encounter_map_ids().size() == field_count, "刷怪目录不能缺图或混入城镇")
	for map_id: String in ["buli_c04_field_zone", "glory_nft_bl_c08", "glory_nft_bt_c04", "glory_nft_btb_c04", "glory_nft_ds_c04", "glory_nft_pl_c04", "glory_nft_sk_c04"]:
		_check_authoritative_spawn(catalog, directory["definitions"][map_id])
	_finish()


## 抽样真实导航出生、地图范围分散和一分钟权威补怪。
## [param catalog] 已校验的共享怪物目录。
## [param definition_path] 当前地图定义资源路径。
func _check_authoritative_spawn(catalog, definition_path: String) -> void:
	var instance = MapInstanceScript.new()
	_expect(instance.load_map(definition_path).ok, "抽样地图导航应可加载")
	var configured: Dictionary = instance.configure_combat(catalog, 20)
	_expect(configured.ok, "抽样地图应完成权威种群初始化：%s" % configured)
	if not configured.ok:
		return
	_expect(instance.combat_module.monsters.size() == 100, "实际服务端应生成100只怪物")
	var buckets := {}
	var removed_ids: Array[String] = []
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		_expect(monster.map_instance_id == instance.instance_id, "实际怪物不能串图")
		_expect(instance.navigation.is_walkable(monster.position), "出生点必须可走")
		var relative: Vector2 = monster.position / instance.definition.world_size
		buckets[Vector2i(floori(relative.x * 4), floori(relative.y * 4))] = true
		if removed_ids.size() < 60:
			removed_ids.append(monster.monster_id)
	_expect(buckets.size() >= 5, "出生点应跨越多个地图分区而不是集中在固定点")
	for monster_id: String in removed_ids:
		instance.combat_module.monsters.erase(monster_id)
	instance.combat_module.current_tick = 1199
	instance._replenish_monster_population_if_due()
	_expect(instance.combat_module.monsters.size() == 40, "不足一分钟不能提前补怪")
	instance.combat_module.current_tick = 1200
	instance._replenish_monster_population_if_due()
	_expect(instance.combat_module.monsters.size() == 60, "一分钟时低于50%应补20只")
	instance._replenish_monster_population_if_due()
	_expect(instance.combat_module.monsters.size() == 60, "同一时刻不能重复补怪")


## 记录测试断言。
## [param condition] 是否满足预期。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总断言并设置退出码。
func _finish() -> void:
	if failures.is_empty():
		print("GLORY_FIELD_POPULATION_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
