class_name VehicleMiningArm
extends VehicleEquipment


## 校验采掘臂是否可工作，不把工程臂当作能量炮。
## [param mining_level] 权威角色的采矿技能等级。
## 返回成功或耐久、技能限制原因；不消耗材料和能量。
func validate_collection(mining_level: int) -> DomainResult:
	if durability <= 0:
		return DomainResult.failure(&"mining.arm_broken", "mining arm durability is exhausted")
	if mining_level < required_skill_level:
		return DomainResult.failure(&"mining.arm_skill_too_low", "mining skill does not meet the arm requirement")
	return DomainResult.ok()
