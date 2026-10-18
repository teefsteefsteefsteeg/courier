# Asset Manifest

No external assets are imported yet. Everything below is a **PLACEHOLDER** made from Godot
built-in primitive meshes and flat-colour materials authored in this repo. It should be replaced
with properly licensed low-poly art.

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Courier (player) | `scenes/player/player.tscn` (Visual) | Capsule/sphere/box/cylinder primitives | Authored in-repo, no license needed | PLACEHOLDER |
| NPC body | `scenes/npc/npc.tscn` (Visual) | Primitives, colour set per instance | Authored in-repo | PLACEHOLDER |
| Crate | `scenes/props/placeholder_crate.tscn` | BoxMesh 1 m | Authored in-repo | PLACEHOLDER |
| Rock | `scenes/props/placeholder_rock.tscn` | 6-sided CylinderMesh | Authored in-repo | PLACEHOLDER |
| Tree | `scenes/props/placeholder_tree.tscn` | Cylinder trunk + 2 cones | Authored in-repo | PLACEHOLDER |
| Ground, path, fence | `scenes/levels/test_yard.tscn` | PlaneMesh / BoxMesh | Authored in-repo | PLACEHOLDER |
| Flat materials (32) | `assets/materials/placeholder/ph_*.tres` | StandardMaterial3D (some emissive) | Authored in-repo | PLACEHOLDER |
| Village buildings and props | `scenes/props/{cottage,well,lamp_post,market_stall,signpost,barrel,bench,bush,mushroom_cluster}.tscn` | Box/Prism/Cylinder/Sphere primitives | Authored in-repo | PLACEHOLDER |
| Post office, forest entrance | `scenes/locations/*.tscn` | Primitives and Label3D signs | Authored in-repo | PLACEHOLDER |
| NPC costumes (5) | `scenes/npc/characters/*.tscn` | Primitive accessories on npc.tscn | Authored in-repo | PLACEHOLDER |
| UI theme | `assets/ui/courier_theme.tres` | Theme and StyleBoxFlat | Authored in-repo | Temporary |
| UI font | engine default | Godot default font | Godot (MIT) | Temporary |
| Parcel / Dragon egg / Potion crate visuals | `scenes/gameplay/packages/visuals/*.tscn` | Primitives + inline materials | Authored in-repo (Phase 2) | PLACEHOLDER |
| Package pickup marker | `scenes/gameplay/packages/package_pickup.tscn` | Flat cylinder, unshaded | Authored in-repo (Phase 2) | PLACEHOLDER |
| Quest board | `scenes/gameplay/world/quest_board.tscn` | BoxMesh posts/board/notes | Authored in-repo (Phase 2) | PLACEHOLDER |
| Destination ring | `scenes/gameplay/world/destination_area.tscn` | TorusMesh, unshaded | Authored in-repo (Phase 2) | PLACEHOLDER |
| Gameplay UI theme | `scenes/gameplay/ui/gameplay_ui_theme.tres` | Theme, StyleBoxFlat | Authored in-repo (Phase 2) | Temporary |
| Phase 2 sandbox ground/fence/signs | `scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn` | PlaneMesh / BoxMesh / Label3D | Authored in-repo (Phase 2) | PLACEHOLDER (test scene) |

When adding an external asset, record: name, path, author, source URL, license (with a link), date
imported, and any modifications.
