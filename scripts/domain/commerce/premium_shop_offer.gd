class_name PremiumShopOffer
extends RefCounted

var definition_id: String
var display_name: String
var description: String
var family: String
var price: int


## 将服务端目录行转换为类型化商品，展示说明取自物品目录。
## [param row] 已校验的价格配置。
## [param definition] 目录内的物品定义。
func _init(row: Dictionary, definition: Dictionary) -> void:
	definition_id = String(row["definition_id"])
	price = int(row["price"])
	family = String(definition.get("attachment_family", definition.get("premium_category", "")))
	display_name = String(definition["display_name"])
	description = String(definition.get("description", ""))
	if definition.get("stats", {}).get("attachment_effect", "") == "radar":
		description += "\n雷达与隐形功能暂未开放。"


## 导出客户端展示数据，价格只用于显示而非回传结算。
## 返回商品名称、类别、说明和紫晶价格。
func snapshot() -> Dictionary:
	return {"definition_id": definition_id, "display_name": display_name,
		"description": description, "family": family, "price": price, "currency": "amethyst",
		"maximum_quantity": 99 if family == "upgrade_material" else 1}


## 校验购买数量并按权威单价报价，材料可批量购买，装置保持一次一件。
## [param raw_quantity] 未信任的请求数量，允许JSON整数浮点表示。
## 返回有效数量及总价，或非法数量错误。
func quote(raw_quantity: Variant) -> DomainResult:
	if not (raw_quantity is int or raw_quantity is float):
		return DomainResult.failure(&"commerce.invalid_quantity", "购买数量无效")
	var amount := float(raw_quantity)
	var maximum := 99 if family == "upgrade_material" else 1
	if not is_finite(amount) or amount != floorf(amount) or amount < 1 or amount > maximum:
		return DomainResult.failure(&"commerce.invalid_quantity", "购买数量超出范围")
	return DomainResult.ok({"quantity": int(amount), "price": price * int(amount)})
