extends SceneTree

const ControllerScript := preload("res://scripts/server/llm/llm_player_controller.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var registry := ActorControllerRegistry.new()
	_check(registry.controller_for("actor.missing") == null, "未配置 registry 不应返回控制器")
	_check(not registry.has_controller("actor.missing"), "未配置 registry 不应报告控制器存在")
	_check(not registry.unregister("actor.missing").is_ok, "未注册 actor 应拒绝注销")
	_check(registry.configure().is_ok, "registry 应完成初始化")
	_check(registry.observation_policy() != null, "registry 应持有唯一观察策略")

	var resolver := func(_area_id: String, _observation: Dictionary) -> DomainResult:
		return DomainResult.ok({
			"map_instance_id": "map.instance.1",
			"target_position": Vector2.ZERO,
		})
	var sink := func(_intent: PlayerIntent) -> DomainResult:
		return DomainResult.ok()
	var provider := func(_observation: Dictionary) -> LlmToolCall:
		return LlmToolCall.new("wait")
	var controller: LlmPlayerController = ControllerScript.new()
	var registered := registry.register("actor.one", controller, resolver, sink, provider)
	_check(registered.is_ok, "registry 应注册有效控制器")
	_check(registry.has_controller("actor.one") and registry.controller_for("actor.one") == controller,
		"registry 应按 actor 返回同一个控制器")
	var duplicate_controller: LlmPlayerController = ControllerScript.new()
	var duplicate := registry.register("actor.one", duplicate_controller, resolver, sink, provider)
	_check(not duplicate.is_ok and duplicate.error_code == &"llm.already_registered",
		"registry 应拒绝重复控制器")
	var invalid := registry.register("actor.invalid", null, resolver, sink, provider)
	_check(not invalid.is_ok and invalid.error_code == &"llm.controller_invalid",
		"registry 应拒绝无效控制器")
	_check(registry.unregister("actor.one").is_ok, "registry 应注销已有控制器")
	_check(not registry.has_controller("actor.one"), "注销后 actor 不应继续占有控制器")
	controller.free()
	duplicate_controller.free()

	for failure: String in failures:
		push_error(failure)
	print("ACTOR_CONTROLLER_REGISTRY_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
