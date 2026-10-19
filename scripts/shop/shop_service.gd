class_name ShopService
extends RefCounted
## Purchase rules shared by every shop: price check against CourierWallet, uniqueness
## check against CourierInventory, then gold out / item in as one step.

enum PurchaseResult { OK, NOT_ENOUGH_GOLD, ALREADY_OWNED, NO_ITEM, NO_SERVICES }


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
