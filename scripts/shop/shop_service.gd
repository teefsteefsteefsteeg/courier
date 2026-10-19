class_name ShopService
extends RefCounted
## Purchase rules shared by every shop: price check against CourierWallet, uniqueness
## check against CourierInventory, then gold out / item in as one step.

enum PurchaseResult { OK, NOT_ENOUGH_GOLD, ALREADY_OWNED, NO_ITEM, NO_SERVICES }
enum EnhanceResult { OK, NOT_ENOUGH_GOLD, NOT_ENOUGH_ORE, MAX_LEVEL, NOT_OWNED, NOT_ENHANCEABLE, NO_SERVICES }


static func can_buy(wallet: CourierWallet, inventory: CourierInventory, item: ItemDefinition) -> PurchaseResult:
	if wallet == null or inventory == null:
		return PurchaseResult.NO_SERVICES
	if item == null or item.item_id == &"":
		return PurchaseResult.NO_ITEM
	if inventory.has_item(item.item_id):
		return PurchaseResult.ALREADY_OWNED
	if wallet.gold < item.price:
		return PurchaseResult.NOT_ENOUGH_GOLD
	return PurchaseResult.OK


## Takes item.price gold and adds the item. Nothing changes unless the result is OK.
static func buy(wallet: CourierWallet, inventory: CourierInventory, item: ItemDefinition) -> PurchaseResult:
	var result := can_buy(wallet, inventory, item)
	if result != PurchaseResult.OK:
		return result
	if not wallet.spend_gold(item.price):
		return PurchaseResult.NOT_ENOUGH_GOLD
	inventory.add_item(item)
	return result


## Sells carried materials only to a catalog that buys them. Invalid quantities and
## unknown materials leave both services unchanged. Returns the gold paid.
static func sell_material(wallet: CourierWallet, inventory: CourierInventory, catalog: ShopCatalog, material_id: StringName, amount: int) -> int:
	if wallet == null or inventory == null or catalog == null or not catalog.buys_materials or amount <= 0:
		return 0
	var material := inventory.get_material_definition(material_id)
	if material == null or material.sell_price <= 0:
		return 0
	if not inventory.remove_materials({material_id: amount}):
		return 0
	var earned := amount * material.sell_price
	wallet.add_gold(earned)
	return earned


## Buys amount of a material the catalog sells: buy_price x amount gold out, the material
## in, all or nothing (not enough gold, no room in the stack or, for a new consumable, no
## free bag slot changes nothing). Returns
## the gold spent.
static func buy_material(wallet: CourierWallet, inventory: CourierInventory, catalog: ShopCatalog, material: MaterialItem, amount: int) -> int:
	if wallet == null or inventory == null or catalog == null or material == null or amount <= 0:
		return 0
	if not catalog.sells_materials.has(material) or material.buy_price <= 0:
		return 0
	var cost := material.buy_price * amount
	if wallet.gold < cost or inventory.get_room_for(material) < amount:
		return 0
	if not wallet.spend_gold(cost):
		return 0
	inventory.add_material(material, amount)
	return cost


static func can_enhance(wallet: CourierWallet, inventory: CourierInventory, catalog: ShopCatalog, item_id: StringName) -> EnhanceResult:
	if wallet == null or inventory == null or catalog == null or not catalog.enhances_items:
		return EnhanceResult.NO_SERVICES
	var item := inventory.get_definition(item_id)
	if not Enhancement.can_enhance(item):
		return EnhanceResult.NOT_ENHANCEABLE
	if not inventory.has_item(item_id):
		return EnhanceResult.NOT_OWNED
	var level := inventory.get_enhancement(item_id)
	if level >= Enhancement.MAX_LEVEL:
		return EnhanceResult.MAX_LEVEL
	if wallet.gold < Enhancement.gold_cost(level):
		return EnhanceResult.NOT_ENOUGH_GOLD
	if inventory.get_material_count(Enhancement.ORE_ID) < Enhancement.ore_cost(level):
		return EnhanceResult.NOT_ENOUGH_ORE
	return EnhanceResult.OK


## Raises an owned item one enhancement level for gold and iron ore, all or nothing.
static func enhance(wallet: CourierWallet, inventory: CourierInventory, catalog: ShopCatalog, item_id: StringName) -> EnhanceResult:
	var result := can_enhance(wallet, inventory, catalog, item_id)
	if result != EnhanceResult.OK:
		return result
	var level := inventory.get_enhancement(item_id)
	if not inventory.remove_materials({Enhancement.ORE_ID: Enhancement.ore_cost(level)}):
		return EnhanceResult.NOT_ENOUGH_ORE
	if not wallet.spend_gold(Enhancement.gold_cost(level)):
		inventory.add_material(inventory.get_material_definition(Enhancement.ORE_ID), Enhancement.ore_cost(level))
		return EnhanceResult.NOT_ENOUGH_GOLD
	inventory.set_enhancement(item_id, level + 1)
	return result


static func enhance_text(result: EnhanceResult, item: ItemDefinition, level: int) -> String:
	match result:
		EnhanceResult.OK:
			return "%s is now %s." % [item.display_name, Enhancement.level_text(level)]
		EnhanceResult.NOT_ENOUGH_GOLD:
			return "Not enough gold: the next level costs %d." % Enhancement.gold_cost(level)
		EnhanceResult.NOT_ENOUGH_ORE:
			return "Bring %d iron ore (mine it with a pickaxe)." % Enhancement.ore_cost(level)
		EnhanceResult.MAX_LEVEL:
			return "%s is already +%d." % [item.display_name, Enhancement.MAX_LEVEL]
		EnhanceResult.NOT_OWNED:
			return "You don't own that."
	return "That can't be enhanced."


static func result_text(result: PurchaseResult, item: ItemDefinition = null, wallet: CourierWallet = null) -> String:
	match result:
		PurchaseResult.OK:
			return "Bought %s." % item.display_name if item != null else "Bought."
		PurchaseResult.NOT_ENOUGH_GOLD:
			if item != null and wallet != null:
				return "Not enough gold: %s costs %d, you have %d." % [item.display_name, item.price, wallet.gold]
			return "Not enough gold."
		PurchaseResult.ALREADY_OWNED:
			return "You already own that."
		PurchaseResult.NO_ITEM:
			return "That item is not for sale."
	return "The shop is closed."
