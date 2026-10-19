# Asset Manifest

Phase 5A imported the first external models (Quaternius, CC0) for village houses and nature props;
see **External assets** below. Everything else is still a **PLACEHOLDER** made from Godot built-in
primitive meshes and flat-colour materials authored in this repo.

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Courier (player) | `scenes/player/player.tscn` (Visual) | Primitive meshes kept hidden; KayKit Ranger shown | Authored in-repo | Replaced in 5C |
| NPC body | `scenes/npc/npc.tscn` (Visual) | Primitives kept hidden; KayKit models per character | Authored in-repo | Replaced in 5C |
| Crate | `scenes/props/placeholder_crate.tscn` | BoxMesh 1 m | Authored in-repo | PLACEHOLDER |
| Rock | `scenes/props/placeholder_rock.tscn` | 6-sided CylinderMesh | Authored in-repo | PLACEHOLDER (test yard / sandbox only; village uses Quaternius rocks) |
| Tree | `scenes/props/placeholder_tree.tscn` | Cylinder trunk + 2 cones | Authored in-repo | PLACEHOLDER (test yard / sandbox only; village and forest use Quaternius trees) |
| Ground, path, fence | `scenes/levels/test_yard.tscn` | PlaneMesh / BoxMesh | Authored in-repo | PLACEHOLDER |
| Flat materials (32) | `assets/materials/placeholder/ph_*.tres` | StandardMaterial3D (some emissive) | Authored in-repo | PLACEHOLDER |
| Village buildings and props | `scenes/props/{cottage,signpost,bush}.tscn` | Box/Prism/Cylinder/Sphere primitives | Authored in-repo | PLACEHOLDER (signposts still primitive; `cottage`/`bush` unused in the village since 5B). Well, lamp, stall, barrel, bench, crate and mushroom props use Quaternius models since 5B |
| Post office, forest entrance | `scenes/locations/*.tscn` | Primitive colliders and Label3D signs; visuals from `scenes/environment/*_dressing.tscn` | Authored in-repo | Primitive meshes hidden since 5B; mailbox, sign boards and forest sign remain primitive |
| NPC costumes (5) | `scenes/npc/characters/*.tscn` | Primitive accessories, hidden since 5C | Authored in-repo | Replaced in 5C |
| UI theme | `assets/ui/courier_theme.tres` | Theme and StyleBoxFlat | Authored in-repo | Temporary |
| UI font | engine default | Godot default font | Godot (MIT) | Temporary |
| Parcel / Dragon egg / Potion crate visuals | `scenes/gameplay/packages/visuals/*.tscn` | Primitives + inline materials | Authored in-repo (Phase 2) | PLACEHOLDER |
| Package pickup marker | `scenes/gameplay/packages/package_pickup.tscn` | Flat cylinder, unshaded | Authored in-repo (Phase 2) | PLACEHOLDER |
| Quest board | `scenes/gameplay/world/quest_board.tscn` | BoxMesh posts/board/notes | Authored in-repo (Phase 2) | PLACEHOLDER |
| Destination ring | `scenes/gameplay/world/destination_area.tscn` | TorusMesh, unshaded | Authored in-repo (Phase 2) | PLACEHOLDER |
| Gameplay UI theme | `scenes/gameplay/ui/gameplay_ui_theme.tres` | Theme, StyleBoxFlat | Authored in-repo (Phase 2) | Temporary |
| Phase 2 sandbox ground/fence/signs | `scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn` | PlaneMesh / BoxMesh / Label3D | Authored in-repo (Phase 2) | PLACEHOLDER (test scene) |

## External assets

Both packs are by Quaternius (https://quaternius.com, https://www.patreon.com/quaternius), licensed
**CC0 1.0 Universal** (https://creativecommons.org/publicdomain/zero/1.0/). The original License.txt
is copied next to each model folder. Source copies live in `D:\MysticCourierAssets`. Imported
2026-10-18 (Phase 5A) as FBX (the packs ship no GLB/glTF); Godot 4.7 native FBX importer, default
settings (LODs + shadow meshes on). Embedded flat-colour materials are kept; there are no textures.
Modifications: none to the files. Each model is wrapped in a prop scene that scales it, centres it,
and adds collision and a CameraOccluder.

| Model file | Source pack / path | Wrapper scene | Scale | Tris |
|---|---|---|---|---|
| `assets/models/quaternius/medieval_village/House_1.fbx` | Medieval Village Pack - Dec 2020 / Buildings/FBX | `scenes/props/medieval/house_1.tscn` | 2.0 | 5758 |
| `.../medieval_village/House_2.fbx` | same | `scenes/props/medieval/house_2.tscn` | 1.6 | 7162 |
| `.../medieval_village/Inn.fbx` | same | `scenes/props/medieval/inn.tscn` | 1.35 | 7756 |
| `.../medieval_village/Blacksmith.fbx` | same | `scenes/props/medieval/blacksmith.tscn` | 1.6 | 7659 |
| `.../medieval_village/Mill.fbx` | same | `scenes/props/medieval/mill.tscn` | 1.8 | 8126 |
| `assets/models/quaternius/ultimate_nature/CommonTree_1..4.fbx` | Ultimate Nature Pack - Jun 2019 / FBX | `scenes/props/nature/common_tree_1..4.tscn` | 1.2-1.5 | 1352-2952 |
| `.../ultimate_nature/PineTree_1..3.fbx` | same | `scenes/props/nature/pine_tree_1..3.tscn` | 1.15-1.45 | 1692-2392 |
| `.../ultimate_nature/Rock_2.fbx`, `Rock_3.fbx`, `Rock_Moss_2.fbx` | same | `scenes/props/nature/rock_2.tscn`, `rock_3.tscn`, `rock_moss_2.tscn` | 2.2 | 72-80 |
| `.../ultimate_nature/Bush_1.fbx`, `Bush_2.fbx`, `BushBerries_1.fbx` | same | `scenes/props/nature/bush_1.tscn`, `bush_2.tscn`, `bush_berries_1.tscn` | 0.7-0.75 | 268-892 |

### Phase 5B additions (2026-10-18)

Same author and licence (Quaternius, CC0 1.0); each pack's License.txt is copied into its folder.
FBX, Godot 4.7 importer defaults, embedded flat-colour materials. Recolours are done at runtime by
`scripts/world/model_tint.gd` / `medieval_building.gd` (surface overrides by material name); the
files themselves are unmodified. 120 models are imported in total; every one is referenced by a scene.

| Folder (`assets/models/quaternius/`) | Source pack in `D:\MysticCourierAssets` | Models |
|---|---|---|
| `medieval_village/` | Buildings/Medieval Village Pack - Dec 2020 (Buildings + Props) | Bags, Barrel, Bell, Bell_Tower, Bench_1, Bonfire_Lit, Cart, Cauldron, Crate, Fence, Hay, MarketStand_1, MarketStand_2, Package_1, Package_2, Path_Straight, Well (+ 5A houses) |
| `modular_ruins/` | Buildings/Ultimate Modular Ruins Pack - Aug 2021 | Arch_Round, Bookcase_Full, Candles_1, Candles_2, Column_Round, Column_Round_Short, Column_Square, Floor_Squares, Pot1-3, Statue_Fox, Statue_Stag, Wall, Wall_Half |
| `modular_dungeon/` | Buildings/Updated Modular Dungeon - May 2019 | Bag_Standing, Banner, Banner_wall, Table_Big, Table_Small, Torch |
| `rpg_items/` | Items/Ultimate RPG Items Pack - Aug 2019 | Book2_Open, Chest_Closed, Crystal1/2/3/5, Potion1-6_Filled, Pouch, Scroll |
| `food/` | Items/Ultimate Food Pack - Oct 2019 | Apple, Apple_Green, Bottle1, Bread, Carrot, Fish, Jar_Large, Lettuce_Whole, Orange, Pumpkin, Tomato |
| `nature_crops/` | Tree/Nature Crops Pack - Jan 2020 | Carrot_3, Corn_4, Flower_3, Flowers_Crop, Lettuce_3, Mushroom_1-3, Pumpkin_Crop, Wheat_4 |
| `ultimate_nature/` | Tree/Ultimate Nature Pack - Jun 2019 | BirchTree_1-3, BirchTree_Autumn_1, BirchTree_Dead_1, BushBerries_2, CommonTree_5, CommonTree_Autumn_1/2, Flowers, Grass, Grass_2, Grass_Short, PineTree_4/5, Plant_1-5, Rock_5, Rock_6, Rock_Moss_4, Willow_1-3, Willow_Dead_1, WoodLog, WoodLog_Moss (+ 5A trees/rocks/bushes) |

Not used: packs without a License.txt (Modular Dungeon Pack - Jan 2018, RPG Asset Pack - May 2017,
Simple Nature Pack - Dec 2016), and the Ruins "Overgrown"/foliage pieces, which need texture files.
Authored (no licence needed): ground materials in `assets/materials/environment/` (NoiseTexture2D).

### Phase 5C additions (2026-10-18): characters

KayKit Adventurers Character Pack 2.0 (FREE) by Kay Lousberg (www.kaylousberg.com),
**CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/); credit optional, given here.
License.txt copied to `assets/characters/kaykit_adventurers/`. Source: the pack copy found at
`D:\courier-phase5a-assets\characters\KayKit_Adventurers_2.0_FREE` (the requested
`D:\MysticCourierAssets\Characters\` folder does not exist). GLB/glTF, unmodified, Godot 4.7 importer defaults.

| File | Used for |
|---|---|
| `Ranger.glb` | Courier (player) |
| `Barbarian.glb` + `items/mug_full.gltf` | Postmaster Bram |
| `Rogue.glb` | Merchant Mira |
| `Rogue_Hooded.glb` + `items/spellbook_open.gltf` | Alchemist Corvin |
| `Mage.glb` + `items/staff.gltf` | Mage Elowen |
| `Knight.glb` + `items/sword_1handed.gltf` | Villager Pip (child-scaled) |
| `animations/Rig_Medium_General.glb`, `animations/Rig_Medium_MovementBasic.glb` | Shared Rig_Medium clips for all six |
| `items/*_texture.png` | Textures referenced by the item glTFs |

Not imported: Assets/ weapons and shields other than the four above, FBX/OBJ duplicates.
The pack has no creature models, so Forest Slime and Frost Wisp keep their authored visuals.

### Phase 5D additions (2026-10-18): MegaKit pilot

Two Quaternius packs, both **CC0 1.0** per the included `License_Standard.txt` (copied unchanged
into each folder; "Models by Quaternius", attribution optional): **Medieval Village MegaKit
(Standard/free tier)** and **Stylized Nature MegaKit (Standard, 68 of 116 models)**. Source: the
copy at `D:\courier-phase5a-assets\Medieval Village MegaKit[Standard]` (the nature pack is in its
`field/` subfolder). glTF files and textures are unmodified; only the textures these 25 models
reference were copied, and their import is capped at 1024 px (`process/size_limit`).

| Folder (`assets/models/megakit/`) | Models (25) |
|---|---|
| `village/` (Medieval Village MegaKit) | Prop_Vine1, Prop_Vine2, Prop_Vine4, Prop_Vine5, Prop_WoodenFence_Single, Prop_WoodenFence_Extension1, Prop_ExteriorBorder_Straight1, Prop_ExteriorBorder_Corner, Prop_Wagon |
| `nature/` (Stylized Nature MegaKit) | Rock_Medium_1/2/3, Pebble_Round_1, Pebble_Round_3, Pebble_Square_2, RockPath_Square_Small_1/2/3, Mushroom_Common, Clover_1, Plant_7, Plant_7_Big, Bush_Common_Flowers, Flower_3_Group, Flower_4_Group |

Textures copied: `T_VineLeaf_png.png`, `T_WoodTrim_{BaseColor,Normal,Roughness}.png`,
`T_RockTrim_{BaseColor,Normal,ORM}.png`, `Flowers.png`, `Leaves.png`, `Leaves_NormalTree_C.png`,
`Mushrooms.png`, `PathRocks_Diffuse.png`, `Rocks_Diffuse.png`. Wrappers: `scenes/props/megakit/`.

### Phase 5E (2026-10-18): village terrain

No new external assets. Authored in-repo: `assets/shaders/village_ground.gdshader`,
`assets/materials/environment/village_ground.tres` (NoiseTexture2D inputs), and the generated
splat maps / layout in `assets/textures/terrain/` (`village_splat_a.png`, `village_splat_b.png`,
`village_layout.json`). The hill tree line reuses the Phase 5A Quaternius tree scenes.

### Phase 5F additions (2026-10-18): MegaKit buildings

More of the **Medieval Village MegaKit (Standard)** by Quaternius, **CC0 1.0** (`License_Standard.txt`
copied unchanged into the folder). Source: the same copy as Phase 5D,
`D:\courier-phase5a-assets\Medieval Village MegaKit[Standard]` (`glTF/`, `Textures/`). Copied by
`tools/prep_megakit_buildings.py`.

| Folder | Contents |
|---|---|
| `assets/models/megakit/buildings/` | 38 modular pieces (.gltf + .bin): plaster, uneven-brick and timber-grid walls with door/window openings, wall arch, wood and stone corners, two doors, four windows, four shutter types, tile roofs 4x4/4x6/6x6, tower roof, dormer, gable ends 4/6, wooden canopy, two chimneys, wall bracket, two balcony rails, plank floor |
| `assets/textures/buildings/` | 20 textures: `T_{WoodTrim,Plaster,RoundTiles,UnevenBrick,RockTrim,Brick}_{BaseColor,Normal}` at 1024 px, their roughness/ORM maps at 512 px, `T_MetalOrnaments_{BaseColor,Roughness}` at 512 px |
| `assets/materials/buildings/` | Authored: 9 shared materials (timber, planks, plaster, roof_tiles, stone, uneven_brick, brick, iron, windows) plus `embers.tres` |

Modifications: glTF image/texture references were removed; each `.gltf.import` maps the kit's
`MI_*` materials to the shared `.tres` files instead. Textures were downsized (Lanczos);
`T_RoundTiles_BaseColor` was desaturated and brightened so `MedievalBuilding.roof_color` can tint
each roof. Geometry is unmodified. The bell tower's bell reuses the Phase 5A `Bell.fbx`.
Building scenes (`scenes/buildings/`) are generated by `tools/generate_buildings.gd`.

### Phase 5F additions (2026-10-18): Armory weapons

**KayKit Fantasy Weapons Bits 1.0 (FREE)** by Kay Lousberg (www.kaylousberg.com), **CC0 1.0**
(`License.txt` copied unchanged). Source: the pack copy the user placed at
`assets/KayKit_FantasyWeaponsBits_1.0_FREE/` (not committed). The 23 glTF models on display in the
armory, plus `weapons_bits_texture.png` (1024 px), were copied unmodified to
`assets/models/kaykit_weapons/`: arrow_A/B, axe_A/B/C, bow_A_withString, dagger_A/B,
fistweapon_A_stacked, halberd, hammer_A/C, shield_A/B/C, spear_A, staff_B, sword_A/B/C/D/E, wand_A.
Each `.gltf.import` maps the pack's `weapons` material to `assets/materials/armory/weapons.tres`.

When adding an external asset, record: name, path, author, source URL, license (with a link), date
imported, and any modifications.

### Phase 5F (2026-10-18): input prompt icons
`assets/ui/input_prompts/input_prompts.png` (1774x887) is an AI-generated pixel-art input prompt
sheet supplied by the project owner (originally named `601f027d-f495-417a-9a52-8d86fcf11972.png`;
renamed). License: not recorded; supplied by the owner. `tools/crop_input_prompts.py` crops 62 keyboard and mouse icons
from it into `assets/ui/input_prompts/icons/*.png` (32 px tall, box-downsampled; source rectangles in
`regions.json`). Gamepad buttons and the "UI prompt examples" row are not exported. The sheet has no
I, O, P, T, U, Y, 0 or 7-9 keys. See `docs/PHASE5F_INPUT_PROMPTS.md`.

### Phase 5F (2026-10-18): Armory item icons
| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| HUD courier portrait | `assets/ui/hud/courier_portrait.png` | 256x256 render of the KayKit Ranger (CC0, KayKit Adventurers) | Rendered in-repo by `tools/render_courier_portrait.gd`; circle-masked by `assets/shaders/circle_mask.gdshader` (authored) | FINAL |
| Shop item icons (7, incl. the Hunting Bow) | `assets/ui/item_icons/*.png` | 16 px pixel art saved at 32x32 | Authored in-repo by `tools/make_item_icons.py` | PLACEHOLDER |
Swords and the Magic Staff show the existing KayKit `sword_1handed.gltf` / `staff.gltf` in the
courier's hand when equipped; the Battle Axe and Wooden Shield have no model.
