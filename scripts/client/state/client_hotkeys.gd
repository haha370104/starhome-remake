class_name ClientHotkeys
extends RefCounted

const DEFAULTS := {"map": KEY_TAB, "self_repair": KEY_Z}
const LABELS := {"map": "当前地图", "self_repair": "自维修"}
const MODIFIERS := KEY_MASK_CTRL | KEY_MASK_ALT | KEY_MASK_SHIFT
var capturing := false
var _bindings: Dictionary = DEFAULTS.duplicate()


## 规范化按键组合并拒绝重复、系统保留和只有修饰键的绑定。
## [param action] 已存在的游戏动作。[param chord] 物理布局无关的逻辑按键与修饰键。
## 返回成功或可读的绑定失败说明。
func bind_key(action: String, chord: Variant) -> DomainResult:
	if not DEFAULTS.has(action) or not valid_chord(chord):
		return DomainResult.failure(&"settings.invalid_key", "请选择字母、数字、功能键或导航键，避开系统保留组合")
	for other: String in _bindings:
		if other != action and _bindings[other] == chord:
			return DomainResult.failure(&"settings.duplicate_key", "此按键已用于%s" % LABELS[other])
	_bindings[action] = int(chord)
	return DomainResult.ok()


## 判定当前逻辑组合是否触发动作，录入按键期间停用全部游戏快捷键。
## [param action] 动作身份。[param event] 原始输入事件。
## 返回是否为一次完整且准确匹配的按下。
func matches(action: String, event: InputEvent) -> bool:
	return not capturing and event is InputEventKey and event.pressed and not event.echo \
		and _bindings.has(action) and event.get_keycode_with_modifiers() == _bindings[action]


## 生成界面中的实际快捷键文字。
## [param action] 动作身份。
## 返回可读组合名称。
func label(action: String) -> String:
	return OS.get_keycode_string(_bindings.get(action, 0))


## 输出独立偏好快照，不暴露可变的绑定字典。
## 返回两项动作对应的整数键码。
func snapshot() -> Dictionary:
	return _bindings.duplicate()


## 整体恢复规范化绑定，允许对换两个动作而不受逐条赋值顺序影响。
## [param raw] 本地配置中的绑定表。
## 返回是否通过完整校验。
func restore(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size() != DEFAULTS.size(): return false
	var seen: Array[int] = []
	for action: String in DEFAULTS:
		var chord: Variant = raw.get(action)
		if not valid_chord(chord) or int(chord) in seen: return false
		seen.append(int(chord))
	_bindings = raw.duplicate()
	return true


## 保留可用于游戏的键值，避免把关闭窗口和系统切换等组合截作游戏操作。
## [param chord] 未信任的本地按键值。
## 返回是否允许绑定。
static func valid_chord(chord: Variant) -> bool:
	if not chord is int or chord <= 0 or chord & ~(KEY_CODE_MASK | MODIFIERS): return false
	var key: int = chord & KEY_CODE_MASK
	if not ((key >= KEY_A and key <= KEY_Z) or (key >= KEY_0 and key <= KEY_9) \
		or (key >= KEY_F1 and key <= KEY_F12) or key in [KEY_TAB, KEY_SPACE, KEY_INSERT,
		KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]): return false
	if chord & KEY_MASK_ALT and key in [KEY_F4, KEY_TAB, KEY_SPACE]: return false
	if chord & KEY_MASK_CTRL and chord & KEY_MASK_ALT and key == KEY_DELETE: return false
	return true
