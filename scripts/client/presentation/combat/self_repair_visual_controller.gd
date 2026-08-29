class_name SelfRepairVisualController
extends Node

const ENERGY_FIELD_FRAMES := preload(
	"res://assets/equipment_world/shared/self_repair/energy_field/animation_frames.tres"
)
const GROUND_SHADOW_FRAMES := preload(
	"res://assets/equipment_world/shared/self_repair/ground_shadow/animation_frames.tres"
)
const ENERGY_FIELD_OFFSET := Vector2(-10.0, -32.0)
const GROUND_SHADOW_OFFSET := Vector2(-38.0, 25.0)

var _energy_field: AnimatedSprite2D
var _ground_shadow: AnimatedSprite2D
var _active := false


## 在玩家战车节点上创建荣耀版自维修能量场和地面阴影两层表现。
## [param actor] 当前本地玩家的世界表现根节点。
## 返回是否完成绑定；空节点返回 ERR_INVALID_PARAMETER。
## 设计：两层只观察权威快照，不参与维修周期、回血或能耗计算。
func configure(actor: Node2D) -> Error:
	if actor == null:
		return ERR_INVALID_PARAMETER
	_ground_shadow = _create_layer(
		"SelfRepairGroundShadow", GROUND_SHADOW_FRAMES, GROUND_SHADOW_OFFSET, -1
	)
	actor.add_child(_ground_shadow)
	_energy_field = _create_layer(
		"SelfRepairEnergyField", ENERGY_FIELD_FRAMES, ENERGY_FIELD_OFFSET, 40
	)
	actor.add_child(_energy_field)
	return OK


## 根据最新战车资源快照启动或停止自维修循环动画。
## [param vehicle_snapshot] 服务端投影的 local_vehicle 字典。
func apply_snapshot(vehicle_snapshot: Dictionary) -> void:
	var next_active := bool(vehicle_snapshot.get("self_repair_active", false))
	if next_active == _active:
		return
	_active = next_active
	_set_layer_active(_ground_shadow, _active)
	_set_layer_active(_energy_field, _active)


## 创建一个保持 ALE 脚点偏移的维修动画层。
## [param layer_name] 业务语义节点名。
## [param frames] 已按公共画布归一化的荣耀 SpriteFrames。
## [param anchor_offset] 公共画布左上角相对战车脚点的偏移。
## [param z_index] 相对战车的绘制层级。
## 返回默认隐藏且不会拦截输入的动画节点。
func _create_layer(
	layer_name: String,
	frames: SpriteFrames,
	anchor_offset: Vector2,
	z_index: int,
) -> AnimatedSprite2D:
	var layer := AnimatedSprite2D.new()
	layer.name = layer_name
	layer.sprite_frames = frames
	layer.animation = &"repair"
	layer.centered = false
	layer.position = anchor_offset
	layer.z_index = z_index
	layer.visible = false
	return layer


## 同步单个表现层的可见性和循环播放状态。
## [param layer] 待更新的动画节点。
## [param active] 是否处于服务器确认的自维修状态。
func _set_layer_active(layer: AnimatedSprite2D, active: bool) -> void:
	if layer == null:
		return
	layer.visible = active
	if active:
		layer.play(&"repair")
	else:
		layer.stop()
		layer.frame = 0
