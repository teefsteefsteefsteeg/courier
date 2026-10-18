# Phase 5F: building visual overhaul

Branch `phase5f-building-visual`, worktree `D:\courier-phase5f-building-visual`, based on
`phase5e-village-overhaul` @ `38be579`. Focus: the village buildings. Layout, roads, collision,
NPCs, quest markers, gameplay and HUD are unchanged.

Before/after from identical cameras at 1600x900 (left = Phase 5E, right = 5F; views 15 and 16
keep the gameplay HUD): `docs/validation/phase5f/*.png`. Regenerate the after set with
`godot --path . --resolution 1600x900 --script res://tests/capture_phase5f_screenshots.gd -- <dir>`.

## What changed

Every village building was a recoloured Quaternius low-poly model, and six of the ten homes shared
two models (House_1 three times, House_2 three times plus the alchemy shop). Each is now its own
building assembled from Medieval Village MegaKit modules: textured plaster, uneven-stone and
timber-grid walls, round and flat doors, arched windows with shutters, tile roofs with gable ends,
dormers, chimneys, balconies on brackets, porches and canopies.

| Node (unchanged name and transform) | Was (Phase 5E) | Now (`scenes/buildings/`) |
|---|---|---|
| `Buildings/CottageRose` | House_1, red | `rose_cottage`: one-storey plaster cottage, round door beside a shuttered window, dormer, chimney (red) |
| `Buildings/CottageOak` | House_2, orange | `oak_house`: two storeys, stone ground floor, timber-grid upper floor, front balcony (orange) |
| `Buildings/CottageFern` | House_1, green | `fern_cottage`: timber-grid cottage, wooden porch canopy on brackets, dormer each side (green) |
| `Buildings/CottageBlue` | House_2, blue | `blue_house`: tall stone and plaster townhouse, arched windows, side balcony (blue) |
| `Buildings/CottageBrook` | House_2, gold | `brook_cottage`: low stone cottage, wide shuttered windows, side chimney (thatch gold) |
| `Buildings/CottageMoss` | House_1, teal | `moss_cottage`: plaster on a stone plinth, arched windows, two dormers (teal) |
| `Buildings/CottageWillow` | Inn | `inn`: wide two-storey hall, stone below, timber above, full-width balcony, two dormers, two chimneys |
| `Buildings/CottageHill` | Blacksmith | `blacksmith`: side-on stone forge hall, open timber canopy over a hearth with glowing coals and an anvil, big chimney |
| `Buildings/CottageMill` | Mill | `mill`: three-storey stone tower mill with a timber cap and four lattice sails that turn (`Spinner`) |
| `Buildings/AlchemyShop` | House_2, purple | `alchemy_shop`: three-storey tower with a spire roof and a gabled shopfront, violet glowing windows (purple) |
| `VillageDressing/Landmarks/BellTower` | Bell_Tower | `bell_tower`: two-storey stone shaft, open timber belfry with the bell, spire roof |

The post office (a walk-in location with its own interior and gameplay markers) and the market
stalls are not buildings in this sense and are unchanged.

### How the buildings are built
- `tools/generate_buildings.gd` (headless) writes the eleven scenes from short recipes: wall
  layouts per storey and face (`"DW"` = round door, arched window...), roofs, dormers, balconies,
  porches and extras. Kit units are 2 m modules and 3 m storeys; `Model` is scaled to 0.8 (0.93
  for the forge, 0.78 for the bell tower) so each building fits the footprint it replaces.
- Each scene keeps the **exact collider** (`BoxShape3D` size and centre) of the scene it replaces,
  and gets a `CameraOccluder` sized from the collider and the model height.
- `MedievalBuilding.merge_model` combines the pieces at runtime into **one mesh per material**
  (7 to 10 surfaces per building instead of roughly 150 piece/surface draws), cached per scene.
  `CameraOccluder.collect_geometry()` is re-run afterwards so the merged mesh still fades.
- Kit materials are mapped at import to shared materials in `assets/materials/buildings/`, so all
  buildings batch on the same nine materials. Roofs, plaster and window glow keep their
  per-building colours through the existing `roof_color` / `wall_color` / `window_glow` exports;
  the roof texture is desaturated so any hue works.
- Houses that Phase 5E turned 180 degrees show their back and left walls to the camera, so every
  face has windows.
- Phase 5D vines on Rose and Fern moved onto the new, slightly smaller walls.

## Unchanged
Building positions and rotations, colliders, roads and terrain, NPCs and their routes, quest and
delivery markers, combat, minimap, camera, HUD, characters, gameplay scripts.

## Validation

Automated (headless): import clean; **all 18 suites pass** (Phase 1 to 5F, village quest,
world UI); village boot (`--quit-after 180`) exits 0 with no errors.
New `tests/phase5f_building_tests.gd` (138 checks):
- Every kit piece is used, maps to a shared material, and textures are capped at 1024 px.
- Each building is assembled from 30 to 65 pieces, and no two buildings share a design.
- All eleven keep their Phase 5E position and facing, and their exact collider size and centre.
- Each sits on the ground within a bounded overhang, and all ten village roofs differ.
- Each merges to one mesh (the mill: two, for the sails) of 7 to 10 surfaces with no primitives
  left. All use the shared materials and cast shadows. Each building stays within 45k triangles,
  and the set totals 253k.
- Each occluder covers the building's height, the alchemy windows glow violet, the mill's sails
  turn, and a merged house fades when the courier stands behind it.

The Phase 5E road/lane walks, the Phase 5A walks to every NPC, delivery spot, the board and the
clearing, and the full Q1 to Q3 quest playthrough all pass unchanged.

Test updates (Phase 5F replaced what they asserted):
- Phase 5A: "uses a Medieval Village model" now checks for the MegaKit building, and "model
  inside the old footprint" now checks only that the model sits on the ground. The collider still
  fits the old footprint, and Phase 5F bounds the overhang.
- Phase 5B: the alchemy shop "real model" check also accepts the merged mesh.

Rendered (GPU window, scripted, not a human playtest): 16 before/after views inspected.

Frame time at 1600x900, vsync off, 300 frames per view (before = Phase 5E files, average of two
runs). Another session was running headless tests on the same machine, so expect about ±0.4 ms
of noise:

| View | Phase 5E | Phase 5F | Draw calls | Primitives |
|---|---|---|---|---|
| Plaza | 6.57 ms | 6.81 ms | 948 -> 960 | 645k -> 930k |
| Residential south | 6.42 ms | 6.75 ms | 1007 -> 1009 | 605k -> 938k |
| Residential west | 7.28 ms | 7.72 ms | 963 -> 972 | 671k -> 966k |
| Zoomed-out overview | 7.65 ms | 8.33 ms | 1464 -> 1477 | 849k -> 1279k |
| Mill / farm | 6.65 ms | 5.97 ms | 968 -> 968 | 668k -> 842k |
| Alchemy lane | 5.95 ms | 5.91 ms | ~715 -> 715 | ~520k -> 762k |

Draw calls are unchanged thanks to merging. The cost is primitives: the MegaKit pieces are far
more detailed than the old models. Ground-floor-only stone quoins already cut the heaviest piece
(3.1k triangles). Village load (instantiate + ready, headless) rose from about 1.17 s to 1.24 s
for the runtime merge.

## Known issues
- The alchemy tower (12.6 m) and bell tower (12.3 m) are taller than the models they replace, so
  the alchemy tower fades out more often when the courier crosses the south side of the plaza
  (visible in `01_overview.png`). That is the camera occluder working as intended.
- The MegaKit pieces are textured, while trees, rocks and props are flat-colour Quaternius models.
  The buildings now read as the most detailed objects in the scene; up close the style difference
  is noticeable, at gameplay zoom it reads as intended.
- Runtime LOD generation for the merged meshes was tried and dropped (`ImporterMesh.generate_lods`
  did not finish in minutes). The buildings draw at full detail; baking merged meshes with LODs
  offline is the next step if primitives become a bottleneck.
- The Phase 5A scenes in `scenes/props/medieval/` and `scenes/props/env/bell_tower.tscn` are no
  longer used by the village; they are kept for comparison and rollback.
- Not yet playtested by a human.
