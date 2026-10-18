# Phase 5B: environment visual overhaul

Branch `phase5b-environment`, worktree `D:\courier-phase5b-environment`, based on
`phase5a-integration` @ `aa5ce0f`. Characters, NPCs and enemies are unchanged.

Before/after comparisons from identical camera positions (HUD hidden; left = before,
right = after): `docs/validation/phase5b/compare/*.png`. Regenerate either side with
`godot --path . --script res://tests/capture_phase5b_screenshots.gd -- <dir>`.

## How it is built

- **Shared props rewritten in place** (same root type, collider and lights, so every instance
  in the village, post office and forest upgrades at once): `scenes/props/well.tscn`, `bench`,
  `barrel`, `placeholder_crate` (MV Crate), `lamp_post` (stone pillar + lit torch),
  `mushroom_cluster`, `market_stall` (MV MarketStand_1 + produce) and new `market_stall_goods`.
- **Dressing scenes** instanced into the existing locations, each in its own subtree so gameplay
  node paths are untouched:
  `scenes/environment/post_office_dressing.tscn` (PostOffice/Dressing),
  `village_dressing.tscn` (VillageDressing), `forest_dressing.tscn` (ForestEntrance/Dressing).
- **Reusable wrappers** for dressing pieces: `scenes/props/env/*.tscn` (normalised scale, ground
  pivot, collider/occluder where needed).
- **Primitive placeholder meshes are hidden, not deleted**, in `post_office.tscn`,
  `forest_entrance.tscn` and the village cauldron. Their colliders, the post-office wall the HUD
  polish test fades, and all markers stay in place.
- **Runtime scripts**: `scripts/world/model_tint.gd` (recolour/glow imported surfaces by material
  name), `medieval_building.gd` (per-instance roof/wall/window colours; replaces `Cottage` for the
  alchemy shop), `scatter_field.gd` (MultiMesh grass, flowers, ferns and crops).
- **Ground**: authored NoiseTexture2D materials in `assets/materials/environment/` (meadow, dirt,
  cobble, forest floor, clearing moss, forest path). Environment: SSAO, slight saturation/contrast,
  volumetric fog enabled at density 0 so only the forest FogVolume adds mist.

## What changed, by area

| Area | Before | After |
|---|---|---|
| Post office | Plaster boxes, primitive counter/shelves/table/sacks | Stone block walls, square timber pillars, stone arches at both doors, tiled floor and rug, real desk with ledger/parcels/bell/candles, two full bookcases as mail shelves, sorting table with parcels, mail sacks, red post banners, four lit wall torches, chest, potted plants, crystal glow by the exhibit, post cart/hay/parcels and flower planters outside |
| Alchemy shop | Purple primitive cottage | Medieval House_2 with purple roof, lavender walls and violet lit windows; potion table with glowing potions, crystal cluster, jars, glowing cauldron model |
| Houses | 5A models, uniform colours | Eight distinct roof colours, tinted walls, warm lit windows, flower beds, woodpiles and barrels |
| Town square | Flat grey disc | Stone paving tiles, real well and benches, torch pillars, flower planters, tall pots and banners on the rim |
| Market | Primitive stalls | Striped MV market stands with produce/goods, produce crates, cart, fence |
| Roads | Flat dirt planes | Dirt material plus stone path slabs |
| Village meadow | Flat green | Textured grass, ~1,600 grass tufts, ~580 wildflowers in four colours, 34 extra trees incl. autumn/birch/willow, rocks and bushes, bell tower and fox statue landmarks, wheat/corn/pumpkin/carrot/lettuce fields with fences |
| Whisperwood | Same light and greens as the village, primitive gate/stones/crystals | Darker mossy floor, overgrown stone arch with blue magic torches, ruined column circle with glowing runes, crystal heart, stag statue landmark, ruins, ~10 extra trees, glowing mushrooms, ~790 ferns/forest plants, fireflies, teal mist, coloured hollow lights |

## Retained placeholders

Signposts, the mailbox, the post-office sign boards, the forest gate sign board, the quest board,
package pickup markers, destination ring, NPC and player models, enemies, and `test_yard` /
Phase 2 sandbox scenes (test-only). `cottage.tscn` and `bush.tscn` remain in the repo but are no
longer placed in the village or forest.

## Validation

Automated (headless): Godot import clean; every scene under `scenes/props`, `scenes/props/env`,
`scenes/environment`, levels and locations loads. All 13 suites pass, including the new
`tests/phase5b_environment_tests.gd` (dressing wired, no visible primitives in upgraded areas,
forest distinctness, new colliders kept off roads and >1.2 m from every NPC/marker/spawn point,
triangle/light budget) and the Phase 5A navigation walks to every NPC, delivery spot, the quest
board and the forest clearing.

Test changes: `world_ui_tests` and `phase5a_asset_tests` now assert the alchemy shop's per-instance
roof colour on `MedievalBuilding` instead of the old `Cottage` primitive; the Phase 5A per-building
triangle budget is 12k (was 10k) for the single Bell_Tower landmark (11.8k).

Rendered, scripted (GPU window, not a human playtest): the comparison screenshots above and a
frame-time probe at 1600x900 on this machine (vsync off, same camera spots):

| View | Before | After |
|---|---|---|
| Town square | 4.6 ms, 572 draws, 75k prims | 6.9 ms, 1053 draws, 419k prims |
| Post office | 4.4 ms, 428 draws, 80k prims | 7.5 ms, 735 draws, 324k prims |
| Forest clearing | 4.3 ms, 387 draws, 162k prims | 7.6 ms, 629 draws, 371k prims |
| Zoomed-out overview | 4.9 ms, 851 draws, 180k prims | 7.6 ms, 1506 draws, 625k prims |

## Known issues / performance notes

- Frame time rises ~60% (still ~130 fps here). Biggest costs: draw calls from many individually
  instanced props (each FBX model has several material surfaces), volumetric fog, SSAO. If lower-end
  hardware struggles: disable SSAO, drop `volumetric_fog_enabled`, or merge the post-office wall and
  floor pieces into MultiMeshes.
- 49 lights in the village scene (torches, crystals, mushrooms); most are small-range unshadowed omnis.
- Crops and grass are placed by an offline generator (deterministic seeds); the generator is not in
  the repo, so later tweaks are made by editing the dressing scenes.
- Quaternius potion glass imports as opaque; it is tinted pale blue rather than transparent.
- Not yet playtested by a human; check walking feel around the denser dressing.
