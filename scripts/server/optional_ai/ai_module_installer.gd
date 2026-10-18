extends RefCounted


## 仅由显式开关动态加载，配置失败不阻塞普通游戏启动。
## [param server] 完成初始化的服务器。[param config_path] 明确选择的配置路径。
## 返回模块节点或失败结果。
static func install(server: AuthoritativeServer, config_path: String) -> DomainResult:
	if server.get_node_or_null("OptionalAiPlayers") != null: return DomainResult.failure(&"ai.already_installed", "AI模块已安装")
	if server.autosave_service == null: return DomainResult.failure(&"ai.persistence_required", "AI玩家需要启用角色存档")
	var loaded := AiPlayerSettings.load_file(config_path)
	if not loaded.is_ok: return loaded
	var settings: AiPlayerSettings = loaded.value
	if settings.provider == "responses" and OS.get_environment(settings.api_key_env).strip_edges().is_empty():
		return DomainResult.failure(&"ai.key_missing", "AI密钥环境变量为空")
	var provider: AiDecisionProvider
	if settings.provider == "demo": provider = AiDemoProvider.new()
	else:
		var responses := AiResponsesProvider.new()
		responses.configure(settings)
		provider = responses
	var module := AiPlayerModule.new()
	module.name = "OptionalAiPlayers"
	module.configure(settings, AiAuthorityAdapter.new(server, settings.observation_radius), provider)
	server.add_child(module)
	return DomainResult.ok(module)
