# Phase 7: village, Whisperwood, inventory, farming, enhancement VFX and the dragon

Branch `phase5f-integrated`, Godot 4.7.2, Blender 5.2.2 LTS
(`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`). Screenshots are in
`docs/validation/phase7/` (`00_before_*` were taken before any Phase 7 change).

| Milestone | Scope | Status |
|---|---|---|
| A | Guild board, exhibit removal, NPC facing, village roads, Whisperwood relocation | **Done** (this document, section A) |
| B | Inventory redesign + Q view switch, farming near spawn | **Done** (section B) |
| C | Armor, enhancement at Brenna, weapon/armor enhancement VFX, skill VFX timing | **Done** (section C) |
| D | Dragon boss | not started |

## A. Village and Whisperwood

### Courier Guild board
- New model built in Blender by `tools/build_phase7_props.py` (run
  `blender --background --factory-startup --python tools/build_phase7_props.py -- courier_guild_board`):
  posts on stone footings, a plank board in a frame with brass corners, seven pinned parchment
  notices (ink lines, wax seals, pins), a rolled scroll, inkpot and quill, a shingled gable roof,
  a header plank with the guild emblem (blue disc, brass rim, envelope and wings) and a lantern.
  Source `assets/blender/phase7/courier_guild_board.blend`, export
  `assets/generated/phase7/courier_guild_board.glb` (2520 triangles).
- `scenes/gameplay/world/quest_board.tscn` now instances the GLB with one box collider and one
  Interactable (`metadata/prompt_anchor_height = 2.2` so the keycap clears the roof).
- It moved out of the cramped post-office corner to the plaza beside the post-office gate:
  `PostOffice/Markers/QuestBoardSpot` is at world (-3, 0, -4), turned 45 degrees so its notices
  face the isometric camera.
- The cyan route beam and the second floating name over the board are gone: the Phase 4
  delivery integration no longer shows its route marker or destination beam when the target
  is the board (`phase4_delivery_integration.gd`, `encounter_presentation.gd: clear_destination`).
  The interaction prompt is the only label.

### Cargo exhibit
`PostOffice/Phase3Showcase` (the Dragon Egg / volatile potion display) is removed from
`post_office.tscn`. Its scene (`scenes/gameplay/phase3_visual/phase3_showcase.tscn`), scripts
and package data stay; the tests that used it instance it standalone. The real Dragon Egg
pickup is untouched.

### NPCs face the courier
`scripts/npc/npc.gd`: talking to an NPC (its Interactable) makes it turn smoothly
(`turn_sharpness` 5, `lerp_angle` on the visual's Y rotation only) towards the courier. It keeps
facing them for `attention_seconds` (6 s) or as long as a dialogue line or a modal window
(shop, board) is open, while they stay within `attention_range` (4.5 m), then turns back to
the facing it was placed with. NPCs never track passers-by. Brenna (Armory) and Hobb (tool
stall) had been placed facing away from their counters; both are turned 180 degrees in their
generators (`tools/generate_armory.gd`, `tools/generate_tool_sites.gd`) and their serving
point moves to the customer side.

### Village roads
- The three cobbled roads out of the plaza are wider (market and forest roads 3.2 -> 4.4 m,
  south road 2.6 -> 3.4 m), as are the forest lane (3.2 m) and the Whisperwood trail (3.4 m):
  `python tools/edit_village_splat.py phase7-roads`, widths in `village_layout.json`.
- Props that the wider roads now covered moved to the verges (`Props/Lamp2`, `Props/Lamp5`,
  `Props/Crate1`). `phase5e_village_tests` checks every collider against road and lane cores,
  now including the forest annex.

### The Whisperwood moved north
- `ForestEntrance` moved from (14, 0, -20) to **(14, 0, -90)**; Mage Elowen to (16.2, 0, -102.4);
  the Dragon Egg run's slime and wisp spawns moved with it. The forest zone covers x -19..43,
  z -123..-51; Whisperwood Edge (discovery) is at the new edge gate (14, -54).
- The village grew an annex north of its old wall: terrain `mesh_rect` and `flat_rects`
  (`village_terrain.gd` now supports several flat rectangles), boundary walls, a second
  ground collider (`Ground/AnnexCollisionShape3D`; without it the courier fell through the
  forest), the exploration `WORLD_RECT` (-64, -128, 128, 192; saved 64x64 fog grids are
  remapped), the splat maps (now 1536 px over x -96..96, z -128..64; ground material
  `splat_origin`/`splat_size`) and the baked world map (`tools/bake_world_map.gd`).
- A 3.4 m dirt trail runs ~45 m from the old forest lane at (14, -28.6) through open outskirts
  to a timber edge gate and "Whisperwood" signpost at (14.4, -51.8), then winds through the wood
  to the old stone forest gate at (14, -90) and the Moonstone Clearing. Side paths lead to a
  fern glade (-2, -80) and a hollow glade (35, -90).
- `tools/generate_whisperwood.gd` -> `scenes/environment/whisperwood_forest.tscn` (instanced in
  `village.tscn` as `WhisperwoodForest`; generated, change the generator): 164 trees from 16
  Quaternius models (pine, common, birch, autumn, willow and dead trees; each a StaticBody
  with a trunk collider and a CameraOccluder), denser away from the paths and thinning over
  the outskirts; trees keep 3.5 m from walkable ground on the camera side so canopies do not
  hide the courier; 1680 bushes, berry bushes, ferns, grass and flowers as ScatterField
  multimeshes; 26 rocks, 12 mossy logs, 22 mushroom clusters and 7 glowing ones; a FogVolume
  over the wood (the village fog density stays 0) and fireflies over the glades and the
  clearing. The generator keeps clear of every existing collider, the portal, Elowen and the
  encounter spawns.
- The Dragon Egg walk is now ~115 m, so the egg cools more slowly (0.5 -> 0.3 degrees/s): the
  walk takes ~23 s of its 50 s in the safe band.

### Tests and validation (Milestone A)
- New `tests/phase7_village_tests.gd` (39 checks): board model, no beam or floating labels,
  one prompt, placement and facing; exhibit removed but sources kept; Bram ignores
  passers-by, turns smoothly about Y to the courier he talks to and back; Brenna and Hobb face
  their counters and turn while trading; forest position, density, variety, undergrowth,
  props, gate, thinning, mist, fireflies; nothing solid on the forest paths; the courier stands
  on the clearing; map rect and baked map; the Dragon Egg time budget.
- Updated for the new layout: `phase3_tests` (egg cooling rate), `phase4_hud_polish_tests`,
  `phase5a_asset_tests` (walks to the forest follow the trail), `phase5b_environment_tests`,
  `phase5e_village_tests` (splat geometry read from the material, annex flat and grounded,
  road check covers the annex), `world_ui_tests`, `village_quest_tests`,
  `input_prompt_tests` (board anchor height) and the older capture scripts' forest positions.
- `tests/capture_phase7_screenshots.gd` renders `docs/validation/phase7/01..15`.
- All 34 suites passed at the Milestone A commit; headless boot of the main scene for 180 frames
  printed no errors or warnings.

### Limitations (Milestone A)
- No navigation mesh exists in the project (NPCs do not path-find), so there was none to update.
- Village "courtyards": the plaza and post-office forecourt were kept; the pass widened roads
  and cleared them rather than moving houses again (Phase 5H already spaced them).
- The forest is static: trees are individual nodes (occluder fading needs that); the scene has ~750 nodes.

## B. Inventory and farming

### Inventory window (Tab)
`scripts/gameplay_ui/equipment_ui.gd` (class `EquipmentUI`, same API as before) was rebuilt:
- A slate frame and parchment page from the Humble Pixel inventory pack (pieces cropped by
  `tools/prep_inventory_ui.py` into `assets/ui/inventory/`), side tabs, a title and gold.
- **Two views**: *Weapons & Gear* (weapons, then off-hand and armor) and *Tools & Goods*
  (tools, then seeds, produce and materials with counts). **[Q] switches the view while the
  window is open** (the side tabs too). Q stays the Package Shield key in play: the window
  consumes Q in `_input` before the shield sees it (and the courier's input is paused while
  it is open), and with the window closed Q raises the shield as before (tested both ways).
  Hints come from `InputHints.key_for(&"package_shield")`.
- Item cells show the icon, name, enhancement badge (+1..+5 in the level colour), E for
  equipped and the quick-slot number; unowned items are dimmed. The detail pane shows stats,
  description, enhancement stars and tier, status and the actions (Equip/Unequip, quick slots
  1-5). Selecting a seed makes it the one garden beds plant first.
- One inventory: everything is read from and written to `CourierInventory`; no second store.

### Enhancement data
`CourierInventory` now stores an enhancement level 0..5 per owned item
(`get_enhancement`, `set_enhancement`, `enhancement_changed`, saved under
`inventory.enhancements`). `scripts/inventory/enhancement.gd` holds the rules (colours
white/silver, green, blue, purple, gold; tier names; damage +10 % per level; defense +2 per
level). How levels are gained and what they do in combat is Milestone C.

### Farming: the Courier's Garden
- `MaterialItem` gained kinds SEED and PRODUCE and a `buy_price`. Data: `data/materials/`
  wheat/carrot/pumpkin seeds (1/2/5 g) and produce (sell 2/4/14 g); crops in `data/crops/`
  (`CropDefinition`: seed, produce, yield, 3 stages of 40/60/90 s, Quaternius crop model).
- Hobb (Toolwright) sells seeds (`ShopCatalog.sells_materials`, `ShopService.buy_material`,
  "Buy 1 / Buy 5" rows in the shop) and buys produce. Seeds cannot be sold back.
- `FarmService` (GameplayServices) owns all garden state on its own **play-time clock**
  (saved; system clock changes or time with the game closed never ripen crops). Planting
  takes exactly one seed and refuses an occupied bed; harvesting needs a ripe crop and room
  in the stack, pays yield once and empties the bed; unknown crops in a save are dropped and a
  planted time after the saved clock counts as just planted. Saved under `"farming"`.
- `FarmPlot` (`scenes/world/farm/farm_plot.tscn`): a Blender-built raised bed
  (`garden_bed.glb`) whose plants show the stage: seedlings (`crop_seedling.glb`), then the crop
  model at 45 %, 75 % and full size, with a small pop as it grows. Prompts: "Plant Wheat Seeds
  (n)", "Wheat · ripe in 0:40", "Harvest Wheat"; results go to the toasts.
- `scenes/world/farm/courier_garden.tscn`: four beds and a signpost on the lawn south of the
  post office (world (-13, 0, 9), ~15 m from the spawn point, in view of the camera).
- Chop and mine near the spawn: `ToolSites/OfficeTree` (woodcutting, (-26.9, -9)) and
  `ToolSites/OfficeRock` (pickaxe, (-14.8, -16.6)) are HarvestNodes, so they regrow on the
  existing GatheringService timer (180 s) and their depletion is saved.

### Tests and validation (Milestone B)
- New `tests/phase7_inventory_farming_tests.gd` (56 checks): views and [Q], window size,
  tabs, one inventory, Q never raises the shield while the window is open but still does when
  it is closed, enhancement levels (cap, ownership, save/load) and their display, seed shop
  (gold check, Armory sells none, no sell-back), garden layout near spawn, plant/stage/grow,
  preferred seed, harvest once, unripe refused, selling produce, farm save/load and the
  clock-exploit cases, chop/mine near spawn with regrowth.
- Updated: `tool_system_tests` (two more tool targets, produce sell rows, the window's
  sections), `phase6_tools_tests` (sell rows).
- `tests/capture_phase7_inventory_farming.gd` renders `docs/validation/phase7/16..22`.
- All 35 suites pass (2781 checks); clean headless boot.

### Limitations (Milestone B)
- Crops grow only while the game runs (by design, see above).
- There is no watering or soil quality; the garden is four beds.
- Two beds sit partly behind a cottage from the camera; that cottage fades (CameraOccluder).

## C. Armor, enhancement and skill VFX

### Armor and defense
- `ItemDefinition.Slot.ARMOR` (appended; saves store slot names) and a `defense` stat. Brenna
  sells the **Leather Vest** (defense 4, 120 g) and **Iron Mail** (defense 8, 320 g); the
  Wooden Shield now gives defense 2. Armor shows under "Gear" in the inventory window, is
  worn (no held model) and leaves both hands alone.
- `EquipmentStats` sums the defense of the shield and armor plus `Enhancement.defense_bonus`
  (+2 per level) into `CombatController.defense`. `reduce_by_defense()` runs first in the
  damage interceptor: damage x 20 / (20 + defense), at least 1. A 10 damage hit: 10 bare,
  8.33 in a +0 vest, 5.88 in a +5 vest, 4.00 in +5 mail with a +5 shield.
- The main-hand weapon's level multiplies its damage by 1 + 0.1 x level (sword/axe melee,
  bow arrows, staff bolts; bare-hand bolts are unaffected).

### Enhancing at Brenna
- The Armory catalog has `enhances_items`; the shop shows "Enhance your gear" with a row per
  owned weapon, shield and armor (never tools). A step from +L costs 60 x (L+1) gold and L+1
  iron ore; `ShopService.enhance` checks both first and takes them together or not at all.
  +5 is the cap (the button reads Max). Levels are saved (CourierInventory).

### Enhancement effects (`scripts/vfx/`)
- `EnhancementVisuals` (GameplayServices) rebuilds the effects whenever the equipment, a
  level, a held model or the setting changes (including after a load). Effects are children
  of the player or of the held models, so they follow swings, teleports and region changes.
- **Weapon** (`EnhancementGlow`, under the held model, along its longest axis from grip to
  tip, in `Enhancement.level_color`): a soft sheen that brightens per level, plus +1 two
  sparkles (silver), +2 three (green), +3 an aura (blue), +4 four sparkles and a coloured
  light (purple), +5 golden: five sparkles, aura, light and a burst at the tip every 1.8 s.
  An enhanced shield glows the same way; a tool in hand shows nothing.
- **Armor**: the Binbun StatusFX shatter effect around the body (0.9 m up, scale 0.85),
  recoloured per level, 16-40 particles and brighter with the level; its light streaks are
  the +5 crown.
- Flipbooks are `VfxStrip` (Sprite3D, additive unshaded billboard, 15 fps) on the
  Gigapack strips in `assets/vfx/enhancement/`.
- **Toggle**: "Show enhancement effects" (CheckButton in the inventory window footer) sets
  `UISettings.SHOW_ENHANCEMENT_VFX` (default on, saved in `user://ui_settings.cfg`). Hiding
  removes every effect node; damage and defense bonuses are unchanged.

### Attack timing
- Measured before: the axe's hit landed at 0.35 s but its chop pose struck at ~0.72 s; the
  sword hit ~0.07 s before its reach; bolts and arrows left at the start of a wind-up.
- `KayKitCharacter.play_once_strike(action, strike_in, speed)` plays a one-shot so its strike
  (`CLIP_IMPACT`: throw 58%, interact 36%, use-item 41%) lands strike_in seconds later (speed
  chosen for that, max 5x, else the clip starts part-way). `PlayerAnimator` uses it with
  `melee_windup` for swings and 0 for bolts/arrows (the pose is at its release as the
  projectile leaves). The gameplay hit time is unchanged; only the animation moved.
- `AttackEffects` (GameplayServices): a BattleFX swing arc starts with the swing and sweeps to
  its fullest at the hit (speed = 0.25 s / windup); a level arc for swords, a vertical chop
  for the axe, in the weapon's enhancement colour; a cancelled swing removes its arc. An
  impact flash plays on the attacker's side of the target on `target_hit` for melee and
  arrows. The Magic Bolt keeps its own projectile and burst.

### Tests and validation (Milestone C)
- New `tests/phase7_enhancement_tests.gd` (119 checks): armor slot via the inventory window,
  defense numbers, weapon damage per type and a real +5 swing, Brenna's enhance flow through
  the real interact key (no ore, 59 gold, +0 -> +1 costs, +1 -> +5 totals 840 g / 14 ore, cap,
  armor), save/load of armor and levels, weapon effects at each level, shield glow, tool in
  hand, armor aura at each level and after a teleport, the toggle (hidden effects keep the
  bonuses, survives reopening), swing pose / arc / hit within one frame for sword and axe,
  release pose for bow and staff, impact flashes, cancelled swing.
- Updated: `armory_shop_tests` (nine items, armor prices and slots, enhance flag),
  `equipment_visual_tests` (armor is worn, not held; it keeps both hands).
- `tests/capture_phase7_enhancement.gd` renders `docs/validation/phase7/23..39` (1600x900, GPU,
  real attack key for the swings): weapon +1..+5, armor +1/+3/+5, all +5 at play zoom, the
  toggle on/off, effects hidden, Brenna's Enhance section, sword and axe at the hit frame and
  0.1 s later (impact flash).
- All 36 suites pass (3033 checks); clean headless boot.

### Limitations (Milestone C)
- The +1 armor aura is subtle (silver on a light scene); +1 weapon sheen is clearer.
- The "aura" strip is the Gigapack's lightning crackle, so +3 and above read as electric.
- The FREE animation pack still has no real swing clips; strikes are timed on Interact/Throw.
- Not playtested by a person; effect brightness was judged from rendered captures only.
