class_name SmartAssistantController
extends Node

const WEAPON_SWITCH_SECONDS := 0.5

var policy := SmartAssistantPolicy.new()
var _combat: CombatInteractionController
var _panel: SmartAssistantPanel
var _snapshot: Dictionary = {}
var _elapsed := 0.0
var _retry_at: Dictionary = {}
var _settings_path := ""
var _observed_at := 0
var _weapon_elapsed := 0.0


## 绑定已有战斗输入和设置面板，不创建另一个网络或玩家状态所有者。
## [param combat] 手动战斗也使用的意图入口。
## [param panel] 只发布设置意图的窗口。
func configure(combat: CombatInteractionController, panel: SmartAssistantPanel) -> void:
	_combat = combat
	_panel = panel
	_combat.multiplayer_presenter.combat_snapshot_received.connect(_observe)
	_combat.multiplayer_presenter.map_joined.connect(_map_changed)
	_panel.settings_changed.connect(_apply_settings)
	_settings_path = "user://smart-assistant-%s.cfg" % String(_combat.panel_session.current_player.entity_id).sha256_text().left(16)
	var saved := ConfigFile.new()
	if saved.load(_settings_path) == OK:
		var values: Dictionary = saved.get_value("assistant", "preferences", {})
		values["enabled"] = false
		policy.apply(values)
	_panel.apply_settings(policy.snapshot())


## 切图后立即丢弃旧目标，等待新地图快照再恢复增强功能。
## [param _map_id] 新地图定义 ID。
## [param _instance] 新地图实例 ID。
## [param _position] 新出生点。
## [param _version] 新地图定义版本。
func _map_changed(_map_id: StringName, _instance: String, _position: Vector2, _version: int) -> void:
	_snapshot.clear()
	_retry_at.clear()
	_weapon_elapsed = 0.0


## 只保存服务器已投影的可见对象，不修改生命或掉落状态。
## [param snapshot] 当前权威战斗快照。
func _observe(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_observed_at = Time.get_ticks_msec()


## 保存当前角色的界面偏好，启停立即生效。
## [param values] 设置面板发布的选项。
func _apply_settings(values: Dictionary) -> void:
	policy.apply(values)
	_weapon_elapsed = 0.0
	var saved := ConfigFile.new()
	saved.set_value("assistant", "preferences", policy.snapshot())
	if saved.save(_settings_path) != OK:
		_panel.notice_requested.emit("智脑设置保存失败，本次会话仍可使用")
	_retry_at.clear()


## 节流增强操作；切图、死亡、手动行走和维修期间暂停自动攻击。
## [param delta] 本帧秒数。
func _process(delta: float) -> void:
	_advance_weapon_switch(delta)
	_elapsed += delta
	if _elapsed < 0.4 or _combat == null:
		return
	_elapsed = 0.0
	if not policy.enabled:
		_panel.show_status("未启用")
		return
	if _combat.is_input_locked() or _combat.world_view.player == null or not _combat.world_view.player.is_combat_actor_active() \
			or _combat.multiplayer_presenter.session.is_vehicle_recovery_pending():
		_panel.show_status("已暂停：当前状态不允许操作")
		return
	if _snapshot.is_empty() or Time.get_ticks_msec() - _observed_at > 3000:
		_panel.show_status("已暂停：等待当前地图状态")
		return
	_panel.show_status("运行中 · 手动移动时暂停自动攻击")
	var vehicle: Dictionary = _snapshot.get("local_vehicle", {})
	if policy.needs_repair(vehicle) and _may_attempt("repair", 5.0):
		_combat.request_self_repair()
		return
	var origin: Vector2 = _combat.world_view.player.position
	if policy.auto_pickup:
		var loot := policy.nearest(_snapshot.get("ground_loot", []), origin, 120.0, false)
		if not loot.is_empty() and _may_attempt(String(loot.loot_id), 4.0):
			_combat.request_ground_loot_pickup(String(loot.loot_id))
			return
	if not policy.auto_attack or bool(vehicle.get("self_repair_active", false)) or _combat.local_player_controller.has_active_route():
		return
	var mode := String(_combat.hud.selected_action())
	if mode == "energy_cannon":
		var player := _combat.panel_session.current_player
		var device: VehicleEquipment = player.vehicle.loadout.at(1) if player != null and player.vehicle != null else null
		if device == null or device.primary_device_kind() != "energy_cannon":
			_panel.show_status("自动攻击已暂停：主槽当前不是能量炮")
			return
	var visual: WeaponAttackVisualController = _combat.world_view.combat_attack_controllers.get(mode)
	if visual == null:
		return
	var monster := policy.nearest(_snapshot.get("monsters", []), origin, visual.assisted_attack_range(), true)
	if monster.is_empty():
		return
	var target := Vector2(float(monster.position[0]), float(monster.position[1]))
	if visual.can_assist_fire(origin, target):
		_combat.request_weapon_attack(target)


## 按原版500毫秒心跳切换炮导，独立于自动攻击，手动点击仍经过原战斗入口。
## [param delta] 本帧秒数；暂停期间不累计切换次数。
func _advance_weapon_switch(delta: float) -> void:
	if _combat == null or not policy.enabled or not policy.gun_missile_mode \
		or _combat.is_input_locked() or _combat.world_view.player == null \
		or not _combat.world_view.player.is_combat_actor_active() or _snapshot.is_empty() \
		or Time.get_ticks_msec() - _observed_at > 3000 \
		or bool(_snapshot.get("local_vehicle", {}).get("self_repair_active", false)):
		_weapon_elapsed = 0.0
		return
	var player := _combat.panel_session.current_player
	var next := policy.next_attack_weapon(_combat.hud.selected_action(),
		player.vehicle.loadout if player != null and player.vehicle != null else null)
	if next.is_empty():
		_weapon_elapsed = 0.0
		return
	_weapon_elapsed += delta
	if _weapon_elapsed + 0.000001 < WEAPON_SWITCH_SECONDS:
		return
	_weapon_elapsed = fmod(maxf(_weapon_elapsed, WEAPON_SWITCH_SECONDS), WEAPON_SWITCH_SECONDS)
	_combat.hud.select_action(next)


## 限制失败后的重试频率，避免背包满或能源不足时刷屏。
## [param key] 动作或掉落实例身份。
## [param seconds] 最短重试间隔。
## 返回本次是否可以尝试。
func _may_attempt(key: String, seconds: float) -> bool:
	var now := Time.get_ticks_msec()
	if now < int(_retry_at.get(key, 0)):
		return false
	_retry_at[key] = now + int(seconds * 1000)
	return true
