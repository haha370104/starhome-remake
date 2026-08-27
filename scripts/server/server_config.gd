class_name DedicatedServerConfig
extends RefCounted

const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const DEFAULT_MAP_CONFIG := "res://data/maps/yian_harbor_hall_floor_1.json"
const DEFAULT_MAP_CATALOG := "res://data/maps/map_directory.json"

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


## Performs the `from_command_line` operation.
## [param arguments] Input value consumed by the operation.
## Returns the result produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
static func from_command_line(arguments: PackedStringArray) -> DedicatedServerConfig:
	var config := DedicatedServerConfig.new()
	for argument in arguments:
		if argument == "--no-network":
			config.network_enabled = false
		elif argument == "--smoke-test":
			config.smoke_test = true
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


## Validates the supplied state against the domain invariants.
## Returns the resulting string collection.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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
	return errors
