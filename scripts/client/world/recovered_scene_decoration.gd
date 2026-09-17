extends Node2D

const CATALOG_PATH := "res://data/presentation/recovered_scene_decorations_v1.json"

var _textures: Array[Texture2D] = []
var _origins: Array[Vector2] = []
var _sprite := Sprite2D.new()
var _elapsed := 0.0
var _fps := 10.0


## 从受控表现表为指定地图暂存找回的场景动画，不重复创建已有传送点。
## [param map_id] 即将提交的地图标识。
## [param container] 离树暂存容器；失败时由活动世界统一销毁。
## [param output] 随地图提交和清理的场景节点集合。
## 返回所有声明的动画是否成功创建；失败不改变当前地图。
static func stage(map_id: StringName, container: Node2D, output: Array[Node2D]) -> bool:
	var loaded := JsonConfigLoader.load_dictionary(CATALOG_PATH)
	if not loaded.is_ok:
		return false
	var rows: Array = loaded.value.get("maps", {}).get(String(map_id), [])
	if rows.is_empty():
		return true
	var repository := AleSpriteRepository.new()
	if not repository.load_default():
		return false
	for row: Dictionary in rows:
		var decoration = load("res://scripts/client/world/recovered_scene_decoration.gd").new()
		if not decoration.configure(row, repository):
			decoration.free()
			return false
		container.add_child(decoration)
		output.append(decoration)
	return true


## 校验表现数据并按原 ALE 帧与原点构造动画。
## [param row] 本地表现表中的锚点、帧间隔和精确素材引用。
## [param repository] 已加载索引的只读素材仓储。
## 返回配置是否有效。
func configure(row: Dictionary, repository: AleSpriteRepository) -> bool:
	var anchor: Array = row.get("anchor", [])
	var interval := float(row.get("frame_duration_ms", 0.0))
	if anchor.size() != 2 or interval <= 0.0:
		return false
	var animation := repository.load_animation(String(row.get("ale_reference", "")))
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return false
	for frame: Dictionary in frames:
		_textures.append(frame.texture)
		_origins.append(frame.origin)
	name = String(row.get("id", "RecoveredDecoration"))
	position = Vector2(float(anchor[0]), float(anchor[1]))
	_fps = 1000.0 / interval
	_sprite.name = "Animation"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_process(0.0)
	return true


## 按原版时间间隔循环完整动画，每帧同步尺寸对应的原点。
## [param delta] 距离上帧的秒数。
func _process(delta: float) -> void:
	if _textures.is_empty():
		return
	_elapsed = fmod(_elapsed + delta, float(_textures.size()) / _fps)
	var index := mini(int(_elapsed * _fps), _textures.size() - 1)
	_sprite.texture = _textures[index]
	_sprite.position = _origins[index]
