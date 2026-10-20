# Asset Manifest

### Phase 6 continuation (2026-10-19): original fishing rod

`assets/generated/tools/fishing_rod.tscn` is an original Mystic Courier procedural prop,
extended from the existing authored rod in `scenes/props/tools/fishing_rod.tscn`.
It uses Godot cylinders, a box and three low-resolution torus line guides (540 triangles),
four shared materials, a grip-centred pivot, a `Tip` attachment marker and optional capsule
collision (disabled while held). It is equipped by `data/items/fishing_rod.tres` in the playable
village. No vendor models were modified. Source: authored in this repository; no external asset
licence applies. Scale and placement instructions: `assets/generated/tools/README.md`.
Rendered verification and continuation status: `docs/PHASE6_CONTINUATION.md`.

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

### Phase 6 new region (2026-10-19): Runewood Highlands and Sentinel Vault

- Original terrain: `assets/blender/phase6/runewood_terrain.blend`, exported with
  Blender 5.2.2 LTS to `assets/generated/phase6/runewood_terrain.glb`.
- Composed environment: `assets/blender/phase6/runewood_newmap_dressing.blend`,
  exported to `assets/generated/phase6/runewood_newmap_dressing.glb`.
  Reuses the owner-supplied Alefran pack in `assets/newmap/FreeVersion/`:
  Bridge01, Stylized Hut01, Streetlamp01, Bench01, Barrel03, Box01, Wall_Stone01,
  Trunk02, Trunk04, Foliage01 and RockMedium. The pack's included license permits
  modification and use in games, but prohibits redistribution as standalone assets.
  Models are arranged/scaled and texture copies packed; original pack files remain unchanged.
- Leafy trees: existing Quaternius Ultimate Nature `CommonTree_1.fbx`, CC0.
  Blender export-copy materials corrected to opaque colors, without changing the source.
- Reliquary props: Quaternius Fantasy Props MegaKit, CC0, supplied under
  `assets/newmap/fantasy/`: `Chest_Wood.gltf`, `Vase_Rubble_Medium.gltf`.
- Monsters: Quaternius **Bestiary - Dungeon Monsters Kit [Standard]**, **QAL v1.0**,
  from the owner-supplied `assets/Bestiary - Dungeon Monsters Kit[Standard]/`.
  Actual `Exports/GLB (Godot-Unreal)/Imp.glb` and `Puglin.glb` are used, including
  the scaled Puglin boss. Original files and rigs remain unchanged. Supplied GLBs
  contain **no animation clips**; runtime posing is authored in
  `scripts/phase6/bestiary_visual.gd`. This pack is not CC0; retain its included license.
- Original Blender modular dungeon sources under `assets/blender/`, with matching
  exports under `assets/generated/blender/`: `runewood_dungeon_entrance`,
  `crypt_stairway`, `crypt_wall_4m`, `crypt_floor_4m`, `crypt_pillar`,
  `sentinel_rune_stone`, `amethyst_cluster`, `boss_heart_altar`,
  `sentinel_boss_arena`, `crypt_brazier`, `ironbound_treasure_chest`.

See `docs/PHASE6_NEWMAP.md` for provenance, reproduction commands, integration and
actual rendered validation. No external asset was downloaded for this work.

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

### Phase 5H additions (2026-10-19): RPG tools
**KayKit RPG Tools Bits 1.0 (FREE)** by Kay Lousberg (www.kaylousberg.com), **CC0 1.0**
(http://creativecommons.org/publicdomain/zero/1.0/; `License.txt` copied unchanged). Source: the
pack the user placed at `assets/KayKit_RPGToolsBits_1.0_FREE/` (from
`KayKit_RPGToolsBits_1.0_FREE.zip`; not committed, and given a `.gdignore` so Godot does not import
its FBX/OBJ duplicates). All 49 glTF models with their `.bin` files and the four textures
(`tools_bits_texture.png` atlas, `tools_bits_blueprint.png`, `tools_bits_map.png`,
`tools_bits_map_empty.png`) were copied unmodified to `assets/models/kaykit_rpg_tools/`. The pack
has no rig and no animations. Use (see `docs/PHASE5H_VILLAGE_AND_TOOLS.md` for the full inventory):

| Use | Models |
|---|---|
| Held tools (gameplay) | axe (Woodcutter's Axe), hammer (Carpenter's Hammer), pickaxe, shovel, trowel |
| Toolwright stall and pond dressing | anvil, grindstone, tongs, lantern, torch, bucket_metal, rope_bundle_A/B, blueprint_stacked, saw, chisel, wrench_A, pencil_A_long, journal_open, nail, screw_A, mallet (and the five tools above on the rack); Toolwright Hobb holds the hammer |
| Copied, not placed | blueprint, compass_base, drafting_compass, file, handdrill, handplane, journal_closed, knife, magnifying_glass, map, map_empty, map_rolled, pencil_A_short, pencil_B_long/short, scissors, screw_B, screwdriver_A/B_long/short(_color) (8), torch_burnt, wrench_B |

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Fishing rod | `scenes/props/tools/fishing_rod.tscn` | Primitive meshes (cylinders, box) with a `Tip` marker | Authored in-repo (the pack has no fishing rod) | PLACEHOLDER |
| Tool and material icons (13) | `assets/ui/item_icons/{fishing_rod,carpenter_hammer,woodcutter_axe,miner_pickaxe,garden_shovel,mason_trowel,pond_perch,silver_trout,golden_carp,wood,stone,iron_ore,clay}.png` | 16 px pixel art saved at 32x32 | Authored in-repo by `tools/make_item_icons.py` | PLACEHOLDER |
| Pond water, shore, walls | `scripts/world/pond.gd` | Procedural mesh and inline shader | Authored in-repo | FINAL |
| Tool sites (trees, ore rocks, dig spots, fence, wall, jetty, stall) | `scenes/world/tools/`, `scenes/locations/willowmere_pond.tscn`, `scenes/locations/tool_stall.tscn` | Composed from existing Quaternius/MegaKit props, KayKit RPG Tools and primitives | Generated by `tools/generate_tool_sites.gd` | FINAL |

### Phase 7 (2026-10-19)

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Courier Guild board | `assets/generated/phase7/courier_guild_board.glb` (source `assets/blender/phase7/courier_guild_board.blend`) | Blender model, flat materials, 2520 tris | Authored in-repo with `tools/build_phase7_props.py` (Blender 5.2.2) | FINAL |
| Garden bed, crop seedling | `assets/generated/phase7/{garden_bed,crop_seedling}.glb` (sources in `assets/blender/phase7/`) | Blender models, 968 / 152 tris | Authored in-repo with `tools/build_phase7_props.py` | FINAL |
| Whisperwood forest | `scenes/environment/whisperwood_forest.tscn` | Placement of existing Quaternius Ultimate Nature models and props | Generated by `tools/generate_whisperwood.gd` | FINAL |
| Crops (wheat, carrot, pumpkin) | `assets/models/quaternius/nature_crops/{Wheat_4,Carrot_3,Pumpkin_Crop}.fbx` | Existing Quaternius CC0 models, used by `data/crops/*.tres` | Quaternius (CC0) | FINAL |
| Seed, produce and armor icons (8) | `assets/ui/item_icons/{wheat_seeds,carrot_seeds,pumpkin_seeds,wheat,carrot,pumpkin,leather_vest,iron_mail}.png` | 16 px pixel art saved at 32x32 | Authored in-repo by `tools/make_item_icons.py` | PLACEHOLDER |
| Enhancement and hit flipbooks (14) | `assets/vfx/enhancement/{sparkle,aura,burst,impact,spark,nature_burst,swirl,bubbles,splash,bolt_flash,strike,flame,flame_b,blast}.png` + `frames.json` | Horizontal PNG strips, whitened for tinting (sparkle 24 f, aura 16 f, burst 14 f, impact 7 f, 15 fps) | **"Super Pixel Effects Gigapack - Will Tice / unTied Games"** (Free Version; raw pack in `assets/Super Pixel Effects Gigapack (Free Version)/`, not committed). Licence (untiedgames.com/files/license.txt): commercial and non-commercial use in a game OK, **attribution requested, no redistribution of the pack contents outside a game, no AI training**. Source frames: Status Effect Sparkling 001, Lightning Aura 002, Round Sparkle Burst 001/002, Symmetrical Impact 001, Sci-fi Spark Burst 001, Spell Absorb 001, Directional Bubble Burst 001, Burst Splatter 001, Lightning Burst 001, Lightning Strike 001, Fire Looping 003A/004A, Stylized Explosion 001 (Phase 8 tiers); built by `tools/prep_enhancement_vfx.py` | FINAL |
| Armor aura, swing arc (Binbun VFX) | `assets/vfx/BinbunVFX_Vol2/` (StatusFX `vfx_status_shatter.tscn`, BattleFX swing/slash/claw/charge/shield, shaders, scripts) | Godot scenes, shaders and GDScript | **Binbun3D (bun3d.com) StatusFX and BattleFX, CC0**; raw packs in `assets/BinbunVFX/`, `assets/StatusFXFree/`, `assets/bossEffect/` (not committed). Vendored by `tools/vendor_binbun_vfx.py` (res:// paths repaired, uids dropped). Used: shatter (armor aura), swing (melee arc) | FINAL |
| Interior furniture (38 models) | `assets/models/fantasy_props/` (`.gltf` + `.bin`, 13 trim textures at 1024 px) | Low-poly props: beds, tables, chairs, bookcases, cabinets, anvil, workbenches, weapon stands, candles, chandelier, barrels, crates... | **Fantasy Props MegaKit [Standard] by Quaternius, CC0** (raw pack in `assets/newmap/fantasy/`, not committed); copied by `tools/copy_fantasy_props.py`; used by `tools/generate_interiors.gd` | FINAL |
| Inventory window pieces (12) | `assets/ui/inventory/` (frame, parchment, tabs, holders, buttons, header, tool/bag icons) | Cropped PNGs | Humble Pixel inventory UI pack (humblepixel.itch.io; raw pack in `assets/inventory/`, not committed): may be used and modified in commercial and non-commercial projects, **no redistribution or resale of the assets**. Cropped by `tools/prep_inventory_ui.py` | FINAL |

### Phase 8: Wyrmfall Vale (2026-10-19)

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Water shaders and textures | `assets/vfx/water_kit/` (`shaders/lake.gdshader`, `water_common.gdshaderinc`, 4 textures, `presets/pond_clear.tres`, `presets/pond_toon.tres`, `LICENSE.txt`) | Godot shaders, PNG textures, ShaderMaterial presets | **REEBOO Labs - Godot Water Shader Kit (Free Sample)** (reebo0.itch.io/godot-water-kit; raw pack in `assets/waternature/`, not committed): use in commercial and non-commercial games OK, modify OK, credit appreciated, **no resale or redistribution as-is**. Vendored by `tools/vendor_water_kit.py` (res:// paths rewritten) | FINAL |
| Waterfall shader | `assets/shaders/waterfall.gdshader` | Spatial shader (scrolling streaks, plunge foam, faded sides) | Authored in-repo | FINAL |
| Wyrmfall terrain, collision, bridge deck, map | `assets/generated/wyrmfall/{terrain_<x>_<z>,terrain_shape_<x>_<z>,bridge_collision}.res`, `wyrmfall_map.png` (open world: four terrain tiles; the map image is the vale only) | Generated meshes / HeightMapShape3D / ConcavePolygonShape3D / image | Generated by `tools/generate_wyrmfall.gd` from `scripts/world/wyrmfall_layout.gd` | FINAL |
| Wyrmfall newmap meshes (24) and textures (20) | `assets/generated/wyrmfall/newmap/*.res` (`tex_*.res` = 512 px lossy WebP) | Meshes extracted per model with opaque materials; textures downscaled, normal maps dropped | Owner-supplied **Alefran FreeVersion pack** (`assets/newmap/FreeVersion/AllModelsInOne/AllAssets_with_texture.glb`, not committed): use in games and modification OK, **no redistribution of the unmodified assets**. Bridge01, Stylized Hut01, Market03, Barrel01/03, Box01, Bench01, Brazier, Ladder, Wheel_L, ClayVase01/03, FenceWood_H01, Streetlamp01, Wall_Stone01-05, Trunk02, Trunk04, RockMedium, RockSmall, Foliage01. Extracted by `tools/generate_wyrmfall.gd` | FINAL |
| Wyrmfall Vale open-world chunks | `scenes/world/chunks/wyrmfall/*.tscn`, `data/world/wyrmfall_chunks.tres` (the region scene and village gate were removed) | Generated scenes (existing Quaternius Ultimate Nature trees/undergrowth/rocks CC0, wayfarer gate, signposts, tool sites, forest slimes) | Generated by `tools/generate_wyrmfall.gd` | FINAL |

### Phase 8: weapon elemental VFX and ultimates (2026-10-19)

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Elemental flipbooks (9) | `assets/vfx/enhancement/{dust_ring,dust_puff,rubble,quake_blast,charge,warp,arc_ring,slash_flash,light_burst}.png` | Horizontal PNG strips (frames.json) | Super Pixel Effects Gigapack (Free Version), same terms as the other enhancement sheets (attribution, no redistribution outside a game); Symmetrical/Directional/Looping Smoke Burst 001, Epic Explosion 001, Sci-fi Charge Up 001, Sci-fi Warp 001, Lightning Burst 003, Directional Impact 001, Round Light Burst 001; built by `tools/prep_enhancement_vfx.py` | FINAL |
| Magic projectiles | `assets/vfx/BinbunVFX_Magic/` (effects, materials, shared scripts/shaders/textures) | Godot scenes, shaders, GDScript | **Binbun3D Magic Projectiles, CC0** (raw pack `assets/BinbunVFX/`, not committed; `.gdignore` added there); vendored by `tools/vendor_binbun_projectiles.py`; wave = Flame Slash, basic = Arcane Storm bolts | FINAL |
| Fire / explosion / smoke flipbooks | `assets/vfx/boss/{fire,explosion,smoke}_8x8.png` | 8x8 PNG flipbooks, 512 px | **Brackeys VFX bundle, CC0** (flipbooks by Thomas Iche; raw `assets/brackeys_vfx_bundle/`, not committed); vendored by `tools/vendor_boss_vfx.py`. Fire used by the +5 sword | FINAL |
| Storm vortex | `assets/vfx/boss_tornado/` (vortex scene, visual shader, 2 meshes, 3 noise PNGs) | Godot scene + VisualShader + OBJ | Owner-supplied `assets/bossEffect/tornado/` sample (**no licence file**; ask the owner before any redistribution); vendored by `tools/vendor_boss_vfx.py`. Used by the Arcane Storm (and planned for the dragon boss) | FINAL |

### Phase 8: recovery milestone 1, provisions and world-space VFX (2026-10-19)

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Food & Market models (19) | `assets/models/food_market/mdvl_food_*.glb` + `LICENSE.txt` | Low-poly glTF, one 256 px palette texture each | **Avramania Asset Library - Food & Market, Free edition, CC0** (raw pack in `assets/Food_Market/`, not committed; the author asks not to re-upload the pack as-is). Used by the Food Market stall, Grocer Tilda's apple and the rendered icons | FINAL |
| Provision icons from the UI sheet (6) | `assets/ui/item_icons/{health_potion,mana_potion,bread_loaf,red_apple,fresh_milk,raw_steak}.png` | 64x64 RGBA, cut from the sheet | Owner-supplied AI-generated UI sheet `assets/potion/01_image-01.png` (not committed; no licence file, treat as the owner's). Cut by `tools/crop_consumable_icons.py` | FINAL |
| Provision icons rendered (6) | `assets/ui/item_icons/{cheese_wheel,roast_ham,sweet_grapes,warriors_ale,berserker_draught,ironbark_stew}.png` | 64x64 renders of the Food & Market models | Rendered in-repo by `tools/render_food_icons.gd` (CC0 models) | FINAL |
| Ground effect decals | `assets/vfx/ground/{ring,scorch,cracks,rune_circle,glow}.png` and `*_emission.png` | Procedural PNGs | Authored in-repo by `tools/make_ground_vfx.py` | FINAL |
| Food Market stall | `scenes/locations/food_market.tscn`, `scenes/npc/characters/grocer_tilda.tscn` | Generated scene / NPC | Generated by `tools/generate_food_market.gd` (existing building materials, Food & Market models, KayKit Rogue) | FINAL |

### Phase 8: seamless open world (2026-10-20)

| Asset | Path | Type | Source / License | Status |
|---|---|---|---|---|
| Outlands (scenery round the playable areas) | `scenes/world/chunks/outlands/outlands.tscn`, `assets/generated/outlands/outlands_terrain.res`, `data/world/outlands_chunks.tres` | Generated low-poly terrain + ScatterField trees (existing Quaternius Ultimate Nature, CC0) | Generated by `tools/generate_outlands.gd` | FINAL |
| Unified world map | `assets/textures/map/world_map.png` | 768x1280 image over `ExplorationService.WORLD_RECT` | Baked by `tools/bake_world_map.gd` (village splats + `wyrmfall_map.png`) | FINAL |
