# Phase 5D: Medieval Village / Stylized Nature MegaKit pilot

Branch `phase5d-megakit-pilot`, worktree `D:\courier-phase5d-megakit-pilot`, based on
`phase5c-characters` @ `d606ce2`. A deliberately small integration test of the MegaKit packs
(see the audit report) before deciding on anything broader.

Before/after from identical cameras (HUD and labels hidden; left = Phase 5C, right = 5D):
`docs/validation/phase5d/*.png`. Regenerate with
`godot --path . --script res://tests/capture_phase5d_screenshots.gd -- <dir>`.

## What was added

One new node in `scenes/levels/village.tscn`: `MegaKitPilotDressing`
(`scenes/environment/megakit_pilot_dressing.tscn`), plus wrapper scenes in `scenes/props/megakit/`.
No existing building, tree, prop, character, script or test was changed.

| Location | Additions |
|---|---|
| Post office | 6 vines (inner north and west walls, both south pillars, over the east arch); planted bed along the south wall (stone edging, two flower groups, flowering bush, clover) and a smaller bed east of the south door; pebbles along the post-office road |
| CottageRose (-8, 13) and CottageFern (18, 13) | Vines on both front corners and one side wall; stone edging in front of the Phase 5B flower beds; a flowering bush and tall flowers placed clear of the existing woodpiles and barrels |
| Farm edge (wheat field / mill) | MegaKit wagon (with collider), three wooden fence segments along the field's west edge, a boulder, flowering bush and flower clumps |
| Forest path | Seven stepping stones down the path, pebble edging on both sides, ~18 ground plants, 12 mushrooms, two boulders (with colliders) east of the path |

Collision only where it matters: wagon (box), fences (thin boxes), boulders (cylinders).
Vines, flowers, edging, pebbles, stepping stones and plants have none. Small repeated pieces
(stones, pebbles, plants, mushrooms) are MultiMeshes. No lights added.

## Validation

Automated (headless): import clean; all 15 suites pass (Phase 1 to 5D), including the new
`tests/phase5d_megakit_tests.gd` (64 checks): CC0 licences present, exactly 25 models and every one
used, textures capped at 1024 px, all four locations dressed, pilot colliders off every road and
the square and >1.2 m from all NPCs/markers/enemy spawns, post-office south doorway clear, no
collision on decorative pieces, pilot budget (51 geometry nodes, ~41k triangles, 0 lights), and
Phase 5B/5C nodes and the Ranger courier untouched. The Phase 5A navigation walks still reach every
NPC, delivery spot, the quest board and the forest clearing.

Rendered (GPU window, scripted, not a human playtest): main scene ran 600 frames without errors.

Frame time at 1600x900, vsync off, same camera spots, average of two runs each:

| View | Phase 5C | Phase 5D | Delta | Draw calls |
|---|---|---|---|---|
| Town square | 6.92 ms | 7.16 ms | +0.24 | 1073 -> 1129 |
| Post office | 7.09 ms | 7.47 ms | +0.38 | 741 -> 775 |
| Forest clearing | 7.48 ms | 7.64 ms | +0.16 | 635 -> 649 |
| Zoomed-out overview | 7.61 ms | 8.02 ms | +0.41 | 1528 -> 1595 |
| Farm edge | 5.54 ms | 6.11 ms | +0.57 | 840 -> 877 |
| Forest path | 6.65 ms | 6.97 ms | +0.32 | 607 -> 622 |
| CottageRose | 5.82 ms | 5.70 ms | -0.12 (noise) | 667 -> 700 |

Run-to-run noise is about +/-0.3 ms.

## Known issues and observations

- The textured MegaKit pieces are kept small or at the edges of views on purpose; up close the
  wood/stone texture is visibly different from the flat-colour Quaternius props (expected, see audit).
- West of the forest path there was no free space (Forest Slime spawn clearance and dense
  trunks), so both forest boulders sit on the east side.
- Some farm fence segments are partly hidden behind the mill and trees in the farm view.
- Not yet playtested by a human.
