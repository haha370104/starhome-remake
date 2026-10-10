class_name PersistenceCoordinator
extends RefCounted

const Result := preload("res://scripts/core/domain_result.gd")
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

var _autosave: AuthoritativeAutosaveService
var _repository: PlayerStateRepository
var _capture: Callable
var _configured := false


## 配置自动存档推进、状态采集和最终写盘端口。
## [param autosave] 在线玩家状态与检查点服务；持久化关闭时可为空。
## [param repository] 最终写盘仓储；持久化关闭时可为空。
## [param capture] 从权威地图和战斗状态采集瞬时事实。
func configure(
	autosave: AuthoritativeAutosaveService,
	repository: PlayerStateRepository,
	capture: Callable,
) -> DomainResult:
	if autosave != null and repository == null:
		return Result.failure(&"persistence.coordinator_repository_missing", "repository is required when autosave is enabled")
	if not capture.is_valid():
		return Result.failure(&"persistence.coordinator_capture_missing", "persistence capture port is required")
	_autosave = autosave
	_repository = repository
	_capture = capture
	_configured = true
	return Result.ok(self)


## 推进自动存档检查点并采集最新权威状态。
## [param elapsed_seconds] 本次模拟经过的时间。
## [param population_refresh_happened] 本帧是否发生重型世界刷新。
## 返回检查点状态或采集失败；失败保留自动存档 dirty 状态。
func advance(elapsed_seconds: float, population_refresh_happened: bool) -> DomainResult:
	if not _configured:
		return Result.failure(&"persistence.coordinator_unconfigured", "persistence coordinator is not configured")
	var capture_started_at := PerformanceTelemetryScript.begin(&"server_capture_persistence")
	if _autosave == null:
		PerformanceTelemetryScript.end(&"server_capture_persistence", capture_started_at)
		return Result.ok(false)
	var result := _autosave.advance(elapsed_seconds, _capture, population_refresh_happened)
	PerformanceTelemetryScript.end(&"server_capture_persistence", capture_started_at)
	return result


## 保存断线宽限期已结束的角色，随后由会话服务负责删除会话。
## [param identity] 已过期会话的角色身份。
## 返回采集或保存失败；成功时 value 为是否执行了保存。
func save_expired_player(identity: String) -> DomainResult:
	if not _configured:
		return Result.failure(&"persistence.coordinator_unconfigured", "persistence coordinator is not configured")
	if _autosave == null:
		return Result.ok(false)
	return _autosave.save_player(identity, _capture)


## 保存全部已登记角色并等待仓储完成最终写盘。
## 返回保存数量或首个持久化失败。
func save_all() -> DomainResult:
	if not _configured:
		return Result.failure(&"persistence.coordinator_unconfigured", "persistence coordinator is not configured")
	if _autosave == null:
		return Result.ok(0)
	var result := _autosave.save_all(_capture)
	if result.is_ok and _repository != null:
		var flush_result := _repository.flush()
		if not flush_result.is_ok:
			return flush_result
	return result
