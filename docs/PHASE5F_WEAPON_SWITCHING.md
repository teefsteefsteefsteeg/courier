# Phase 5F: weapon inventory and quick switching

Branch `phase5f-integrated`. The courier can switch between purchased weapons anywhere, and
each weapon type now attacks differently. Everything is built into the existing
`CourierInventory`, `EquipmentStats`, `CombatController`, `SaveGame` and HUD; there is no second
inventory or combat system.

Screenshots (1600x900, rendered): `docs/validation/phase5f/weapon_switch/`. Regenerate with
`godot --path . --resolution 1600x900 --script res://tests/capture_weapon_switch_screenshots.gd -- <dir>`.

## Player view
- **Quick weapon bar** (bottom-right, under the package panels): five slots with the weapon
  icon and the key cap (1-5). The equipped weapon has a gold outline; empty slots are dim, show
  "-" and are disabled. Above the slots: the weapon in hand, how it attacks and its stats
  ("Battle Axe / Axe · heavy melee · 45 damage, 0.95 s, 2.2 m reach"), or "Bare hands / Magic
  bolts" with the Tab hint.
- **Switching:** press 1-5 or click a slot. The model in the hand, the attack and the stats change
  at once. Moving, dashing, interacting and attacking are unchanged.
- **Equipment window** (Tab): every item, marked **Equipped** (gold), **Owned** (green) or **Not
  owned · buy it at the Armory** (dimmed, every button disabled). Owned items have Equip /
  Unequip. Owned weapons have five slot buttons; the weapon's current slot is gold, and pressing
  it clears the slot. Shields show "Off-hand: no quick slot". Tab, Escape or Close closes it.
- **Buying** still only adds the item, and the new weapon fills the first empty quick slot. It is
  not equipped automatically.
- **Hunting Bow** (`data/items/hunting_bow.tres`, KayKit `bow_A_withString`, new pixel icon) is
  sold in the Armory for 250 g, so arrows can be used in play. Shop and Equipment rows show each
  weapon's attack type and "two-handed".

## Weapon types (`ItemDefinition.weapon_type`)
| Type | Items | Space attacks with | Animation (FREE pack) |
|---|---|---|---|
| none (bare hands) | - | Magic Bolt (base stats) | Throw, 1.6x |
| STAFF | Magic Staff | Magic Bolt + the staff's bolt bonuses | Throw, 1.6x |
| SWORD | Wooden / Iron / Steel Sword | fast melee: 14 / 20 / 27 damage, 0.38 / 0.36 / 0.32 s, 1.7-1.9 m, 110-115° arc, 0.1-0.12 s wind-up | Interact, 2.6x |
| AXE | Battle Axe | heavy melee: 45 damage, 0.95 s, 2.2 m, 150° arc, 0.35 s wind-up | Throw, 1.1x (overhead chop) |
| BOW | Hunting Bow (250 g, two-handed) | arrows (`scenes/gameplay/combat/arrow.tscn`, KayKit `arrow_A`): 16 damage, 0.6 s, 24 m, 28 m/s | Use_Item, 2.0x |

Melee damages every enemy (CombatHealth on the enemy layer) inside the reach and arc when the
wind-up ends, through the same `CombatHealth.apply_damage` and `target_hit` signal as bolts. Bows
are `two_handed`: equipping one takes the shield off, and a shield cannot be equipped beside one.
Weapon stats are data in `data/items/*.tres` (Attack group).

## Code
| File | Change |
|---|---|
| `scripts/shop/item_definition.gd` | `WeaponType`, `two_handed`, attack stats, `is_weapon()`, `get_attack_summary()`; stat lines show attack stats |
| `scripts/inventory/courier_inventory.gd` | Quick slots: `assign_quick_slot`, `clear_quick_slot`, `select_quick_slot`, `get_quick_slot(_ids)`, `find_quick_slot`, `can_quick_slot`, `quick_slots_changed`. Only owned main-hand weapons, at most one slot per weapon, auto-fill on purchase. Two-handed rule in `equip`. `to_dict` / `from_dict` save `quick_slots`; older saves fill the slots from owned weapons |
| `scripts/combat/combat_controller.gd` | `AttackStyle`, `try_attack` (the Space action), `try_melee` / `get_melee_targets` / `cancel_melee`, `try_arrow`, `set_attack_style`, `switch_weapon` (cancels an unlanded swing; optional `switch_delay`), signals `melee_started`, `melee_resolved`, `melee_cancelled`, `arrow_fired`; `get_bolt_cooldown_remaining` / `get_bolt_cooldown`, so the combat HUD shows the real cooldown of any attack. `try_magic_bolt` is unchanged |
| `scripts/inventory/equipment_stats.gd` | Sets the attack style and melee / arrow stats from the main-hand weapon; calls `switch_weapon()` when the weapon changes |
| `scripts/characters/kaykit_character.gd`, `player_animator.gd` | `melee_fast`, `melee_heavy`, `shoot` actions, played on the new signals |
| `scripts/gameplay_ui/quick_weapon_bar.gd` | `QuickWeaponBar` (HUD) |
| `scripts/gameplay_ui/equipment_ui.gd` | `EquipmentUI` (modal, Tab) |
| `scripts/gameplay_ui/gameplay_hud.gd` | Creates both; bottom-right column is quick bar, package status, package indicator |
| `scripts/core/save_game.gd` | Autosaves when quick slots change |
| `project.godot` | `quick_slot_1`..`quick_slot_5` (keys 1-5) and `toggle_equipment` (Tab). None was bound before |

## Safety rules
- **Blocked** while any `ui_modal` window (journal, quest board, shop, Equipment, expanded map)
  or a dialogue line is open, while the courier's input is off, or while knocked out. Both keys
  and clicks are blocked. The Equipment window refuses to open over another window or a dialogue
  line.
- **Mid-swing:** a melee swing that hasn't landed is cancelled (`melee_cancelled`), so it never
  lands with the new weapon's stats.
- **Cooldown:** all attacks share one cooldown, and switching never shortens it, so switching
  can't skip a cooldown. A newly equipped weapon can attack at once when no cooldown is running.
  `CombatController.switch_delay` (0 by default) can add a minimum wait after a switch.
- **Mid-dash:** the dash finishes normally; only the weapon changes.

## Persistence
`user://savegame.json` → `inventory` holds `owned`, `equipped` (MAIN_HAND / OFF_HAND) and
`quick_slots` (five ids, "" for empty). The save loads on start, so reloading the scene restores
purchases, slots and the weapon in hand. Ownership is stored once (`owned`); quick slots only
refer to ids, and unknown or unowned ids in a save are dropped.

## Tests
`tests/weapon_quick_switch_tests.gd` (93 checks) runs on the real village:
- Item types, and the quick-slot rules: unowned weapons, shields, bad indexes, no duplicates,
  replace and clear, the two-handed bow, and an old save.
- Buying two weapons in the shop and assigning them to slots 1 and 2 in the Equipment window.
- Owned, Equipped and Not owned marking.
- Switching with keys while standing and while walking, empty slots, and clicks.
- Mesh and attack style per weapon, real hits on a training dummy (sword 14, axe 45 after its
  wind-up), a miss behind, bolts for the staff and bare hands, arrows for a bow, and the
  animations.
- Switching mid-swing, on cooldown and mid-dash.
- Blocking during dialogue, the shop, the Equipment window and the journal.
- HUD key caps and icons, no overlap at 1600x900, 1366x768 and 1280x720, and no key conflicts.
- Save, load and a full scene reload from a test save file.

`tests/equipment_visual_tests.gd` was updated: the loaded axe now asserts its heavy melee.

## Known limitations
- The KayKit FREE animation pack has no swing or draw clips; melee and bow reuse Interact /
  Throw / Use_Item at different speeds (`ACTIONS` lists the proper clip names first, so a pack
  that has them would use them).
- The Phase 4 combat panel still labels the primary attack "Bolt" (its cooldown is now exact
  for every weapon).
- Quick-slot key caps follow the InputMap but the bar is not remappable in-game (no settings UI).
- Not yet playtested by a person.
