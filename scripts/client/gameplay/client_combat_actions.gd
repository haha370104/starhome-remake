class_name ClientCombatActions
extends RefCounted

const WEAPON_MODES := {
	"energy_cannon": {
		"weapon_id": &"recruit_energy_cannon",
		"ability_id": "energy_cannon.primary",
		"layer_id": &"primary_weapon",
		"display_name": "新兵能量炮",
	},
	"missile": {
		"weapon_id": &"starter_missile",
		"ability_id": "missile.primary",
		"layer_id": &"missile_weapon",
		"display_name": "初级导弹",
	},
	"rocket_launcher": {
		"weapon_id": &"starter_rocket_launcher",
		"ability_id": "rocket_launcher.primary",
		"layer_id": &"rocket_weapon",
		"display_name": "初级火箭",
	},
}
const SELF_REPAIR_ABILITY_ID := "self_repair"
