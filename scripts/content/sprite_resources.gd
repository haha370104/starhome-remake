class_name SpriteResources
extends RefCounted

static var _repository: AleSpriteRepository
static var _queue: SpriteResourceQueue
static var _initialized := false


## 在主线程创建共享仓储和队列，所有消费者复用相同图集缓存。
## 返回是否有可用的受控资源索引。
static func prepare() -> bool:
	if not _initialized:
		_initialized = true
		if not bool(RuntimeContentBootstrap.mount_default().get("ok", false)): return false
		var loaded := AleSpriteRepository.new()
		if loaded.load_default(): _repository = loaded
	if _repository == null: return false
	if not is_instance_valid(_queue):
		_queue = SpriteResourceQueue.new()
		_queue.name = "SpriteResourceQueue"
		_queue.repository = _repository
		var tree := Engine.get_main_loop() as SceneTree
		tree.root.add_child.call_deferred(_queue)
	return true


## 取得主线程共享仓储；缓存由资源加载层统一维护。
## 返回已初始化仓储或空值。
static func repository() -> AleSpriteRepository:
	prepare()
	return _repository


## 请求或预取单帧图标，回调不等待磁盘。
## [param presentation] 表现定义。[param callback] 可选消费回调。
static func request(presentation: Dictionary, callback: Callable = Callable()) -> void:
	if prepare(): _queue.request(presentation, callback)


## 请求或预取完整 ALE 动画。
## [param asset_reference] 原始引用。[param prefix] 消歧前缀。[param callback] 可选消费回调。
static func request_animation(asset_reference: String, prefix: String, callback: Callable = Callable()) -> void:
	if prepare(): _queue.request_animation(asset_reference, prefix, callback)


## 请求已经物化的动画资源。
## [param path] SpriteFrames 路径。[param callback] 可选消费回调。
static func request_frames(path: String, callback: Callable = Callable()) -> void:
	if prepare(): _queue.request_frames(path, callback)


static func configure_cache_budget(bytes: int) -> void:
	if prepare(): _repository.configure_cache_budget(bytes)


static func cache_stats() -> Dictionary:
	if not prepare() or _repository == null:
		return {}
	return _repository.cache_stats()


static func set_active_map_references(references: Array, preferred_prefix := "") -> void:
	if prepare(): _repository.set_active_map_references(references, preferred_prefix)


static func clear_active_map_references() -> void:
	if _repository != null: _repository.clear_active_map_references()
