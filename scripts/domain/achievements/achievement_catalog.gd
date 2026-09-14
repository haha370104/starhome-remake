class_name AchievementCatalog
extends RefCounted

class Definition extends RefCounted:
	var id: String
	var category: String
	var target_id: String
	var target_name: String
	var required: int
	var points: int

class Title extends RefCounted:
	var id: String
	var display_name: String
	var required_points: int
	var bonuses: AchievementBonuses

static var _default: AchievementCatalog
var definitions: Array[Definition] = []
var titles: Array[Title] = []
var caps: Dictionary = {}


## 加载并缓存随游戏发布的成就规则，所有玩家共享不可修改的目录。
## 返回已校验的目录；配置错误时报告错误并返回空目录。
static func shared() -> AchievementCatalog:
	if _default == null:
		_default = AchievementCatalog.new()
		var loaded := JsonConfigLoader.load_dictionary("res://data/gameplay/achievements_v1.json")
		var checked := _default.initialize(loaded.value) if loaded.is_ok else loaded
		if not checked.is_ok:
			push_error("Achievement catalog: " + checked.error_message)
	return _default


## 校验目标、阶梯与称号规则后一次性安装目录。
## [param config] 来自配置边界的成就规则，不含玩家状态。
## 返回目录或具体错误；错误配置不会部分生效。
func initialize(config: Dictionary) -> DomainResult:
	var rows: Array[Definition] = []
	var ranks: Array[Title] = []
	var limits: Dictionary = {}
	if int(config.get("schema_version", 0)) != 1 or not config.get("targets") is Array \
		or not config.get("milestones") is Dictionary or not config.get("titles") is Array:
		return _invalid("invalid schema or collections")
	for raw: Variant in config["targets"]:
		if not raw is Dictionary:
			return _invalid("target must be a dictionary")
		var category := String(raw.get("category", ""))
		var target := String(raw.get("id", ""))
		var key := "%s:%s" % [category, target]
		var milestones: Variant = config["milestones"].get(category)
		if category not in AchievementEvent.KIND_IDS or target.is_empty() \
			or String(raw.get("name", "")).is_empty() or limits.has(key) \
			or not milestones is Array or milestones.is_empty():
			return _invalid("invalid or duplicate target " + key)
		var previous := 0
		for step: Variant in milestones:
			if not step is Dictionary or not _positive_integer(step.get("required")) \
				or not _positive_integer(step.get("points")) or int(step["required"]) <= previous:
				return _invalid("milestones must be positive and strictly increasing")
			var row := Definition.new()
			row.category = category
			row.target_id = target
			row.target_name = String(raw["name"])
			row.required = int(step["required"])
			row.points = int(step["points"])
			row.id = "%s:%d" % [key, row.required]
			rows.append(row)
			previous = row.required
		limits[key] = previous
	var previous_points := -1
	var title_ids: Dictionary = {}
	for raw: Variant in config["titles"]:
		if not raw is Dictionary or not raw.get("bonuses") is Dictionary:
			return _invalid("invalid title")
		var points: Variant = raw.get("required_points")
		if not _positive_integer(points, true) or int(points) <= previous_points \
			or String(raw.get("id", "")).is_empty() or title_ids.has(raw["id"]) \
			or String(raw.get("name", "")).is_empty():
			return _invalid("invalid or unordered title")
		for field: Variant in raw["bonuses"]:
			if field not in AchievementBonuses.FIELDS or not _positive_integer(raw["bonuses"][field], true):
				return _invalid("invalid title bonus")
		var rank := Title.new()
		rank.id = String(raw["id"])
		rank.display_name = String(raw["name"])
		rank.required_points = int(points)
		rank.bonuses = AchievementBonuses.new(raw["bonuses"])
		ranks.append(rank)
		title_ids[rank.id] = true
		previous_points = rank.required_points
	if rows.is_empty() or ranks.is_empty() or ranks[0].required_points != 0:
		return _invalid("catalog needs targets and a zero-point title")
	definitions = rows
	titles = ranks
	caps = limits
	return DomainResult.ok(self)


## 选择积分已达到的最高称号，低阶称号不参与叠加。
## [param points] 聚合根据已完成成就派生的积分。
## 返回唯一生效的称号。
func title_for(points: int) -> Title:
	var result: Title = null
	for rank: Title in titles:
		if rank.required_points > points:
			break
		result = rank
	return result


## 验证配置中的有限整数量值，拒绝字符串、小数与超大数值。
## [param value] 配置字段值。
## [param allow_zero] 是否允许零值。
## 返回该值是否属于允许范围。
func _positive_integer(value: Variant, allow_zero := false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floorf(float(value)) and float(value) >= (0 if allow_zero else 1) \
		and float(value) <= 1000000


## 构建成就配置失败结果。
## [param message] 配置错误原因。
## 返回统一领域错误。
func _invalid(message: String) -> DomainResult:
	return DomainResult.failure(&"achievements.invalid_catalog", message)
