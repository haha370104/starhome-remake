class_name PlayerSyncStream
extends RefCounted

var _baseline: Dictionary = {}
var _sequence := 0
var _epoch := ""
var _force_full := true


## 清除连接基线；新连接永远从完整快照开始。
func reset() -> void:
	_baseline.clear()
	_sequence = 0
	_epoch = ""
	_force_full = true


## 请求下一份投影以完整形式发送，不改变持久化事务版本。
func require_full() -> void:
	_force_full = true


## 编码一份完整玩家投影；同步序号独立于可能不变的存档 revision。
## [param bundle] 已通过领域校验的完整投影。
## 返回带版本、连接代号和完整内容或补丁的信封。
func encode(bundle: Dictionary) -> Dictionary:
	if _epoch.is_empty(): _epoch = Crypto.new().generate_random_bytes(12).hex_encode()
	var id := String(bundle.get("character", {}).get("character_id", ""))
	if _baseline.get("character", {}).get("character_id") != id: _force_full = true
	var envelope := {"version": PlayerChange.VERSION, "epoch": _epoch, "sequence": _sequence + 1,
		"base": _sequence, "character_id": id}
	if _force_full or _baseline.is_empty(): envelope["full"] = bundle.duplicate(true)
	else: envelope["patch"] = PlayerChange.difference(_baseline, bundle)
	_sequence += 1
	_force_full = false
	_baseline = bundle.duplicate(true)
	return {"player_change": envelope}


## 校验连接代号及连续序号后原子接受候选，断档保留旧投影等待全量。
## [param envelope] 信封中的 player_change 对象。
## 返回完整投影；重复、乱序、身份混用与坏补丁均拒绝。
func decode(envelope: Dictionary) -> DomainResult:
	if int(envelope.get("version", -1)) != PlayerChange.VERSION or not envelope.get("epoch") is String \
			or String(envelope.epoch).is_empty() or int(envelope.get("sequence", 0)) <= 0:
		return DomainResult.failure(&"player_sync.invalid", "玩家同步信封无效")
	var sequence := int(envelope.sequence)
	if envelope.epoch == _epoch and sequence <= _sequence:
		return DomainResult.failure(&"player_sync.duplicate", "玩家同步已接收")
	var candidate: Dictionary
	if envelope.get("full") is Dictionary:
		candidate = envelope.full.duplicate(true)
	else:
		if envelope.epoch != _epoch or int(envelope.get("base", -1)) != _sequence \
				or sequence != _sequence + 1 or not envelope.get("patch") is Dictionary:
			return DomainResult.failure(&"player_sync.gap", "玩家同步需要完整快照")
		var applied := PlayerChange.apply(_baseline, envelope.patch)
		if not applied.is_ok: return applied
		candidate = applied.value
	if not candidate.get("character") is Dictionary or not candidate.get("inventory") is Dictionary \
			or not candidate.get("vehicle") is Dictionary or candidate.character.get("character_id") != envelope.get("character_id"):
		return DomainResult.failure(&"player_sync.invalid", "玩家同步身份或组件无效")
	_baseline = candidate.duplicate(true)
	_sequence = sequence
	_epoch = envelope.epoch
	return DomainResult.ok(candidate)
