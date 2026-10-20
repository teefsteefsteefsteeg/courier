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

- **Controls revision (later the same day, user request):** M world map, Tab inventory, Q
  tool/weapon quick switch (and the inventory's view while it is open); T is free again.
  Sections 1-5 below describe the first layout (Tab map, Q inventory, T switch).

## Status
| # | Milestone | Status |
|---|---|---|
| 1 | Controls: M map, Tab inventory, R shield, Q tool/weapon switch, Ctrl jump | **Done** (below; revised layout in section 1b) |
| 2 | Resource respawn without countdowns; tools in every map | **Done** (below) |
| 3 | Weapon enhancement VFX rework (+1 silver spark .. +5 legendary elemental) | **Done**, then **reworked per weapon** (`docs/WEAPON_ELEMENTAL_VFX.md`: sword fire, axe earth, bow wind/lightning, staff arcane; +5 ultimates on C) |
| 4 | Animated HUD avatar | **Done** (below) |
| 5 | Enterable houses (Armory, Post Office, one home) with NPCs | **Done** (below) |
| 6 | Food market, consumables, food slots 6-0, MP and rage, HP regeneration | **Done** (recovery milestone 1 below) |
| 7 | Staff spells and weapon ultimates (Z / X / C) | **partly**: the four +5 ultimates on C now cost rage and leave world-space effects (recovery milestone 1); staff bolts and the Arcane Storm spend real MP; Z / X skills not started |
| 8 | New region: waterfall, river, bridge, fishing spot, gateway | **Done**, then made **seamless** (recovery milestone 2: Wyrmfall is part of the open world, no gate) |
| 9 | Dungeon, Bestiary enemies, dragon boss (bite, breath, AoE), HP bar, rewards | **started** (uncommitted: dragon model with authored Bite/Breath/Slam/Hit/Roar/Death, boss VFX vendored; no dungeon or boss script yet) |
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

## 4. Animated HUD avatar
- `scripts/gameplay_ui/animated_portrait.gd` (`AnimatedPortrait`, a SubViewport): renders the
  player's own model (the KayKit Ranger the Player uses) head and shoulders, framed like the
  old still portrait, in its own tiny world (8 meshes, two lights, no shadows), 128x128, one
  render every other frame (about 30 fps). `CombatHUD` shows its texture in the round frame
  (the still `courier_portrait.png` stays as the fallback).
- Alive: the idle clip breathes and moves the head; every 3.5-7 s it glances left or right.
- Reactions: a hit plays `Hit_A` and the portrait flushes red; at 25% health or less the
  idle slows to 0.6x, the courier sags forward and the portrait pulses red; healing restores
  it; a quest reward (`QuestManager.quest_rewarded`) plays a cheer (the FREE pack has no
  cheer clip: `Spawn_Air`, a happy hop). Boss victory will call `celebrate()` too.
- Fix during the work: the HUD's heal flash must stay the `elif` of the damage branch (a
  misplaced insert briefly turned it off; `status_hud_tests` caught it).
- Tests: new `tests/phase8_avatar_tests.gd` (live texture in the frame, the player's model,
  budget, idle motion, glance, flinch + red, low + sag + pulse, recover, cheer).
- Rendered: `tests/capture_phase8_avatar.gd` -> `docs/validation/phase8/28..32` (nine
  portrait crops over 2.7 s of idling, all different; idle HUD; hit; low health; cheer).

## 5. Enterable houses and interior NPCs
- **Doors** (`scripts/world/house_door.gd`, `village.tscn` `HouseDoors/`): "[E] Enter ..." at
  - the Armory's entrance (4.4, -14.35) -> **Brenna's Forge** (`interior_armory`);
  - a new door in the Post Office's north wall (-17.5, -10.55) -> **the Courier Guild Hall**
    (`interior_guild_hall`; the post office itself was already an open walk-in hall);
  - Rose Cottage's front door (-9.53, 16.2) -> **Rose Cottage** (`interior_rose_cottage`).
- **Routing:** interiors are `WorldRouter` regions (`INTERIORS`): the village is paused and
  hidden, the player, services, HUD, inventory and a carried package stay; the router keeps
  the door's Exit marker and puts the courier back there on leaving ("[E] Leave ...", the
  room's exit door, `InteriorRoom.leave`). Indoors there is no minimap or world map and the
  village's fog of war is untouched; a knockout indoors returns the courier outside the door.
- **Rooms** (generated: `tools/generate_interiors.gd` -> `scenes/interiors/*.tscn`, root
  script `scripts/world/interior_room.gd`): MegaKit floor and walls, glazed windows with a
  daylight panel, full-height north/west walls and low south/east walls (the iso camera
  looks from +X/+Z, so nothing tall stands between it and the courier), full-height
  invisible colliders, warm lights and an environment of their own. Furniture: Quaternius
  Fantasy Props MegaKit (CC0), copied by `tools/copy_fantasy_props.py` to
  `assets/models/fantasy_props/` (textures downscaled to 1024 px).
- **People and purpose:**
  - *Forgemaster Torvin* (Brenna's Forge, hearth fire `scripts/world/hearth_fire.gd`): his
    Merchant (attached at runtime by `InteriorRoom`, catalog `data/shops/forge.tres`) opens
    the shop with only the Enhance section: weapons, shields and armor for gold and ore.
  - *Guild Clerk Ivy* (Courier Guild Hall): giver of the new contract **The Sealed Letter**
    (`data/quests/q004_sealed_letter.tres`, 70 g, 6 rep): talk to Ivy, take the letter from
    her desk (`pkg_sealed_letter`), deliver it to Granny Hollis.
  - *Granny Hollis* (Rose Cottage): the letter's recipient, and her spare bed
    (`scripts/world/rest_bed.gd`) restores full health ("You're not tired." at full).
  - NPCs face the courier while talking (the existing NPC turn).
- Tests: new `tests/phase8_interiors_tests.gd` (58: doors and doorsteps, real E in and out,
  same door on return, things carried along, village paused, no maps, walls hold, nothing
  tall on the camera side, one NPC and lights per room, the whole Sealed Letter contract,
  Ivy turns to the courier, Torvin enhances for gold and ore, bed heals, knockout inside).
- Rendered: `tests/capture_phase8_interiors.gd` -> `docs/validation/phase8/33..45` (each door
  outside, inside, talking, the letter picked up and delivered, resting, Torvin's forge
  shop, back outside the same door).

## 8. Wyrmfall Vale (new region)
- **Getting there and back:** a timber gate with a "Wyrmfall Vale" signpost on Willowmere's
  south edge (`WyrmfallGate` in `village.tscn`, at (3, 0, 41.2)): "[E] Travel to Wyrmfall
  Vale". In the vale, the gate in the south-west corner ("[E] Travel to Willowmere") puts
  the courier back at the village gate. Both are `RegionGate`s (`scripts/world/region_gate.gd`,
  a generic "travel to region" door like `HouseDoor`). The router clears the village trees
  in the gate's passage at start-up, as it does for the Runewood gateway.
- **Router:** `WorldRouter` knows region `wyrmfall` (`REGIONS`, `WYRMFALL`), keeps its map
  per region in `REGION_MAPS` (image, radius, centre, title, legend) and sends a knockout in
  the vale back to the vale's Arrival (`RECOVERY`). Same session rules as Runewood: the
  player, services, HUD and inventory stay; the village is paused; the vale is cached
  while away (a felled tree stays a stump); fog of war is kept per region.
- **Layout:** `scripts/world/wyrmfall_layout.gd` (`WyrmfallLayout`): one height function
  and the shared numbers (river and road polylines, pool, cliff, bridge, landmarks) used by
  the generator, the map image and the tests. 120 x 120 m lowland of rolling grass inside
  a ring of hills (walls at +-54 m); a 12 m plateau north of a cliff; its stream falls
  over the lip into the Falls Pool; the Wyrm River leaves the pool to the south-east; the
  road from the gate crosses the river on the Old Stone Bridge and ends at the foot of the
  Ember Cliffs in the east (the planned dungeon site).
- **Generator:** `tools/generate_wyrmfall.gd` builds `scenes/regions/wyrmfall_vale.tscn`
  (root script `scripts/world/wyrmfall_vale.gd`), `scenes/world/wyrmfall_gate.tscn` and
  `assets/generated/wyrmfall/` (terrain mesh and `HeightMapShape3D` from the same samples,
  newmap meshes with baked textures, bridge collider, `wyrmfall_map.png`):
  - Terrain: flat-shaded height field, sRGB vertex colours (grass, meadow, road, wet sand,
    river stones, banded cliff rock).
  - Water: pool disc, river ribbon and plateau stream with the vendored water kit lake
    shader (`assets/vfx/water_kit/`, greener/deeper colours, wind along the flow); the
    waterfall sheet (`assets/shaders/waterfall.gdshader`, scrolling noise streaks) traced
    down the cliff face 0.35-0.9 m in front of it, mist and spray particles and a foam disc
    at the plunge.
  - Walls (one invisible `ConcavePolygonShape3D`): boundary, cliff foot, pool rim, both river
    banks, open only where the bridge crosses.
  - Old Stone Bridge: newmap `Bridge01`; its stepped ends are not walkable, so the collider is
    a smooth deck traced from the mesh (2.6 m wide, ramps to the ground, railings). The road
    runs exactly north-east over it, one of the eight keyboard directions: at 12 degrees
    off, the courier rubbed along a railing and stopped (Godot's 15 degree
    `wall_min_slide_angle`).
  - Newmap pack (`assets/newmap/FreeVersion`, Alefran; raw pack not committed): fisher's
    camp (hut, stall, barrels, crates, bench, brazier with fire light, fence, ladder, wheel),
    road lamps with lights, the Drakeward Ruins (a broken ring of stone walls round a giant
    dead trunk), reeds by the river. Meshes are saved per model and their textures baked
    to 512 px lossy `PortableCompressedTexture2D` resources (normal maps dropped), so the
    vale needs nothing from the raw pack.
  - Quaternius Ultimate Nature trees (noise-driven groves, willows by the river, pines on
    the plateau and hills; trunk colliders and `CameraOccluder` inside the walls), rocks at
    the cliff foot, undergrowth `ScatterField`s.
  - Tool sites (region-prefixed ids): two trees, two ore rocks at the cliff foot, soft soil
    by the camp. Fishing: `RiverWater` for the river and the pool, FishingSpots "the Wyrm
    River" (bank by the camp) and "the Falls Pool" (more golden carp).
  - Three forest slimes on the far bank (over 9 m from any tool site).
  - Places (`WorldLocation`, region `wyrmfall`): Willowmere Gate, Wyrmfall, Old Stone
    Bridge, Drakeward Ruins, Fisher's Camp, Ember Cliffs; village side: Road to Wyrmfall.
- Tests: new `tests/phase8_wyrmfall_tests.gd` (53: layout, the real E key in and out at
  both gates, arrival, village paused and back, exploration region, terrain under every
  landmark, water and waterfall shaders, map, places and discovery, held-key walking over
  the bridge, river bank / pool rim / cliff / boundary hold, axe / pickaxe / shovel / rod
  at the vale's sites, knockout recovery, cached region on a second trip).
- Rendered: `tests/capture_phase8_wyrmfall.gd` -> `docs/validation/phase8/46..58` (village
  gate, arrival, falls and pool, bridge, camp, ruins, cliffs, overview, walking over the
  bridge with real keys, the Tab map, the gate back, back in Willowmere).
- Not yet: the dungeon entrance at the Ember Cliffs (milestone 9), a portal for fast travel
  inside the vale, the plateau is scenery only.

## 1b. Controls revision and bow effects
- `project.godot`: `toggle_map` M, `toggle_equipment` Tab, `quick_switch_tool` Q (T free).
- **Inventory on Tab:** `EquipmentUI` now opens in `_input` too (Tab is the GUI's focus-next
  key; it consumes the key only when the window actually opens), so a focused button can't
  swallow it. While open, Q switches its views; Tab or Esc closes it.
- **Map on M:** `MinimapController` keeps reading `toggle_map` in `_input`; `MinimapHUD`'s
  fallback key is M.
- **Key guide:** rows E Q R M / Tab J Ctrl / Shift Space (as narrow as before).
- **Bow enhancement effects visible:** the courier holds the bow across the body, so from
  the iso camera its effects were behind the courier. `EnhancementGlow` now draws a bow's
  flipbooks and particles over the body (`no_depth_test`, render priority 10) and 1.3x
  larger (`shows_over_body`); other weapons keep normal depth.
- Tests updated for the keys: `phase8_controls` (M map, Tab inventory with a focused button,
  T free, Q switch), `keycap`, `phase4_hud_polish`, `input_prompt`, `phase8_interiors`,
  `weapon_quick_switch`, `phase7_inventory_farming`; `phase8_weapon_vfx` checks the bow
  effects draw over the body at +1/+4/+5 and a sword's don't.
- Rendered: `tests/capture_phase8_controls.gd` (now the revised layout) ->
  `docs/validation/phase8/59..69` (key guide, M map, Tab inventory, Q view switch, Q pickaxe,
  bow +4 / +5 from the gameplay camera, running towards the camera, Ctrl jump).

## 3b. Weapon elemental rework and +5 ultimates
Every weapon class now has its own element and every level its own composition; normal
attacks get weapon-specific effects; a +5 weapon has an ultimate on [C] with real hit
detection. Full description, tables, tests and screenshots: `docs/WEAPON_ELEMENTAL_VFX.md`.

## Recovery milestone 1 (2026-10-19): world-space VFX, vitals, consumables
Brief "Phase 8 recovery" part A. Everything below runs from real gameplay events and is
covered by `tests/phase8_vitals_tests.gd` (115 checks) plus the updated older suites.

### World-space weapon effects (`scripts/vfx/ground_fx.gd`, `GroundFx`)
- New library of effects that live in the environment: **decals projected onto the terrain**
  (they follow slopes): shockwave rings, glowing fissures that cool to dark, burn marks,
  spinning rune circles; **lightning from the sky** (camera-facing jagged ribbons with a
  white core, glow and forks, flickering, light flash, burn mark, spark ring); **flame
  patches** that keep burning; **3D rock debris**; dust rings; flipbook explosions with
  smoke; light flashes; elemental **status effects on enemies** (burning, shocked, stunned,
  arcane); **camera shake** (`IsoCameraRig.add_shake`). Textures baked by
  `tools/make_ground_vfx.py` into `assets/vfx/ground/` (glowing shapes get a premultiplied
  `_emission` map: a Decal's emission ignores alpha). The white Brackeys fire / explosion
  sheets get a colour ramp (`GroundFx.fire_ramp`).
- +5 ultimates reworked on top of their existing hit rules (`WeaponUltimates`):
  - Sword Flame Slash: the ground it crosses burns (a flame patch and a scorch mark every
    0.9 m), hit enemies burn, it ends in an explosion; travelling light; shake.
  - Axe Earthquake: fissure decal opening to the 7 m radius, three shockwave rings, rocks
    thrown up at the centre and along the front, dust, stun shown on staggered enemies.
  - Bow Thunder Arrow: lightning from the sky on the first target and every chained one,
    flickering arcs between them, shocked status.
  - Staff Arcane Storm: rune circle drawn on the terrain under the target, six timed violet
    lightning strikes from the sky with real area damage, arcane status.
- Normal attacks (`AttackEffects`): critical hits (gold "CRITICAL n" text, flash, sparks,
  shake), a rune circle at the feet for every spell cast, axe +3..+5 chops crack the ground,
  sword +4/+5 hits scorch it, defeated enemies burst (dust, sparks, light). Passive +1..+5
  weapon effects are unchanged.

### HP regeneration, MP and rage (`scripts/combat/courier_vitals.gd`, `CourierVitals`)
- New GameplayServices node (persists across regions with the player). HP regenerates
  1.5/s after 6 s without damage, at 25% while in combat (a hit dealt/taken in the last 5 s,
  or an enemy chasing the courier), never above max, never while knocked out; all
  configurable exports. The HUD follows through the normal health signal.
- MP 100, regenerates 2.5/s; a staff's bolts cost 4 MP (`EquipmentStats.STAFF_BOLT_MANA`,
  refused with `no_mana`); bare-handed bolts are free; the Arcane Storm costs 30 MP.
- Rage 100: +8 per hit of a primary attack (`CombatController.basic_hit`; skills don't
  build it), +0.5 per damage taken, decays after 8 s out of combat. **Every ultimate costs
  50 rage** (`CourierVitals.ULTIMATE_RAGE_COST`). The weapon bar says what the ultimate waits
  for ("6 s", "32/50 rage", "needs 30 MP").
- **Development mode: unlimited rage** (user request): in a debug build with a window the
  rage bar stays full and ultimates never spend it; headless tests keep the rule.
- Crits: `CombatController.crit_chance` (0 by default so damage stays deterministic; buffs
  raise it), x1.75, `critical_hit` signal. `damage_multiplier` and `defense_bonus` come from
  buffs.
- HUD (`combat_hud.gd`): real MP and rage bars under the shield bar ("Rage n · C READY"
  pulses when the ultimate can be released), and a row of active buff icons with seconds.

### Food, potions and the inventory
- `ConsumableItem` (`scripts/inventory/consumable_item.gd`) extends `MaterialItem` (new kinds
  FOOD, HEALTH_POTION, MANA_POTION, BUFF; per-item `max_stack`): heal at once, heal over
  time, mana, rage, and a timed buff (damage x, defense +, crit +, rage gain x, HP / MP regen
  +). 12 in `data/consumables/`: Health Potion, Mana Potion, Red Apple, Bread Loaf, Fresh
  Milk, Sweet Grapes, Cheese Wheel (Well Fed), Roast Ham (Hearty), Hunter's Steak (Blood Up,
  the rage food), Warrior's Ale (Battle Fury), Berserker Draught (Berserk), Ironbark Stew.
  Potions share a 1.5 s cooldown and are refused when they would do nothing.
- `CourierInventory`: stack limits, at most 16 kinds of provisions carried
  (`CONSUMABLE_BAG_SLOTS`), five consumable quick slots on **6 7 8 9 0** (saved, auto-filled;
  `QuickConsumableBar` at the bottom left of the weapon bar with icon, count, key and potion
  cooldown).
- Inventory window: third view **Provisions** (Q cycles Weapons & Gear -> Tools & Goods ->
  Provisions) with Health Potions / Mana Potions / Food / Combat Buffs sections, counts, the
  pack's capacity, effects and description, Use, and slot buttons 6-0. "Gear" is now
  "Armor".
- **Food Market** (`scenes/locations/food_market.tscn`, `tools/generate_food_market.gd`): a
  striped stall on the market square (16.2, -2.8; it replaces the plain goods stall) dressed
  with Food & Market models, Grocer Tilda (`grocer_tilda.tscn`), catalog
  `data/shops/food_market.tres`. The shop lists each provision with its effects and stack
  room ("You carry 3 / 10"); full stacks and a full pack refuse with a reason. The
  Toolwright does not buy provisions.
- Icons cropped from the user's UI sheet (`assets/potion/01_image-01.png`: red/blue potion,
  bread, apple, milk, steak) by `tools/crop_consumable_icons.py`; the others rendered from the
  vendored Avramania Food & Market models (CC0, `assets/models/food_market/`) by
  `tools/render_food_icons.gd`.
- Saved: `SaveGame` "vitals" (health, MP, rage, buffs, heals in progress) and the
  consumable slots.

### Rendered evidence (`tests/capture_phase8_vitals.gd` -> `docs/validation/phase8/70..89`)
HUD with MP/rage/buffs (70), Food Market stall and shop (71, 72), Provisions view (73),
hurt by a real slime and regenerated (74, 75), critical hit (76), Flame Slash burning
ground / explosion / trail (77-79), Earthquake rings / rocks / fissures (80-82), Thunder
Arrow strikes and chain (83-85), Arcane Storm circle and strikes (86-88), staff cast circle
with rage READY (89).

### Known limits
- No human playtest. Balance numbers (regen, costs, prices, buff strengths) are first passes.
- Burn marks are mostly covered by the still-burning flames in the 1.2 s frame.
- Decals also tint characters standing inside them (they project onto render layer 1).

## Recovery milestone 2 (2026-10-20): the seamless open world, Village -> Whisperwood -> Wyrmfall
Brief "true seamless open world" (overrides the region-gate design of section 8). Wyrmfall
Vale is no longer a region behind a gate: the courier walks out of Willowmere, up the
Whisperwood trail and through a pass in the vale's hills to the waterfall, with no gate,
portal, prompt, loading screen or scene change.

### Architecture
- **Coordinates:** one world. Willowmere and the Whisperwood annex stay where they were
  (village.tscn, origin at the plaza). Wyrmfall Vale's origin is
  `WyrmfallLayout.WORLD_ORIGIN` = (54, 0, -184): it covers x -6..114, z -244..-124, north of
  the Whisperwood, and its `PASS` meets the wood's north edge at world (14, -124).
  `ExplorationService.WORLD_RECT` = Rect2(-64, -256, 192, 320) for the map and fog.
- **Streaming** (`scripts/world/world_streamer.gd`, node `OpenWorld` in village.tscn):
  `WorldChunk` resources (scene, world rect, always_loaded, biome) grouped in `WorldChunkSet`s
  that the generators write. Chunks within 70 m of the courier (plus 2 s of its velocity,
  plus `extra_distance` for future flight; `focus_override` follows another node) load on a
  background thread and are added one per frame; beyond 110 m they are parked (out of the
  tree, kept), so felled trees, mined ore and hurt enemies stay as they were; a chunk the
  courier stands on loads at once; `prepare_at()` before a teleport. Chunk roots carry their
  own world transform.
- **Chunks:** `tools/generate_wyrmfall.gd` builds the vale whole and cuts it into four 60 m
  tiles (`wyrmfall_<x>_<z>`: terrain tile mesh + HeightMapShape3D, skirted at the outer edge,
  and everything standing on the tile; undergrowth ScatterFields split per instance), the
  `wyrmfall_core` chunk (water, waterfall, walls, bridge: whole, so the river never breaks)
  and `wyrmfall_places` (WorldLocations, always loaded for the map). `tools/generate_outlands.gd`
  builds `outlands` (always loaded, no collision): low wooded hills round the playable areas,
  sunk under them, so no bare sky shows at the world's edges or between biomes.
- **Removed:** the Wyrmfall region scene, the village gate and the gate back, the router's
  `wyrmfall` region / map / recovery. The Runewood Highlands and the Sentinel Vault (Phase 6)
  are still router regions behind their gateway; interiors are unchanged.

### The seam
- The vale's southern hills are cut by `PASS` (6 m half width) and its ground comes down to
  height 0 at the forest edge; walls line the pass; the village's `AnnexNorth` wall has a 9 m
  gap there; the village terrain mesh ends at z -124 (no hills under the vale).
- The Whisperwood trail continues north from the Moonstone Clearing (`PASS_TRAIL` in
  `tools/generate_whisperwood.gd`, splat lane `phase8-pass`); Tree29 and a mushroom cluster
  of `forest_entrance.tscn` were moved off it. The vale's grass darkens into the forest floor
  over its southern 20 m (noisy blend), pines and broadleaf trees continue on both sides.
- A footpath (`FALLS_PATH`) leads from the vale road to a viewpoint below the waterfall.

### Map
- One world map (`tools/bake_world_map.gd`: the village splats plus the vale's own image at
  its world position, plain land elsewhere), fog over the whole world rect (older fog grids
  are remapped, `LEGACY_RECTS`). M opens it centred on the courier's real position; zoom with
  the zoom keys / wheel, pan with WASD. Region maps (Runewood, vault) keep the rect they were
  baked for (`WorldRouter.REGION_MAP_RECT`). Punctuation keys show their symbol on drawn
  keycaps ("=" not "Equal").

### Validation
- `tests/phase8_open_world_tests.gd` (56): streamer and chunks, no gate or region, a
  continuous ground profile across the seam (no hole, no step), **the mandatory walk**:
  held movement keys (8 keyboard directions, running) from the plaza through the forest
  and the pass to the falls and back. No teleport (largest step 0.14 m in a frame), no
  region change, the same player and HUD, chunks loaded about 80 m ahead, never below the
  ground. Also: buff/MP/gold carry over, tool sites stream in, the real E key fells a vale
  tree, river water for the rod, parked chunks keep a hurt slime and a felled tree, the map.
  Plus the vale's content checks ported from the removed gated-region suite: terrain tiles
  match the layout, water/waterfall shaders, baked textures, the bridge carries held keys,
  bank / pool rim / cliff / boundary / pass walls hold.
- `weapon_elemental_vfx_tests` now checks the region change with the Runewood and the
  Earthquake in the streamed vale.
- Rendered walk (`tests/capture_phase8_open_world.gd` -> `docs/validation/phase8/90..99`):
  plaza, Whisperwood trail, Moonstone Clearing, approaching the pass, in the pass, the vale
  road, towards the bridge, at the waterfall (+ zoomed out), world map at the falls and
  zoomed out. Performance on a GTX 1060 at 1600x900 (`open_world_performance.txt`): 26.7 s
  walk, average 17.1 ms (59 fps, vsync), 99th percentile 28 ms, worst chunk activation 50 ms.

### Known limits
- One frame of about 140 ms on the walk is not a chunk activation (those are at most 50 ms);
  most likely first-use shader compilation of the vale's materials. A shader warm-up (or
  instancing chunks off the main thread) is the next streaming improvement.
- The chunk activation itself (add_child of a tile) costs up to ~50 ms on the GPU machine and
  ~120 ms headless: smaller tiles would spread it.
- Frostpeak, Ashen Volcano and Sunscorch Desert are not built yet; the outlands fill those
  directions for now. The Runewood Highlands are still a gated region.
- No human playtest.

