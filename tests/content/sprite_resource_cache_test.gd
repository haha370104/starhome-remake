extends SceneTree

const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")

var failures: PackedStringArray = []
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var repository = RepositoryScript.new()
	repository.configure_cache_budget(2500)
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var first := ImageTexture.create_from_image(image)
	var second := ImageTexture.create_from_image(image)
	repository.cache_page("fixture:first", first)
	_expect(repository.cached_page("fixture:first") == first, "首次写入的图集页应可命中")
	repository.cache_page("fixture:second", second)
	_expect(repository.cached_page("fixture:first") == null, "超出预算时应优先淘汰最旧未固定页")
	_expect(repository.cached_page("fixture:second") == second, "最新图集页应保留")
	var after_eviction: Dictionary = repository.cache_stats()
	_expect(int(after_eviction.evictions) >= 1, "缓存淘汰次数应记录")
	repository.cache_page("fixture:first", first)
	var after_reload: Dictionary = repository.cache_stats()
	_expect(int(after_reload.reloads) >= 1, "被淘汰页再次加载应记录重新加载")
	repository.retain_page("fixture:pinned")
	repository.cache_page("fixture:pinned", first)
	repository.configure_cache_budget(1)
	_expect(repository.cached_page("fixture:pinned") == first, "固定引用不得因预算淘汰")
	repository.release_page("fixture:pinned")
	_expect(repository.cached_page("fixture:pinned") == null, "释放固定引用后应允许淘汰")
	var final_stats: Dictionary = repository.cache_stats()
	_expect(int(final_stats.hits) >= 3, "缓存命中次数应记录")
	_expect(int(final_stats.misses) >= 3, "缓存未命中次数应记录")
	if failures.is_empty():
		print("SPRITE_RESOURCE_CACHE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
