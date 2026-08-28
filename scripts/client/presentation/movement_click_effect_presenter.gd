class_name MovementClickEffectPresenter
extends Node2D

const EFFECT_FRAMES := preload(
	"res://assets/ui/world_feedback/movement_destination/animation_frames.tres"
)
const EFFECT_ANIMATION := &"play"
const EFFECT_OFFSET := Vector2(0.5, 1.5)

var last_presented_position := Vector2.INF


## 在用户实际点击的世界坐标播放一次荣耀版右键落点动画。
## [param world_position] 未经寻路修正的鼠标世界坐标。
## 返回本次创建并已开始播放的动画节点。
## 设计：每次点击创建独立实例，使连续点击能像原客户端一样同时保留各自的短动画。
func present(world_position: Vector2) -> AnimatedSprite2D:
	var effect := AnimatedSprite2D.new()
	effect.name = "MovementClickEffect"
	effect.sprite_frames = EFFECT_FRAMES
	effect.animation = EFFECT_ANIMATION
	effect.centered = true
	effect.offset = EFFECT_OFFSET
	effect.position = world_position
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.animation_finished.connect(effect.queue_free)
	add_child(effect)
	last_presented_position = world_position
	effect.play()
	return effect


## 清除仍在播放的旧地图落点动画。
func clear_effects() -> void:
	for child: Node in get_children():
		child.queue_free()
	last_presented_position = Vector2.INF


## 统计当前仍在播放的落点动画。
## 返回活动动画节点数量，供表现回归与诊断使用。
func active_effect_count() -> int:
	return get_child_count()


## 查询所导入荣耀版落点动画的帧数。
## 返回动画资源中的帧数，供资源完整性回归使用。
func frame_count() -> int:
	return EFFECT_FRAMES.get_frame_count(EFFECT_ANIMATION)
