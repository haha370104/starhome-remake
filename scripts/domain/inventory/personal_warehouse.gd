class_name PersonalWarehouse
extends RefCounted

const MAX_CABINETS := 6

var revision := 0
var _cabinets: Array[Inventory] = [Inventory.new()]


## 在首次访问物品前完成存储适配器的按需还原；纯内存仓库无需额外工作。
## 返回加载结果，失败必须保留原存储，不能把空列表当作已清空的仓库。
func materialize() -> DomainResult:
	return DomainResult.ok()


## 查询已开通的个人柜数量，未开通的柜不能持有物品。
## 返回一至六个柜子。
func cabinet_count() -> int:
	return _cabinets.size()


## 提供指定柜内物品的数组副本，不把仓库合并进可用背包。
## [param cabinet] 从一开始的柜号。
## 返回物品数组，未开通柜返回空数组。
func items(cabinet: int) -> Array[GameItem]:
	if not materialize().is_ok: return [] as Array[GameItem]
	return _cabinets[cabinet - 1].items() if cabinet >= 1 and cabinet <= cabinet_count() else [] as Array[GameItem]


## 按实例身份搜索自己的全部储物柜。
## [param id] 稳定实例身份。
## 返回仓库内物品，没有时为空。
func find(id: String) -> GameItem:
	if not materialize().is_ok: return null
	for cabinet: Inventory in _cabinets:
		var item := cabinet.find(id)
		if item != null: return item
	return null


## 在背包和指定柜之间存取，旧意图及未开通柜在转移前拒绝。
## [param backpack] 当前人物的真实背包。
## [param cabinet] 从一开始的柜号。
## [param deposit] true为存入，false为取出。
## [param id] 来源物品身份。
## [param amount] 完整接收才结算的正整数数量。
## [param inventory_revision] 客户端观察到的背包版本。
## [param warehouse_revision] 客户端观察到的仓库版本。
## [param split_id] 由服务端生成、部分转移时使用的新身份。
## 返回实际转移结果；成功同时推进背包和仓库版本。
func transfer(backpack: Inventory, cabinet: int, deposit: bool, id: String, amount: int, inventory_revision: int, warehouse_revision: int, split_id: String) -> DomainResult:
	var checked := backpack.require_revision(inventory_revision)
	if not checked.is_ok: return checked
	if warehouse_revision != revision:
		return DomainResult.failure(&"warehouse.revision", "仓库状态已更新，请重试")
	checked = materialize()
	if not checked.is_ok: return checked
	if cabinet < 1 or cabinet > cabinet_count():
		return DomainResult.failure(&"warehouse.cabinet", "请先开通该储物柜")
	if deposit and find(id) != null:
		return DomainResult.failure(&"warehouse.identity", "物品身份已存在于仓库")
	if not split_id.is_empty() and (find(split_id) != null or backpack.find(split_id) != null):
		return DomainResult.failure(&"warehouse.identity", "存取物品身份重复")
	var source: Inventory = backpack if deposit else _cabinets[cabinet - 1]
	var target: Inventory = _cabinets[cabinet - 1] if deposit else backpack
	var result := InventoryTransfer.move(source, target, id, amount, split_id)
	if result.is_ok: revision += 1
	return result


## 以原版扩容费用开通下一个柜，余额不足或版本冲突不扣费。
## [param wallet] 当前人物紫晶钱包。
## [param rules] 服务器加载的仓库规则。
## [param expected_revision] 当前仓库版本。
## 返回新柜数量和实际费用。
func expand(wallet: AmethystWallet, rules: WarehouseRules, expected_revision: int) -> DomainResult:
	if expected_revision != revision:
		return DomainResult.failure(&"warehouse.revision", "仓库状态已更新，请重试")
	var loaded := materialize()
	if not loaded.is_ok: return loaded
	if cabinet_count() >= MAX_CABINETS:
		return DomainResult.failure(&"warehouse.maximum", "已开通全部六个储物柜")
	var checked := wallet.can_spend(rules.expansion_cost)
	if not checked.is_ok: return checked
	wallet.spend(rules.expansion_cost)
	_cabinets.append(Inventory.new())
	revision += 1
	return DomainResult.ok({"cabinet_count": cabinet_count(), "cost": rules.expansion_cost})
