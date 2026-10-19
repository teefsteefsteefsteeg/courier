# Mystic Courier

Isometric 3D fantasy courier game: deliver parcels, a dragon egg and volatile potions around the
village of Willowmere and the Whisperwood, fight forest creatures with a Magic Bolt, earn gold and
reputation, and spend gold on weapons at the Armory.

- **Engine:** Godot **4.7.2** (Forward Plus). Executables: `D:\godot\Godot_v4.7.2-stable_win64.exe`
  (windowed) and `D:\godot\Godot_v4.7.2-stable_win64_console.exe` (console; use it for headless
  runs and tests).
- **Main scene:** `res://scenes/levels/village.tscn` (village, post office, forest entrance and
  Armory in one scene).
- **Language:** GDScript, statically typed. The project treats "type inferred from Variant" as
  an error, so type ternaries over different classes explicitly.
- **Detailed state and history:** `docs/DEVELOPMENT_HANDOFF.md` (read it first in a new session),
  plus the per-phase docs in `docs/PHASE*.md`.

## Repository and worktrees
- `D:\courier` is the main checkout (`main`, at `d87a7da`, far behind). **Do not modify it** unless
  explicitly asked.
- Each phase/role works in its own git worktree. Current ones for Phase 5F:
  | Worktree | Branch | Head | Role |
  |---|---|---|---|
  | `D:\courier-phase5f-integrated` | `phase5f-integrated` | this branch | **Current, playable integration** |
  | `D:\courier-phase5f-gameplay-ui` | `phase5f-gameplay-ui` | `f156aca` | Gameplay/UI role |
  | `D:\courier-phase5f-building-visual` | `phase5f-building-visual` | `c12261d` | Building/visual role |
- All three branch from `38be579` (Phase 5E). Nothing is pushed or merged to `main` yet.
- Never use bare `git stash`: the stash is shared across worktrees and sessions.
- Running Godot rewrites many vendor `assets/**/*.import` files with different line endings only
  (no content change). Don't commit that noise. Restore with
  `git checkout -- assets/characters assets/models assets/textures`.

## Commands (PowerShell)
```powershell
# Play the integrated game (debug build with a window = development mode: 500 starting gold)
& "D:\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\courier-phase5f-integrated"
# Start over (deletes user://savegame.json first)
& "D:\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\courier-phase5f-integrated" -- --new-game

$godot = "D:\godot\Godot_v4.7.2-stable_win64_console.exe"
# Import (after adding assets or a new class_name script, so the global class cache updates)
& $godot --headless --path . --import
# One suite (exit code = number of failed checks)
& $godot --headless --path . --script res://tests/player_animation_tests.gd
# Every suite
Get-ChildItem tests\*_tests.gd | ForEach-Object { & $godot --headless --path . --script "res://tests/$($_.Name)" *> "$env:TEMP\$($_.BaseName).log"; "$($_.BaseName): exit $LASTEXITCODE" }
# Boot the main scene headless for 180 frames (expect no ERROR/WARNING lines)
& $godot --headless --path . --quit-after 180
# Rendered screenshots (GPU window, not headless), e.g. the integrated walkthrough
& $godot --path . --resolution 1600x900 --script res://tests/capture_phase5f_integrated_screenshots.gd -- "$env:TEMP\shots"
```
Tests are `SceneTree` scripts in `tests/`. Headless runs default to a square 1600x1600 viewport,
so tests that check screen layout set `root.size = Vector2i(1600, 900)` first. `await
process_frame` resumes *before* that frame's `_process` callbacks, so UI updated in `_process`
needs one more frame.

## Architecture
`village.tscn` top level: `GameplayServices` (first child), `PostOffice`, `WhisperwoodForest`, `ForestEntrance`,
`Armory`, `VillageDressing`, `MegaKitPilotDressing`, `Player`, `IsoCameraRig`, `DebugHUD`,
`LocationBanner`, `InteractionPrompt`, `DialogueBox`, `GameplayHUD`, `QuestJournal`, `QuestBoardUI`,
`Phase4DeliveryIntegration`. NPCs live under `NPCs/` (Bram, Mira, Corvin, Elowen, Pip; Brenna is
inside `Armory`).

Services are per-level nodes in `scenes/gameplay/gameplay_services.tscn`, found by group with
`X.find(get_tree())`. There are **no autoloads**.
| Service | Script | Role |
|---|---|---|
| `QuestManager` | `scripts/quests/quest_manager.gd` | All quest state; one active delivery at a time; idempotent `grant_reward`; `retry_quest`; `restore_finished_quests` |
| `CourierWallet` | `scripts/quests/courier_wallet.gd` | Gold, reputation, courier rank (Novice to Renowned); `spend_gold`, `restore` |
| `CourierInventory` | `scripts/inventory/courier_inventory.gd` | Owned items (unique), MAIN_HAND / OFF_HAND / ARMOR equipment, enhancement levels, five quick slots (owned weapons and tools), stackable materials (`MaterialItem` counts, cap 999) |
| `EquipmentStats` | `scripts/inventory/equipment_stats.gd` | Applies equipped items to the player's `CombatController` (stats and attack style by weapon type; TOOL for a tool) and the held models |
| `ExplorationService` / `FastTravel` | `scripts/world/` | Phase 5G: location registry (`WorldLocation`), discovery, fog of war, portals |
| `GatheringService` | `scripts/tools/gathering_service.gd` | Phase 5H: depleted harvest nodes (real-time respawn), repaired structures (paid once), tallies |
| `FarmService` | `scripts/farming/farm_service.gd` | Garden beds, crops and their play-time growth clock (Phase 7) |
| `EnhancementVisuals` / `AttackEffects` | `scripts/vfx/` | Phase 7 C: enhancement glow/aura (toggle `UISettings.SHOW_ENHANCEMENT_VFX`), swing arc and impact flash timed to the hit |
| `SaveGame` | `scripts/core/save_game.gd` | `user://savegame.json`; autosave; **off in headless runs** |

Key gameplay scripts:
- **Player:** `scripts/player/player_controller.gd` (input -> camera-relative movement, `input_enabled`),
  `scripts/components/movement_component.gd` (IDLE/WALK/RUN/AIRBORNE), `interaction_detector.gd`,
  `scripts/characters/player_animator.gd` + `kaykit_character.gd` (animation; one-shots).
- **Combat:** `scripts/combat/combat_controller.gd` (primary attack by weapon: Magic Bolt, fast/heavy melee, arrow; Dash, Package Shield; Space / Shift / Q),
  `combat_health.gd`. Enemies `scripts/enemies/` (ForestSlime, FrostWisp) are spawned only during the
  Dragon Egg run in the forest by `scripts/phase4_integration/phase4_delivery_integration.gd`.
- **Tools (Phase 5H, `docs/PHASE5H_VILLAGE_AND_TOOLS.md`):** `ItemDefinition.tool_type` marks a
  tool (main hand, quick-slottable, never attacks: `AttackStyle.TOOL`, Space emits
  `tool_use_requested`). `scripts/tools/tool_user.gd` (Player child `ToolUser`) validates and runs
  jobs and fishing; world `ToolTarget`s (`HarvestNode`, `RepairSite`, `FishingSpot`, each with a
  stable `target_id`) and `scripts/world/pond.gd` (`Pond`, the only water). Tool sites are under
  `ToolSites` in the village; the Toolwright's stall is `scripts/world/tool_stall.gd`.
- **Packages:** `scripts/packages/` (carrier, pickups, instances with temperature/instability).
- **NPCs:** `scripts/npc/npc.gd` (group `npcs`, `NPC.find_by_id`); child behaviours supply lines and
  prompt verbs: `scripts/quests/quest_npc_behaviour.gd` (quest markers `! ? ✓`, delivery, giver
  lines) and `scripts/shop/merchant.gd`.
- **Quests:** data in `data/quests/*.tres` (Q1 First Delivery 50 g, Q2 Dragon Egg 120 g, Q3 Unstable
  Potion 90 g), packages in `data/packages/`. `scripts/quests/quest_waypoint.gd` maps the current
  objective to a world node (minimap objective).
- **UI:** `scripts/gameplay_ui/` (GameplayHUD layout, tracker, wallet, toasts, board, ShopUI,
  QuickWeaponBar (bottom-right, keys 1-5), EquipmentUI (Tab inventory; [Q] switches Weapons & Gear / Tools & Goods while open), ToolActionHUD (bottom centre, tool
  jobs and fishing), MovementGuide), courier status panel `scripts/phase4_visual/combat_hud.gd` (top-left: portrait,
  rank badge, HP, shield energy, reputation; pushed by the combat visual adapter), `scripts/ui/` (interaction prompt, dialogue box, journal, location banner,
  UISettings, `input_prompts/`), minimap `scripts/phase4_integration_visual/minimap_controller.gd`.
  Modal windows (journal, quest board, shop, expanded map) join group `ui_modal`, pause the
  player, and refuse to open over each other.
- **Input prompts:** `InputPromptIcons` (InputMap binding -> 32 px keycap in
  `assets/ui/input_prompts/icons/`), `InputPrompt` component (`scenes/ui/input_prompt.tscn`),
  `InputPromptLabel` (draws a Label's `"[E] ..."` text with keycaps while keeping `label.text`).
  Hint text always comes from `InputHints.key_for(action)`; never hard-code keys.
- **Shop:** `ItemDefinition` / `ShopCatalog` (`scripts/shop/`, data `data/items/`, `data/shops/armory.tres`),
  `ShopService` purchase rules, `ShopUI` (`scenes/gameplay/ui/shop_ui.tscn`, instanced in
  `gameplay_hud.tscn`). The visual `Armory` (`scripts/world/armory.gd`) and the `ToolStall`
  (group `shop_locations`, catalog `data/shops/toolwright.tres`) get their Merchant attached at
  runtime by `ShopUI._attach_armory_merchants()`. A catalog with `buys_materials` adds a Sell section.
- **Dev mode:** `scripts/core/dev_mode.gd`: debug build with a window. Override with `-- --dev` / `-- --no-dev`.

Bindings (from `project.godot`): WASD move, Shift run **and** dash, E interact, G drop package,
Space attack (bolt / melee / arrow by weapon; with a tool in hand: use the tool), 1-5 weapon/tool quick slots, Tab equipment, Q package shield (switches inventory views while the inventory is open), J journal, M map, mouse wheel or `=` `-` zoom, F3 debug HUD,
Esc close (`ui_cancel`).

## Assets
`assets/models/quaternius/` (CC0 village/nature), `assets/models/megakit/` (MegaKit buildings and
nature), `assets/models/kaykit_weapons/` (Armory displays), `assets/models/kaykit_rpg_tools/`
(RPG Tools Bits: held tools and stall dressing), `assets/characters/kaykit_adventurers/`
(rigged characters, animations, sword/staff props), `assets/ui/input_prompts/` (prompt sheet and
cropped icons), `assets/ui/item_icons/` (placeholder shop icons), `assets/materials/`. Every
asset and its licence is in `ASSET_MANIFEST.md`; keep it updated. Generators:
`tools/crop_input_prompts.py`, `tools/make_item_icons.py`, `tools/prep_megakit_buildings.py`
(Python), and `tools/generate_buildings.gd`, `tools/generate_armory.gd`, `tools/generate_tool_sites.gd`,
`tools/generate_whisperwood.gd`, `tools/bake_world_map.gd` (Godot, headless), and
`tools/build_phase7_props.py` (Blender 5.2.2, `blender --background --factory-startup --python`).
Some scenes (`scenes/buildings/*`,
`scenes/locations/armory.tscn`, `scenes/props/armory/*`, `scenes/world/tools/*`,
`scenes/locations/willowmere_pond.tscn`, `scenes/locations/tool_stall.tscn`,
`scenes/environment/whisperwood_forest.tscn`) are **generated**:
change the generator, not the scene. The terrain splat maps have no generator; edit them with
`tools/edit_village_splat.py` and record lanes in `village_layout.json`, then re-bake the world map.

## Status
**Phase 7 in progress** (`docs/PHASE7_WORLD_AND_SYSTEMS.md`): Milestone A (guild board on the
plaza, exhibit removed, NPCs face the courier, wider roads, Whisperwood moved to (14, 0, -90)
inside a generated forest annex north of the village) and Milestone B (two-view inventory
with [Q] switching views while open, enhancement levels, `FarmService` + `FarmPlot` garden)
and Milestone C (armor slot and defense, enhancing at Brenna, weapon/armor enhancement VFX
with a hide toggle, attack poses and swing VFX synced to the hit) are done; D is not started.
Phases 5G (map, portals) and 5H (village spacing, faster courier, RPG tools) are committed on
`phase5f-integrated`, and every automated check passes on the committed tree (30 suites, 2614
checks, clean boot). It has **not been played by a person**. See `docs/DEVELOPMENT_HANDOFF.md` for what is complete,
known issues and next priorities.

## Working rules
- Run the relevant suites (and ideally all) before committing. Every bug fix gets a regression test.
- Verify UI visually with a rendered capture (GPU window, 1600x900); headless can't show layout.
- Preserve other roles' work: on a role branch, don't edit the other role's files. Do
  cross-cutting wiring on the integration branch.
- Commit only when asked or when the task says so. Never push or merge to `main` without explicit
  instruction.
