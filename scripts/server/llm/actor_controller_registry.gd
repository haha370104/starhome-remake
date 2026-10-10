class_name ActorControllerRegistry
extends RefCounted

const DomainResultScript := preload("res://scripts/core/domain_result.gd")

var _controllers: Dictionary[String, LlmPlayerController] = {}
var _observation_policy: ObservationPolicy
var _configured := false


## 持有 actor 到控制器的唯一注册关系，以及 LLM 观察策略实例。
## 不持有会话、地图、玩家聚合或节点树；服务器负责生命周期和外部副作用。
func configure() -> DomainResult:
	_controllers.clear()
	_observation_policy = ObservationPolicy.new()
	_configured = true
	return DomainResultScript.ok(self)


func has_controller(actor_id: String) -> bool:
	return _controllers.has(actor_id)


func actor_ids() -> Array[String]:
	var identities: Array[String] = []
	for actor_id: String in _controllers:
		identities.append(actor_id)
	identities.sort()
	return identities


func controller_for(actor_id: String) -> LlmPlayerController:
	return _controllers.get(actor_id)


func observation_policy() -> ObservationPolicy:
	return _observation_policy


func register(
	actor_id: String,
	controller: LlmPlayerController,
	area_resolver: Callable,
	intent_sink: Callable,
	decision_provider: Variant,
	decision_delay_seconds := 0.0,
	decision_timeout_seconds := 180.0,
) -> DomainResult:
	if not _configured:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	if _controllers.has(actor_id):
		return DomainResultScript.failure(&"llm.already_registered", "actor already has an LLM controller")
	if actor_id.is_empty() or controller == null or not area_resolver.is_valid() \
			or not intent_sink.is_valid() or not (decision_provider is Callable or decision_provider is LlmProvider):
		return DomainResultScript.failure(
			&"llm.controller_invalid", "controller, area resolver, intent sink and provider are required"
		)
	var configured := controller.configure(
		actor_id,
		area_resolver,
		intent_sink,
		decision_provider,
		decision_delay_seconds,
		decision_timeout_seconds,
	)
	if not configured.is_ok:
		return configured
	_controllers[actor_id] = controller
	return DomainResultScript.ok(controller)


func unregister(actor_id: String) -> DomainResult:
	if not _controllers.has(actor_id):
		return DomainResultScript.failure(&"llm.not_registered", "actor has no LLM controller")
	_controllers.erase(actor_id)
	return DomainResultScript.ok()
