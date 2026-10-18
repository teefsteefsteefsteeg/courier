# Phase 5A: real 3D asset integration

Branch `phase5a-assets`, worktree `D:\courier-phase5a-assets`, based on `phase4-live` @ `1b75ac4`.
The uncommitted HUD-polish work in `D:\courier-phase4-live` is **not** included.

## What changed

| Location | Before | After |
|---|---|---|
| `scenes/levels/village.tscn` `Buildings/CottageRose, CottageFern, CottageMoss` | `props/cottage.tscn` | `props/medieval/house_1.tscn` |
| `Buildings/CottageOak, CottageBlue, CottageBrook` | `props/cottage.tscn` | `props/medieval/house_2.tscn` |
| `Buildings/CottageWillow` | `props/cottage.tscn` | `props/medieval/inn.tscn` |
| `Buildings/CottageHill` | `props/cottage.tscn` | `props/medieval/blacksmith.tscn` |
| `Buildings/CottageMill` | `props/cottage.tscn` | `props/medieval/mill.tscn` |
| `Buildings/AlchemyShop` | unchanged | tinted `props/cottage.tscn` (quest destination identity, tested roof tint) |
| `Trees/Tree01..75` | `props/placeholder_tree.tscn` | cycled `props/nature/common_tree_1..4`, `pine_tree_1..3` |
| `Props/Rock1..7` | `props/placeholder_rock.tscn` | cycled `props/nature/rock_2`, `rock_3`, `rock_moss_2` |
| `Props/Bush01..18` | `props/bush.tscn` | cycled `props/nature/bush_1`, `bush_2`, `bush_berries_1` |
| `scenes/locations/forest_entrance.tscn` `Trees/Tree01..37` | `props/placeholder_tree.tscn` | pine-weighted cycle of the nature trees |
| `forest_entrance.tscn` `BushWest`, `BushEast` | `props/bush.tscn` | `props/nature/bush_1`, `bush_2` |

Node names, transforms, roads, NPCs, quest board, post office and forest gate are unchanged.
`test_yard.tscn` and the Phase 2 sandbox still use the placeholders.

Wrapper scenes keep the placeholder contract: houses and trees are `StaticBody3D` with a
`CameraOccluder`; colliders are no larger than the placeholder they replace (house boxes fit
the old 6.4 x 5.4 m cottage box, trees keep the 0.4 m trunk cylinder, rocks are <= 0.85 m radius);
bushes stay collision-free. All meshes cast shadows. Models face +Z like the old cottages.

Also fixed: `scripts/phase4_integration_visual/minimap_view.gd` declared `const Projection`,
which clashes with Godot's built-in `Projection` type, so the minimap failed to parse at `1b75ac4`.
Renamed to `MinimapProjection` (the same rename exists, uncommitted, in `phase4-live`).

## Validation

Automated, headless: `godot --headless --path . --script res://tests/<suite>.gd`
- New `tests/phase5a_asset_tests.gd`: model imports, licenses, polygon budget, materials and
  shadows, collider footprints, occluders, and analog-steered walks from the village square to
  every NPC, both delivery spots, the quest board and the forest clearing.
- Every existing suite passes except `phase4_gameplay_tests.gd`, which fails to parse at the base
  commit too (it calls `_test_village_delivery()`, defined only in uncommitted `phase4-live` work).

Rendered, scripted (GPU window, not a human playtest): `tests/capture_world_screenshots.gd`;
selected frames in `docs/validation/phase5a/`.
