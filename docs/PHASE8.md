# Phase 8: controls, world expansion, dragon boss and companion

Branch `phase5f-integrated`, Godot 4.7.2. Screenshots in `docs/validation/phase8/` come from
rendered runs of the real game (GPU window, 1600x900, real key events); each capture
script removes SaveGame so the player's save is never touched.

Two briefs from the user (2026-10-19) are tracked here: "Phase 7 completion & Phase 8 world
expansion" (A-H) and "Phase 8 additional features" (food market, staff spells, jump, HP
regeneration, dragon companion and flight).

## Decisions taken with the user (2026-10-19)
- **Controls:** Space attack (unchanged), Ctrl jump, Tab world map, Q inventory, R package
  shield (was Q), T tool/weapon quick switch (also switches the inventory's two views while
  it is open), M freed. Five extra food slots on 6 7 8 9 0 (with the food market). Planned
  for the later features: Z / X weapon skills, C ultimate, V dragon ability, H summon /
  dismiss the dragon (bound when those features land, so prompts never show dead keys).
- **New region:** the waterfall, river, dungeon and dragon go in a **new separate region**
  with its own gateway; Runewood Highlands and the Sentinel Vault (boss Gorvath) stay.
- Tab opening the map instead of the inventory could not be reproduced on this branch (the
  InputMap had Tab = inventory, M = map, and a rendered run with real keys did that). The
  new layout makes Tab the map on purpose.

## Status
| # | Milestone | Status |
|---|---|---|
| 1 | Controls: Tab map, Q inventory, R shield, T tool/weapon switch, Ctrl jump | **Done** (below) |
| 2 | Resource respawn without countdowns; tools in every map | not started |
| 3 | Weapon enhancement VFX rework (+1 silver spark .. +5 legendary elemental) | not started |
| 4 | Animated HUD avatar | not started |
| 5 | Enterable houses (Armory, Post Office, one home) with NPCs | not started |
| 6 | Food market, consumables, food slots 6-0, MP and rage, HP regeneration | not started |
| 7 | Staff spells and weapon ultimates (Z / X / C) | not started |
| 8 | New region: waterfall, river, bridge, fishing spot, gateway | not started |
| 9 | Dungeon, Bestiary enemies, dragon boss (bite, breath, AoE), HP bar, rewards | not started |
| 10 | Dragon companion: base placement, Earthquake, Fire, summon, mount and flight | not started |

## 1. Controls
- `project.godot`: `toggle_map` Tab, `toggle_equipment` Q, `package_shield` R, new
  `quick_switch_tool` T and `jump` Ctrl. No key is bound to two gameplay actions (Shift is
  run and dash on purpose).
- **Map on Tab:** Tab is also the GUI's focus-next key, so `MinimapController` reads
  `toggle_map` in `_input` (before a focused button takes it) and consumes it only when the
  map opens or closes. Escape still closes it.
- **Inventory on Q:** `EquipmentUI` opens/closes on `toggle_equipment`; while open, T switches
  its two views.
- **T quick switch:** `CourierInventory.last_weapon` / `last_tool` (set by `equip`, saved)
  and `toggle_tool_weapon()` / `get_switch_target()`: with a tool in hand T takes up the last
  weapon, otherwise the last tool (the first owned one when none is remembered).
  `QuickWeaponBar` handles the key (refused in windows, dialogue, knockout) and shows WEAPON
  MODE / TOOL MODE beside the item name; its tooltip names the item T switches to. The hand
  model, attack style (TOOL vs weapon) and enhancement bonuses follow `EquipmentStats` as
  for any equip.
- **Jump:** `PlayerController.jump_velocity` 4.8 m/s (about 1.2 m), ground only (no double
  jump), 0.1 s coyote time, 0.12 s press buffer; `jumped` / `landed` signals; `PlayerAnimator`
  plays `move/Jump_Start` and `move/Jump_Land` around the existing airborne loop. Off while a
  window is open. Attacks work mid-air; Shift still dashes.
- **Key guide:** three short rows (E Q T R / Tab J Ctrl / Shift Space) so it stays as narrow
  as before and clear of the HUD at 1024x600.
- Tests: new `tests/phase8_controls_tests.gd` (bindings, Tab map with a focused button, M
  free, Q inventory, T with hand model / attack style / HUD / save / refusal, jump height,
  no double jump, running jump, mid-air attack, dash, no jump in windows). Updated for the
  new keys: `phase4_gameplay`, `keycap`, `phase4_hud_polish`, `input_prompt`,
  `phase7_inventory_farming`, `weapon_quick_switch`.
- Rendered: `tests/capture_phase8_controls.gd` -> `docs/validation/phase8/01..06` (weapon
  mode HUD and key guide, Tab map, Q inventory, T inventory view, T pickaxe in hand, Ctrl
  jump in mid-air, 1.14 m measured).
