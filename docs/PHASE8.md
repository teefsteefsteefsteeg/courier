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
| 2 | Resource respawn without countdowns; tools in every map | **Done** (below) |
| 3 | Weapon enhancement VFX rework (+1 silver spark .. +5 legendary elemental) | **Done** (below) |
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

## 2. Natural resource respawn and tools in every map
- **No countdown:** `HarvestNode` draws a random hidden respawn time between
  `respawn_min_seconds` and `respawn_max_seconds` (trees 180-300 s, ore rocks 240-360 s, soft
  soil 120-240 s; set by `tools/generate_tool_sites.gd`) at each depletion. A depleted node
  shows its depleted look (stump, rubble, dug soil) and its prompt says only "regrowing" /
  "the ore will return" / "settling" (or "used up" for nodes that never return).
- **State:** unchanged design: `GatheringService` keeps one unix timestamp per `target_id`,
  so every node has its own timer, nothing resets on a region change, saves keep it, and a
  depleted node pays nothing (no duplicate reward).
- **Fix found by the new test:** a region kept out of the tree by `WorldRouter` refreshed its
  nodes while away (a save/load emits `changed`), found no service and showed them as
  available again. `ToolTarget` now refreshes when it re-enters the tree, and `HarvestNode` /
  `RepairSite` ignore refreshes while outside it.
- **Tools in every map:** the tool system was already group-based (no village paths); two
  gaps were closed. `ToolUser.find_water` ignores hidden water (the paused village pond
  shares coordinates with other regions), and the "nothing here" hints no longer point only
  at village places. Generated regions get their tool sites from a separate scene that
  `WorldRouter` adds on first load (`REGION_TOOL_SITES`); its `GroundSnap` root
  (`scripts/world/ground_snap.gd`) places every child on the terrain after the colliders
  exist. `scenes/world/tools/runewood_tool_sites.tscn`: two marked trees, two ore rocks,
  soft soil, and `RiverWater` (`scripts/world/river_water.gd`, a Pond whose open water is a
  strip along a centreline traced from the Runewood height field; no geometry of its own)
  with the "Moonbrook" bank FishingSpot. Region-prefixed `target_id`s (`runewood_tree_1`...).
- Tests: new `tests/phase8_resources_tests.gd` (village rock: no countdown on prompt or HUD,
  hidden time within range, random times, no second reward, regrows on time; Runewood
  sites: six unique ids, on the terrain; axe / pickaxe / shovel / rod through the real
  interact key there; hidden village pond and dry bank are not water; depletion across
  region changes and save/load). `tool_system_tests` updated (prompt and random time).
- Rendered: `tests/capture_phase8_resources.gd` -> `docs/validation/phase8/07..12` (village
  rubble prompt, Runewood marked tree, chopping, stump "regrowing", mining, Moonbrook
  fishing with the bobber in the river).

## 3. Weapon enhancement VFX rework
Before: every level was the same sparkle/aura glow in a different colour. Now each level is
its own composition of animated elements (`scripts/vfx/enhancement_glow.gd`, built under the
held model by `EnhancementVisuals`; `elements` lists them for tests):

| Level | On the weapon | Swing / hit (`AttackEffects`) |
|---|---|---|
| +0 Normal | nothing | plain arc, impact flash |
| +1 Silver Spark | spark bursts (Sci-fi Spark Burst) and glints along the blade, drifting silver motes | silver arc |
| +2 Nature Energy | green sparkle blooms (Round Sparkle Burst 002, own colours), leaf particles spiralling up | green arc |
| +3 Water | droplet swirl round the weapon (Spell Absorb, blue), bubbles at the tip, dripping water, blue light | blue arc, bubble trail, water splash on hit |
| +4 Lightning | violet crackle aura in two places (Lightning Aura), bolt flashes (Lightning Burst), flickering violet light | violet arc, lightning flash on the swing, electric strike on hit |
| +5 Legendary | three flames (Fire Looping 003A/004A, own colours) on the outer blade, violet lightning over them, a water ring and drips by the grip, rising embers, flickering fire light | gold arc plus a larger fire arc, lightning flash, explosion (Stylized Explosion) and electric strike on hit |

- **Assets:** `tools/prep_enhancement_vfx.py` now also builds `spark`, `nature_burst`,
  `swirl`, `bubbles`, `splash`, `bolt_flash`, `strike`, `flame`, `flame_b`, `blast` from the
  Gigapack (whitened for tinting, or own colours: `frames.json` `tinted`). Full-colour sheets
  draw with normal blending, tinted ones additively (`VfxStrip`). Particles (`CPUParticles3D`,
  world space so they trail behind a swing) use procedural dot and leaf sprites.
- **Placement by weapon type:** sword along the blade (30-100% of grip to tip), axe round the
  head (62-100%), staff at the top (72-100%), bow along both limbs (-90..90%), shield face.
- **Budget:** at most 6 flipbooks and 40 particles per weapon (measured: 18-30 particles).
- Unchanged: damage, enhancement stats, inventory, save/load and swing timing (tests check
  the hit damage and the strike timing at every tier).
- Tests: new `tests/phase8_weapon_vfx_tests.gd` (elements per tier, tiers don't share
  elements, all flipbooks animate, budgets, placement per weapon, still attached while
  running, tier trails and impacts with damage and timing, one-shots clean up);
  `phase7_enhancement_tests` weapon section rewritten for the tiers.
- Rendered: `tests/capture_phase8_weapon_vfx.gd` -> `docs/validation/phase8/13..26`
  (Steel Sword +1..+5 close up, the same sword just after a real Space-key hit at every
  tier, axe +5, bow +4, staff +3, axe +2) and `27_weapon_tiers_side_by_side.png`.
- Known: from the default camera the bow is held in front of the body, so its effects are
  mostly hidden behind the courier when idle (the light still shows); +1 is deliberately the
  quietest tier.
