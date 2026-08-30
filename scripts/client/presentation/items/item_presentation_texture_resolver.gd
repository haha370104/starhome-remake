class_name ItemPresentationTextureResolver
extends RefCounted

const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")
const RuntimeContentBootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")

static var _repository: RefCounted
static var _initialized := false


## 将业务表现定义解析为贴图、ALE 原点和原生尺寸；旧 PNG 路径仍原样兼容。
static func resolve(presentation: Dictionary) -> Dictionary:
	var texture_path := String(presentation.get(
		"icon", presentation.get("dialog_texture", presentation.get("texture", ""))
	))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var texture := ResourceLoader.load(texture_path, "Texture2D") as Texture2D
		if texture != null:
			return {"texture": texture, "origin": Vector2.ZERO, "size": texture.get_size()}
	var ale_reference := String(presentation.get("ale_reference", "")).strip_edges()
	if ale_reference.is_empty() or not _ensure_repository():
		return {}
	var animation: Dictionary = _repository.load_animation(ale_reference)
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return {}
	var frame_index := clampi(int(presentation.get("frame", 0)), 0, frames.size() - 1)
	var frame: Dictionary = frames[frame_index]
	return {
		"texture": frame["texture"],
		"origin": frame["origin"],
		"size": frame["size"],
		"logical_id": animation.get("logical_id", ""),
	}


static func _ensure_repository() -> bool:
	if _initialized:
		return _repository != null
	_initialized = true
	if not bool(RuntimeContentBootstrapScript.mount_default().get("ok", false)):
		return false
	var repository = RepositoryScript.new()
	if not repository.load_default():
		return false
	_repository = repository
	return true
