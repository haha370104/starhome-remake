class_name DedicatedServerConfig
extends RefCounted

const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const DEFAULT_MAP_CONFIG := "res://data/maps/yian_harbor_hall_floor_1.json"
const DEFAULT_MAP_CATALOG := "res://data/maps/map_directory.json"
const DEFAULT_PLAYER_STATE_STORE := "user://server/player_states.json"

var listen_address := "*"
var port := 24680
var max_clients := 16
var simulation_hz := 20
var snapshot_hz := 10
var reconnect_grace_seconds := 30.0
var default_movement_speed := 203.0
var dynamic_blocking_enabled := true
var dynamic_blocking_radius := 18.0
var map_transition_radius := 72.0
var default_spawn := Vector2(730.0, 1330.0)
var map_config_path := DEFAULT_MAP_CONFIG
var map_catalog_path := DEFAULT_MAP_CATALOG
var protocol_version := Protocol.PROTOCOL_VERSION
var content_version := Protocol.PUBLIC_CONTENT_VERSION
var network_enabled := true
var smoke_test := false
var persistence_enabled := true
var player_state_store_path := DEFAULT_PLAYER_STATE_STORE
var autosave_interval_seconds := 3.0


## 加载并校验 `from_command_line` 对应的模块状态。
## [param arguments] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
static func from_command_line(arguments: PackedStringArray) -> DedicatedServerConfig:
	var config := DedicatedServerConfig.new()
	for argument in arguments:
		if argument == "--no-network":
			config.network_enabled = false
		elif argument == "--smoke-test":
			config.smoke_test = true
		elif argument == "--disable-persistence":
			config.persistence_enabled = false
		elif argument.begins_with("--player-state-store="):
			config.player_state_store_path = argument.trim_prefix("--player-state-store=")
		elif argument.begins_with("--autosave-interval-seconds="):
			config.autosave_interval_seconds = float(
				argument.trim_prefix("--autosave-interval-seconds=")
			)
		elif argument.begins_with("--listen-address="):
			config.listen_address = argument.trim_prefix("--listen-address=")
		elif argument.begins_with("--port="):
			config.port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--max-clients="):
			config.max_clients = int(argument.trim_prefix("--max-clients="))
		elif argument.begins_with("--reconnect-grace-seconds="):
			config.reconnect_grace_seconds = float(
				argument.trim_prefix("--reconnect-grace-seconds=")
			)
		elif argument.begins_with("--movement-speed="):
			config.default_movement_speed = float(argument.trim_prefix("--movement-speed="))
		elif argument == "--disable-dynamic-blocking":
			config.dynamic_blocking_enabled = false
		elif argument.begins_with("--dynamic-blocking-radius="):
			config.dynamic_blocking_radius = float(
				argument.trim_prefix("--dynamic-blocking-radius=")
			)
		elif argument.begins_with("--map-transition-radius="):
			config.map_transition_radius = float(
				argument.trim_prefix("--map-transition-radius=")
			)
		elif argument.begins_with("--map-config="):
			config.map_config_path = argument.trim_prefix("--map-config=")
		elif argument.begins_with("--map-catalog="):
			config.map_catalog_path = argument.trim_prefix("--map-catalog=")
	return config


## 执行 `validation_errors` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if port < 0 or port > 65535:
		errors.append("port must be between 0 and 65535")
	if max_clients <= 0:
		errors.append("max_clients must be positive")
	if simulation_hz <= 0 or snapshot_hz <= 0 or snapshot_hz > simulation_hz:
		errors.append("tick rates must satisfy simulation_hz >= snapshot_hz > 0")
	elif simulation_hz % snapshot_hz != 0:
		errors.append("simulation_hz must be divisible by snapshot_hz")
	if reconnect_grace_seconds < 0.0:
		errors.append("reconnect_grace_seconds cannot be negative")
	if default_movement_speed <= 0.0:
		errors.append("default_movement_speed must be positive")
	if dynamic_blocking_radius <= 0.0:
		errors.append("dynamic_blocking_radius must be positive")
	if map_transition_radius <= 0.0:
		errors.append("map_transition_radius must be positive")
	if map_config_path.is_empty():
		errors.append("map_config_path cannot be empty")
	if map_catalog_path.is_empty():
		errors.append("map_catalog_path cannot be empty")
	if persistence_enabled and player_state_store_path.is_empty():
		errors.append("player_state_store_path cannot be empty when persistence is enabled")
	if autosave_interval_seconds <= 0.0:
		errors.append("autosave_interval_seconds must be positive")
	return errors
