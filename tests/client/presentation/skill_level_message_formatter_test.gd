extends SceneTree

const Formatter := preload(
	"res://scripts/client/presentation/skill_level_message_formatter.gd"
)


func _initialize() -> void:
	assert(Formatter.format("energy_cannon", 21) == "你的能量炮操作技能提升到21级！")
	assert(Formatter.format("rocket_launcher", 12) == "你的火箭炮操作技能提升到12级！")
	print("SKILL_LEVEL_MESSAGE_FORMATTER_OK (2 assertions)")
	quit(0)
