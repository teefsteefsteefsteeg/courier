# Phase 5H: village improvements and functional RPG tools

Branch `phase5f-integrated`, worktree `D:\courier-phase5f-integrated`. Built on the Phase 5G
exploration map and teleport portals, which this phase does not change. Rendered validation
images: `docs/validation/phase5h/` (regenerate with
`godot --path . --resolution 1600x900 --script res://tests/capture_phase5h_screenshots.gd -- <dir>`).

## 1. Armory crate (Task 1)
- The obstruction was the Armory's **weapon barrel** (a barrel of swords, `Armory/Displays/WeaponBarrel`).
  It stood at location (1.85, 4.25), 0.6 m from the `ShopFront` marker, right in front of
  Weaponsmith Brenna's counter.
- `tools/generate_armory.gd` now places it at `BARREL_SPOT` (-2.95, 0, 1.0): the hall's west front
  corner beside the sword rack. It is still solid decoration.
  - An east-side spot was tried first. It sat on the plaza-to-forest diagonal, about 0.3 m from the
    cobbled road, and the Phase 5A/5F route tests got stuck on it.
- Brenna's reach was the second half of the problem. Her interaction sphere (0.6 m) plus the
  courier's detector (1.4 m) only reached about 0.3 m past her counter, so walking up stopped
  out of range unless the courier pressed against the counter.
  - Fix: `Armory.serve_reach` (1 m) moves her interaction point to the counter front at runtime.
  - The trigger, prompt and shop are unchanged.
- Only the barrel's transform line changed in `scenes/locations/armory.tscn`. The generator re-rolls
  every `unique_id`, so its other output was not kept.

## 2. Village spacing (Task 2)
Measured collider gaps before and after (`tests/phase5h_village_tests.gd` checks them):

| Pair | Before | After |
|---|---|---|
| Blue house / bell tower | 1.1 m | 6.9 m |
| Armory hall / bell tower | 1.2 m | 3.2 m |
| Blue house / post office | 3.9 m | 6.4 m |
| Blue house / Armory | 4.3 m | > 7 m |
| Rose / Oak cottages | 5.5 m | 8.1 m |

| Building | From | To |
|---|---|---|
| Bell tower (`VillageDressing/Landmarks/BellTower`) | (0, -12) | (-1.4, -10.4) |
| `Buildings/CottageBlue` | (-4, -17) | (-8.6, -20.2) |
| `Buildings/CottageOak` | (-17, 10) | (-19.6, 10.6) |
| `Buildings/CottageFern` | (18, 13) | (19.8, 14.2) |

- Each house moved with its woodpile, barrel, flower beds (ScatterField offsets) and, for Fern, its
  MegaKit vines. Oak and Fern breaking the straight south row (z = 10 to 13) also makes it less
  grid-like.
- 28 meadow tufts that ended up inside the new footprints were removed.
- Props moved off the new spots: `Crate3` (with Oak), `Bush04`, `Bush08`, `Bush09`, `Tree01`.
- **Narrowest gap left:** blacksmith to post office, 2.9 m. It is a walkable alley. Moving the
  blacksmith west would put it on the west farm track.
- **Ground paint.** The Phase 5E splat generator was never committed, so
  `tools/edit_village_splat.py` applies explicit edits that match the committed maps (lane profile
  and contact shade measured from them):
  - moves each house's contact shade;
  - reroutes `blue_lane` (bending east of the post-office cart) and fades its old dead end;
  - extends `fern_lane` and adds `oak_spur`.
  - The polylines are in `village_layout.json`, so the Phase 5E suite walks them end to end and
    checks that no collider stands on them.
- **Unaffected:** NPCs, quest markers, delivery spots, zones, map locations and portals. None stood
  at the moved buildings, and the new tests check that every marker, NPC, portal and map place is
  clear of every building.
- The world map was re-baked (`tools/bake_world_map.gd`). The new tests check the baked map shows
  the moved houses at their new places.

## 3. Movement speed (Task 3)
| | Phase 5F | Phase 5H |
|---|---|---|
| Walk | 4.5 m/s | **5.0 m/s** (+11%) |
| Run (Shift) | 7.5 m/s | **8.4 m/s** (+12%) |
| Dash | 16 m/s for 0.2 s | unchanged |
| Stamina | 25 per dash, 60/s regen after 0.7 s | unchanged |
| Acceleration / deceleration | 35 / 45 m/s² | unchanged |

- Both speeds are exports on `MovementComponent`.
- **Clip playback.** Walk and run clips play at `speed / walk_animation_speed` (or
  `run_animation_speed`, 4.5 and 7.5 m/s), the speeds they were tuned for. That gives 1.11x and
  1.12x, so the courier steps faster instead of sliding further per step.
- Before this, one-shots (attack, interact) handed back to the loop at 1x. `KayKitCharacter` now
  remembers the loop speed.
- **Foot planting, measured.** The KayKit chibi rig plants its feet at only about 0.5 m/s (walk) and
  1.3 to 2.2 m/s (run) at 1x, measured from the foot bones. So the existing 4.5 / 7.5 m/s already
  slid. Matching the stride physically would need 4x to 8x playback, which looks frantic. Phase 5H
  keeps the established look and does not add sliding.

## 4. KayKit RPG Tools Bits: inventory
- **Location and licence:** `assets/KayKit_RPGToolsBits_1.0_FREE/` (the user's copy, from the zip in
  Downloads), CC0.
- **Formats:** each of the **49 models** comes as glTF (+ `.bin`), FBX, FBX (Unity) and OBJ.
- **Textures:** one shared 1024 px atlas, `tools_bits_texture.png`. Maps and blueprints add
  `tools_bits_map.png`, `tools_bits_map_empty.png` and `tools_bits_blueprint.png`.
- **No rig, no animations.** Models are upright with the grip at the origin, the same convention as
  the KayKit weapons, so they sit in the Adventurers' `handslot.r` bone unchanged.
- The glTF set is copied to `assets/models/kaykit_rpg_tools/`. The raw pack gets a `.gdignore` so
  its FBX/OBJ duplicates are not imported.

| Group | Models (49) | Use in Phase 5H |
|---|---|---|
| Gathering / repair tools | axe, pickaxe, shovel, hammer, trowel | **Functional tools** (below) |
| | mallet | Tool rack (a second repair hammer would duplicate the hammer) |
| Carpentry / workshop | saw, chisel, file, handplane, handdrill, wrench_A, wrench_B, screwdriver_A_long, screwdriver_A_long_color, screwdriver_A_short, screwdriver_A_short_color, screwdriver_B_long, screwdriver_B_long_color, screwdriver_B_short, screwdriver_B_short_color, knife, scissors, tongs | saw, chisel, wrench_A on the Toolwright's counter; tongs on the anvil; the rest copied, not placed |
| Drawing / study | pencil_A_long, pencil_A_short, pencil_B_long, pencil_B_short, drafting_compass, magnifying_glass, journal_open, journal_closed | pencil_A_long and journal_open on the counter |
| Navigation / paper | map, map_empty, map_rolled, compass_base, blueprint, blueprint_stacked | blueprint_stacked by the stall |
| Hardware | nail, screw_A, screw_B | nail and screw_A on the counter |
| Workshop props | anvil, grindstone, bucket_metal, rope_bundle_A, rope_bundle_B, lantern, torch, torch_burnt | anvil, grindstone, lantern, torch at the stall; bucket and rope at the stall and the pond jetty |

There is **no fishing rod** in the pack. Phase 5H built one from primitive meshes with a `Tip`
marker for the line (`scenes/props/tools/fishing_rod.tscn`). The Fishing Rod item equips it, held
raised by `held_transform`.

The concurrent continuation session is building a replacement under `assets/generated/`, first a
procedural rod, then a Blender GLB. It is not part of the Phase 5H commit. When this commit was
made, its working-tree item pointed at a `.tscn` that Godot could not parse (a UTF-8 byte-order
mark before `[gd_scene`).

## 5. Functional tools
| Tool (price) | Model | Works | Clip (FREE pack fallback) | Result |
|---|---|---|---|---|
| Fishing Rod (40 g) | authored rod (not in the pack) | open water of Willowmere Pond: any bank ([Space]) or the jetty ([E]) | Throw (cast), Use_Item (reel) | a fish: Pond Perch 62, Silver Trout 30, Golden Carp 8 (weights); a quick hook doubles the carp weight, the jetty triples it |
| Woodcutter's Axe (45 g) | axe | 3 marked trees (white blaze) in the Woodcutters' Grove | Throw (chop) x4 | 2-4 Wood; stump for 4 min |
| Miner's Pickaxe (60 g) | pickaxe | 3 ore rocks at the Old Quarry | Throw (swing) x4 | 2-3 Stone, 50% +1 Iron Ore; rubble for 5 min |
| Shovel (30 g) | shovel | 2 soft-soil mounds on the pond banks | PickUp (dig) x3 | 1-2 Clay; hole for 3 min |
| Carpenter's Hammer (35 g) | hammer | Pond Jetty (4 Wood), Pumpkin Patch Fence (3 Wood) | Interact (hammer) x5 / x4 | jetty: +30 g, +5 rep, opens the jetty and its fishing spot; fence: +25 g, +4 rep |
| Mason's Trowel (30 g) | trowel | Quarry Wall (3 Stone, 1 Clay) | Interact x4 | +35 g, +6 rep |

- **Where to get them.** Toolwright Hobb sells all six at the Hill Smithy Tools stall, across the
  west lane from the blacksmith. He buys every material back (fish 4/9/35 g, wood 2, stone 2,
  iron ore 12, clay 3).
- **Fishing flow:**
  1. Cast. The bobber lands at the throw's release.
  2. Wait 2 to 5 s for a bite.
  3. Press [E] or [Space] within 1.1 s of the bite. Pulling early or missing the window loses
     the fish.
  4. A hook in the first half of the window counts as a "Quick hook".
  - Casting is refused on dry land: `Pond.is_open_water()` must hold for the cast point.
- **Results land on the animation event.** Each result is applied at the impact moment of the last
  stroke's clip. The moments were measured from the right hand's trajectory: Throw 58%,
  Interact 36%, PickUp 43%, Use_Item 41% (`KayKitCharacter.TOOL_IMPACT`).

## 6. Architecture
- **Data.**
  - `ItemDefinition.tool_type` (ToolType: FISHING_ROD, HAMMER, WOOD_AXE, PICKAXE, SHOVEL, TROWEL)
    marks a tool. Tools go in MAIN_HAND like weapons and can be quick-slotted.
  - `ItemDefinition.held_transform` sets the hand pose (the rod is held raised).
  - `MaterialItem` (`scripts/inventory/material_item.gd`, data in `data/materials/`) is a stackable
    resource. `CourierInventory` keeps counts (cap 999), with `add_material`, `remove_materials`
    (all or nothing), `has_materials` and the `materials_changed` signal.
- **Combat.** A tool in hand sets `CombatController.AttackStyle.TOOL`. The primary action then
  emits `tool_use_requested` instead of attacking, so a tool never damages anything and a weapon
  never works a tool target. `EquipmentStats` applies it and shows the held model.
- **ToolUser** (`scripts/tools/tool_user.gd`, child of the Player). It runs jobs and fishing as a
  physics-step state machine.
  - **Starting:** [E] on a target, or [Space] (the focused target, else the nearest one for the tool
    in hand, else open water for the rod).
  - **Validation:** right tool in hand, in reach (the prompt's interaction range), alive, on the
    ground, not dashing, no package carried, courier in control, target available, materials held.
  - **While working:** input is paused. Moving, dashing, Escape or damage cancel. A cancelled job
    pays nothing.
- **World components** (`scripts/tools/`), all with an Interactable child and a stable `target_id`:
  - `ToolTarget`: base class. Owns the prompt ("Chop Marked Tree", "needs a Woodcutting axe",
    "Tree Stump · back in 3:12") and per-stroke feedback (shake, chips).
  - `HarvestNode`: yield, bonus, depletion and respawn, standing and depleted visuals with their
    colliders.
  - `RepairSite`: materials, a one-time reward, damaged and repaired visuals, `unlocks` and
    `blockers`.
  - `FishingSpot`: a cast point, a catch bonus and an optional required repair.
  - `Pond` (`scripts/world/pond.gd`): the procedural water, shore and walls (with the jetty gap),
    open-water test and fish table.
- **GatheringService** (GameplayServices). Keeps depleted nodes until a real-time respawn,
  repaired structures (`mark_repaired` succeeds once per id, so a repair is never paid twice) and
  tallies.
- **Shops.** `ToolStall` (group `shop_locations`) is attached a Merchant at runtime by ShopUI, like
  the Armory. `ShopCatalog.buys_materials` adds a "Sell your goods" section to the shop window.
- **UI.**
  - `ToolActionHUD` (bottom centre): job title and stroke bar, fishing status with the
    bite-window bar, "[Space] Cast your line" when the rod faces open water. It hides the
    interaction prompt while working and routes ToolUser feedback to the quest toasts.
  - The Equipment window has Weapons / Tools / Off-hand / Materials sections.
  - The quick bar shows a tool as "Tool: no attacks · [Space] use".
- **Save** (additive, `VERSION` stays 1). `inventory.materials` and `gathering` (depleted,
  repaired, counts) join the save. Owned tools, the tool in hand and quick slots ride on the
  existing inventory data. Saves without these keys load with no materials and nothing
  repaired.
- **World.**
  - `tools/generate_tool_sites.gd` generates the prefabs (`scenes/world/tools/`) and two locations:
    `willowmere_pond.tscn` and `tool_stall.tscn`.
  - `village.tscn` places them under `ToolSites`, with three LocationZones (pond, quarry, stall)
    and map locations for the pond, Old Quarry, Woodcutters' Grove and the stall.
  - A footpath (`pond_path`) leads from the west farm track to the jetty.
  - Everything sits on the north-west outskirts plus one stall, not among the houses.
  - The stall stands south of the west lane at (-26.2, 9.2), where the smithy's spur continues
    across the lane (`stall_spur`). It was first placed east of there, but that spot sat behind
    the Oak cottage from the camera's angle. The grove was moved off the blue house's camera
    diagonal for the same reason.

## 7. Tools without gameplay, and why
- **Mallet:** would duplicate the hammer; shown on the tool rack.
- **Saw, chisel, file, handplane, handdrill, wrenches, screwdrivers, knife, scissors, pencils,
  drafting compass:** carpentry and crafting tools with no crafting system to use them. Some sit on
  the Toolwright's counter.
- **Anvil, grindstone, tongs:** a smithing station without smithing. Iron ore is sold for now.
- **Lantern, torch:** light sources, but the game has no night and no dark areas.
- **Magnifying glass, compass, maps:** inspection and navigation are already covered by the
  Phase 5G map and minimap.
- **Journal, blueprints, nails, screws, rope, bucket:** props only.

## 8. Tests and validation
- `tests/phase5h_village_tests.gd`: Armory access, spacing, walk-arounds, footprints, spots,
  map, speeds and clip rates.
- `tests/tool_system_tests.gd`: data, inventory, combat, targets, validation, every tool,
  impact timing, respawn, cancel, rewards, shop, UI, save/load and old saves.
- Updated: `phase5e_village_tests` (lane-facing targets), `phase5f_building_tests` (moved
  positions), `world_ui_tests` (10 zones).
- `tests/capture_phase5h_screenshots.gd` is a rendered walkthrough with real keys. It prints an
  "H5" line per step; see the screenshots in `docs/validation/phase5h/`.

### Concurrent continuation session
While Phase 5H was being finished, a second Claude session ran a "Phase 6 continuation" in this
worktree (`docs/PHASE6_CONTINUATION.md`). It hardened the uncommitted tool code:
- a full stack refuses the job;
- jobs stop when the courier leaves the site or changes tool;
- casts reset per attempt;
- `ShopService.sell_material` validates sales;
- the narrow-canvas prompt offset fixes the input-prompt check that already failed at 1024x600.

Its edits inside the Phase 5H files are included in the Phase 5H commit. Left uncommitted for
review (that session could not write git metadata):
- its own tests (`phase6_tools_tests.gd`), captures and docs;
- its generated rod and Blender assets;
- the `RunewoodRegion` underground dungeon it added to `village.tscn`, and its map-bake change.

The commit's `village.tscn` and `world_ui_tests.gd` were staged without those additions; the
working tree keeps them.

Its leave-the-site check exposed a data bug: several targets' `reach` was shorter than their
prompt's range (the jetty spot: 1.6 m against 2.2 m). Casting from the edge of the prompt was
cancelled the next frame. `tools/generate_tool_sites.gd` now derives every reach from the
interaction radius, and `tool_system_tests` checks it for every placed target.

## 9. Known issues and limits
- Not playtested by a human. Fishing timing (2-5 s wait, 1.1 s bite window), respawn times and
  prices are first guesses.
- No tool clips in the FREE animation pack: chop, mine and cast reuse Throw, hammer and trowel
  reuse Interact, digging reuses PickUp, reeling reuses Use_Item.
- There are five quick slots and six tools (plus weapons), so some tools are equipped through
  Equipment (Tab).
- Item icons are placeholders, and the fishing rod is an authored primitive model, not a KayKit one.
- With the camera's fixed angle, a tree you chop from its north-west side can hide the courier
  (harvest trees deliberately have no camera occluder, so they never fade while being chopped).
- Iron ore, fish and clay have no use beyond selling (and clay in the wall repair).
