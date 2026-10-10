class_name ItemPresentationTextureResolver
extends RefCounted

## 将业务表现定义解析为贴图、ALE 原点和原生尺寸；旧 PNG 路径仍原样兼容。
## [param presentation] 调用方传入的 `presentation` 参数。
## 返回该函数计算、查询或操作得到的结果。
static func resolve(presentation: Dictionary) -> Dictionary:
	var texture_path := String(presentation.get(
		"icon", presentation.get("dialog_texture", presentation.get("texture", ""))
	))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var texture := ResourceLoader.load(texture_path, "Texture2D") as Texture2D
		if texture != null:
			return {"texture": texture, "origin": Vector2.ZERO, "size": texture.get_size()}
	var ale_reference := String(presentation.get("ale_reference", "")).strip_edges()
	if ale_reference.is_empty() or not SpriteResources.prepare():
		return {}
	return SpriteResources.repository().load_frame(ale_reference, int(presentation.get("frame", 0)))


## 在场景启动时准备共享图集索引及异步队列。
static func prepare() -> void:
	SpriteResources.prepare()


## 请求或预取背包图标，复用世界表现的共享加载队列。
## [param presentation] 图标定义。[param callback] 可选主线程回调。
static func request(presentation: Dictionary, callback: Callable = Callable()) -> void:
	SpriteResources.request(presentation, callback)
