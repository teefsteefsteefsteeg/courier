# Phase 5E: village visual overhaul

Branch `phase5e-village-overhaul`, worktree `D:\courier-phase5e-village-overhaul`, based on
`phase5d-megakit-pilot` @ `94af16f` (the latest committed state: 5B environment + 5C characters
+ 5D pilot). Focus: terrain, roads, layout and composition, not more props.

Before/after from identical cameras at 1600x900 (left = Phase 5D, right = 5E; views 12 and 13
keep the gameplay HUD): `docs/validation/phase5e/*.png`. Regenerate the after set with
`godot --path . --resolution 1600x900 --script res://tests/capture_phase5e_screenshots.gd -- <dir>`.

## What changed

### Ground and roads (the main change)
- `scripts/world/village_terrain.gd` (`VillageTerrain`, node `Terrain` in `village.tscn`) builds a
  160 x 160 m ground mesh: exactly flat (y = 0) across the walkable square, rising into gentle
  noise-shaped hills beyond the boundary walls, with a 70-tree line on the hills (5A tree scenes).
  The old map edge (blue void at the corners) is gone. Gameplay collision is unchanged: the flat
  `Ground` box and the `Boundary` walls.
- `assets/shaders/village_ground.gdshader` + `assets/materials/environment/village_ground.tres`
  paint the ground from two splat maps: grass with broad deep/lush/sunny patches and dry meadow
  streaks, dirt lanes with ruts, cobblestone roads and flagstone plazas (procedural Voronoi stones
  with mortar), tilled soil with furrows, forest floor and clearing moss, and contact shade under
  trees and around houses. Edges are noise-warped, so surfaces meet irregularly.
- `assets/textures/terrain/village_splat_a.png`, `village_splat_b.png` (1024², 8 px/m) are
  generated from `assets/textures/terrain/village_layout.json`, the road network and districts
  (also used by the Phase 5E tests).
- Road network: cobbled main roads to the market and mill, to the forest gate, and south to the
  alchemy shop; a flagstone plaza, market square and post-office forecourt; dirt lanes to every
  house (west lane, south-west lane, spurs to Rose, Moss, Brook, Fern, Blue, the blacksmith), farm
  tracks past the mill and the west vegetable plots, and the forest path.
- The flat planes are hidden, not deleted: `Ground/Mesh`, the seven `Paths/*` rectangles, and the
  forest `ForestFloor`, `Path` and `ClearingGround`.

### Layout and composition
- Houses face their lanes: CottageOak, CottageMoss, CottageBrook and CottageFern turned 180°,
  CottageWillow (inn) 90°. Rotation only; positions and footprints unchanged.
- Two village trees that stood on new lanes moved a few metres (Tree03, Tree18).
- Phase 5B village dressing regenerated for the new layout: the rectangular path slabs and the
  tiled plaza disc are removed (the terrain paints them); home flower beds, woodpiles and barrels
  follow each house's new facing; extra trees now form groves on the outskirts instead of an even
  sprinkle; rocks cluster at grove edges; meadow grass and wildflowers grow in clumps and drifts;
  crop rows follow the painted furrows; nothing is placed on roads, lanes, the plaza, the market
  square or fields.
- Phase 5D pilot dressing regenerated: Fern's vines follow its turn; the post-office road pebbles
  now line the start of the west lane; the stone curbs by the two houses were dropped (they read as
  loose slabs); post office, farm and forest-path pieces are unchanged.
- Post office yard: the cart and hay bale moved north of the wall, clear of the new lane to
  CottageBlue.

### Unchanged
Quest logic, NPCs and their positions, delivery spots, the post office, market stalls, alchemy
shop, enemy spawns, combat, minimap, camera, KayKit characters and animations, and all collision
except the regenerated dressing.

## Validation

Automated (headless): import clean; all 16 suites pass (Phase 1 to 5E). New
`tests/phase5e_village_tests.gd` (68 checks): terrain built with the ground shader; flat over the
whole walkable square, hills only outside the walls, hill trees outside; old planes hidden; every
surface type present where the layout says (plaza, market, forecourt, each road and lane, each
field, forest floor, clearing, meadow variation); every turned house faces its lane; 320+
colliders keep road and lane cores clear (documented exceptions: Corvin at his shop's road end,
the forest gate posts); quest positions unchanged; **every road and lane walked end to end** by the
player controller, and each main road reached from the plaza centre. The Phase 5A routes to every
NPC, delivery spot, the quest board and the clearing still pass.

Test updates: three Phase 5B checks that asserted the removed paving tiles, path slabs and the
forest-floor plane now assert the equivalent terrain surfaces.

Rendered (GPU window, scripted, not a human playtest): main scene ran 600 frames without errors.

Frame time at 1600x900, vsync off, average of two runs (before = clean Phase 5D checkout):

| View | Phase 5D | Phase 5E | Delta |
|---|---|---|---|
| Plaza | 7.14 ms | 6.85 ms | -0.29 |
| Post office | 7.44 ms | 7.40 ms | -0.04 |
| Market | 5.97 ms | 6.18 ms | +0.21 |
| Residential south | 5.95 ms | 6.10 ms | +0.15 |
| Farm east | 6.13 ms | 6.40 ms | +0.27 |
| Forest clearing | 7.70 ms | 7.70 ms | 0.00 |
| Zoomed-out overview | 7.85 ms | 8.07 ms | +0.22 |
| West edge (hills) | 5.44 ms | 6.19 ms | +0.75 |

Draw calls are about the same (the paving tiles and path slabs are gone); rendered primitives rise
by roughly 230k (terrain mesh plus hill trees). Run-to-run noise is about +/-0.3 ms.

## Known issues
- The ground shader computes Voronoi stones per pixel on road and plaza areas; cheap on this GPU,
  but the first thing to simplify on low-end hardware.
- The hill tree line spawns at runtime from a seed; it is not visible in the editor until play.
- Corvin stands on the end of the south road at his shop door (as he did on the old path).
- Unused Phase 5B wrapper scenes `scenes/props/env/path_stones.tscn` and `stone_tile.tscn` remain.
- Not yet playtested by a human.
