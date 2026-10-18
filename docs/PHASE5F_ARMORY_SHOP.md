# Phase 5F: Armory shop gameplay

Gameplay and UI for the weapon shop, built independently of the Armory building (that is
in the building/visual worktree). Nothing here edits `village.tscn`; the Armory scene
connects by adding a merchant (see "Connecting the Armory scene").

## What existed
- `CourierWallet` (gold, reputation, ranks): reused. It gained `spend_gold(amount)` and
  `restore(gold, reputation)`.
- **No inventory, no equipment, no save system, no melee combat.** The courier's only attack
  is the Magic Bolt (plus Dash and the Package Shield), and the only weapon models in the
  KayKit FREE pack are `sword_1handed.gltf` and `staff.gltf`. There is no axe or shield model.

## Catalog (`data/shops/armory.tres`, items in `data/items/*.tres`)
Weapons are adapted to the combat the game actually has. Every weapon is the courier's spell
focus and changes the Magic Bolt; the shield strengthens the Package Shield.

| Item | Price | Slot | Effect | Held model |
|---|---|---|---|---|
| Wooden Sword | 50 | main hand | +4 bolt damage | KayKit Weapons Bits `sword_A` |
| Iron Sword | 150 | main hand | +8 bolt damage | `sword_B` |
| Steel Sword | 300 | main hand | +13 bolt damage, 10% faster casting | `sword_D` |
| Battle Axe | 400 | main hand | +20 bolt damage, 25% slower casting | `axe_B` |
| Magic Staff | 500 | main hand | +10 bolt damage, 25% faster casting, +6 m range | staff |
| Wooden Shield | 100 | off-hand | +25 Package Shield durability | `shield_A` (left hand) |

Base courier stats: bolt damage 20, cooldown 0.45 s, range 18 m, shield 60.
Icons: `assets/ui/item_icons/*.png`, 16 px placeholder pixel art saved at 32x32 by
`tools/make_item_icons.py`, drawn at 2x with nearest filtering.

## Item data contract (`ItemDefinition`, `scripts/shop/item_definition.gd`)
| Field | Type | Meaning |
|---|---|---|
| `item_id` | StringName | Unique and stable; saved, so never rename a shipped id |
| `display_name` / `description` | String | Shop text |
| `slot` | `Slot.MAIN_HAND` / `Slot.OFF_HAND` | One item per slot is equipped |
| `price` | int > 0 | Gold |
| `icon` | Texture2D | 32x32 pixel art, nearest filter |
| `held_model` | PackedScene (optional) | Shown while equipped: main hand in the courier's right hand (`handslot.r`), off-hand in the left (`handslot.l`) |
| `bolt_damage_bonus` | float, + | Added to `CombatController.bolt_damage` |
| `bolt_cooldown_multiplier` | float, x | Multiplies `bolt_cooldown` (< 1 is faster) |
| `bolt_range_bonus` | float, + | Added to `bolt_range` |
| `shield_durability_bonus` | float, + | Added to `shield_max_durability` |

A `ShopCatalog` (`scripts/shop/shop_catalog.gd`) holds `shop_id`, `title`, `greeting` and
`items`. Any item a shop sells must also be listed in `CourierInventory.item_definitions`
(`scenes/gameplay/gameplay_services.tscn`) so saves can resolve it.

## Systems
| Script | Role |
|---|---|
| `scripts/inventory/courier_inventory.gd` (`CourierInventory`, in GameplayServices) | Owned items (unique) and equipped item per slot; `add_item`, `equip`, `unequip`, `to_dict` / `from_dict`. |
| `scripts/shop/shop_service.gd` (`ShopService`) | `can_buy` / `buy`: refuses when already owned or gold < price (nothing changes), otherwise spends gold and adds the item in one step. |
| `scripts/inventory/equipment_stats.gd` (`EquipmentStats`, in GameplayServices) | Reads the courier's base combat stats once, recomputes them from the equipped items on every change (unequipping restores them exactly), and puts the weapon's model in the right hand and the off-hand item's in the left (`KayKitCharacter.set_held_item` / `set_off_hand_item`). |
| `scripts/core/save_game.gd` (`SaveGame`, in GameplayServices) | New minimal save: `user://savegame.json` with gold, reputation, items, equipment, every REWARDED quest and the starting-gold flag. Loads on start and autosaves 0.5 s after a change. Deliveries in progress are not saved (the carried package is not persisted). Run with `-- --new-game` to start over. Disabled in headless runs, so tests never touch the player's save. |
| `scripts/core/dev_mode.gd` (`DevMode`) | Development/test mode: debug build with a window (editor play, debug export). Off in release exports and headless tests. `-- --dev` / `-- --no-dev` override. |
| `scripts/shop/merchant.gd` (`Merchant`) | Reusable merchant interface (below). |
| `scripts/gameplay_ui/shop_ui.gd`, **`scenes/gameplay/ui/shop_ui.tscn`** (`ShopUI`, instanced in `gameplay_hud.tscn`) | Shop window. |

### Gold
- **Starting gold:** 500 in development mode only, once per save (`starting_gold_granted` is
  saved, so neither a reload nor a second call pays it again).
- **Quest rewards:** delivery contracts already pay gold (Q1 50, Q2 and Q3 per their data) through
  `QuestManager.grant_reward`, which is idempotent. Rewarded quests are now saved and restored
  as REWARDED (`QuestManager.restore_finished_quests`), so a reward is never paid twice and
  a delivered contract is not offered again after a reload.

### Shop window (`ShopUI`)
Title and greeting, current gold, and one row per item: icon, name, slot and stats,
description, price, status (`Owned`, `Equipped`, `Need N more gold`) and a button
(`Buy`, disabled with the reason when unaffordable; `Equip`; `Unequip`). A feedback line
reports each purchase or refusal. It is modal like the quest board: it joins `ui_modal`,
pauses the courier, refuses to open over another window, closes any open dialogue, and closes
on Escape, interact or the Close button. `[Esc] Close` uses the pixel-art keycap.

## Merchant interface / connecting the Armory scene
A shop is anything in group `merchants` with `signal shop_requested(merchant, interactor)`,
`get_catalog() -> ShopCatalog` and `get_merchant_name() -> String`. ShopUI binds every
merchant automatically, including ones added later. Two ready-made ways in:
- **A counter:** instance `scenes/gameplay/shop/merchant_counter.tscn` (an Interactable and a
  Merchant with the Armory catalog) at the Armory's counter. Prompt: `[E] Browse Willowmere Armory`.
- **A shopkeeper NPC:** add a `Merchant` node (script `scripts/shop/merchant.gd`, `catalog` =
  `data/shops/armory.tres`) as a child of the NPC. Prompt: `[E] Browse wares of <name>`.
  Interacting opens the shop.

Until the Armory scene adds one, there is no shop in the village.

## Tests
`tests/armory_shop_tests.gd` (70 checks):
- **Data:** catalog prices and icons.
- **Purchase rules:** no gold, one short, exact, duplicate, overdraft.
- **Starting gold:** none in tests; 500 once in development mode.
- **Shop window via the counter:** prompt, modal, rows, prices, nearest icons, buy, disabled
  Buy with a reason, Escape.
- **Equipment:** stats applied and restored, bolt damage carried by a cast bolt, both slots at
  once, held model.
- **Merchant NPC:** prompt and opening, with the dialogue closed.
- **Quest gold:** paid once, never twice.
- **Save/load:** a fresh session restores gold, items, equipment and stats, keeps Q1 REWARDED
  and unpaid, and doesn't grant starting gold again; plus autosave and a corrupt save ignored.

`tests/capture_armory_shop_screenshots.gd` renders the shop in a GPU window. It also confirms
the development-mode 500 gold and the sword in hand.

## Limitations
- The weapons are spell foci for the Magic Bolt, since there is no melee combat. The axe and
  shield have no 3D model (none in the KayKit FREE pack).
- Item icons are simple placeholders.
- Removing the shield lowers the shield's maximum but not its current durability, so it can
  read above 100% until it is next used.
- Saving is new. Only finished contracts persist; a delivery in progress is lost on quit.

## Fix: equipped weapon not visible (2026-10-18, `phase5f-integrated`)

**Symptom:** after buying and equipping a weapon, the courier's hand was empty.

**Root cause:** data, not code. The Battle Axe and Wooden Shield had no `held_model`. When this
branch was written the project had no axe or shield model (the KayKit Weapons Bits pack arrived
with the Armory displays from `phase5f-building-visual`). Equipping the axe made
`EquipmentStats.apply()` call `set_held_item(null)`, which emptied the hand and also removed the
sword or staff equipped before. The off-hand slot was never shown at all: `EquipmentStats` only
applied the main hand, and `KayKitCharacter` had only a right-hand slot. All three swords also
shared `sword_1handed`, so switching between them changed nothing on screen. The integration
merge did not change any player, character, inventory or combat file.

**Fix:**
- Every item has a `held_model` reused from `assets/models/kaykit_weapons/` (`sword_A`, `sword_B`,
  `sword_D`, `axe_B`, `shield_A`). The staff keeps its Adventurers model. The Weapons Bits share
  the KayKit hand-slot convention (grip at the origin, blade +Y), so the right hand needs no
  transform.
- `KayKitCharacter.set_off_hand_item()` and `get_off_hand_item_node()` add a `LeftHandSlot`
  (`handslot.l`) beside the existing `RightHandSlot`, through the same code path.
- `EquipmentStats.apply()` sets both hands.

Equipping is unchanged: buying only adds the item and **Equip** is a separate button, as designed.

Regression test: `tests/equipment_visual_tests.gd` (31 checks). It checks that every item has a
held model; that each item appears on the right bone, visible and at the courier; that switching
replaces the model; that unequipping removes it; that a save round trip shows the axe and shield;
that the attack animation keeps the weapon; and that Pip's prop is unchanged. On the original item
data it fails 12 checks. Rendered: `docs/validation/phase5f/equipment/` (regenerate with
`tests/capture_equipped_weapon_screenshots.gd`, which removes SaveGame so the real save is never
touched).
