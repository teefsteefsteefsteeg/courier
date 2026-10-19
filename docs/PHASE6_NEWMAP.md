# Phase 6 — Runewood Highlands and the Sentinel Vault

Implementation in `D:\courier-phase5f-integrated`. The normal game still starts in
Willowmere. Main and other worktrees are not modified; nothing is pushed or merged.

## Playable scenes and routes

| Scene | Purpose |
|---|---|
| `scenes/levels/village.tscn` | Existing game/session root; includes the new gateway and persistent router |
| `scenes/phase6/village_gateway.tscn` | Northeast forest trail, stone gate at **(33, 0, -34)**; interact from **(33, 0, -31.5)** to travel |
| `scenes/phase6/runewood_outdoors.tscn` | Separate outdoor level with arrival, refuge, brook bridge, optional ruin loop, forest and elevated northern dungeon gate |
| `scenes/phase6/sentinel_dungeon.tscn` | Separate dungeon: descent stairs, guard hall, side reliquary, connecting passages and boss sanctuary |

The outdoor arrival is near **(-40, 0.9, 36)**. The nearby rune stone offers **Return to
Willowmere**. Follow the ochre road past Amberleaf Refuge and Moonbrook Bridge, then
up the eastern ridge. A side path visits the Broken Watch ruins. The dungeon gate is
at **(29, 6.2, -35)**; interact from the road near **(29, 5.9, -32)**. The dungeon
arrival/exit landing is **(0, 2.16, 15.5)**, above its physical stone staircase.
Returning from the dungeon places the courier just south of its outdoor gate.

`scripts/phase6/world_router.gd` detaches the current level scene and attaches the
destination PackedScene, retaining visited levels in a session cache. The existing
village root holds the one player, camera, services and UI throughout. Village
geometry, NPC processing and collisions are paused while away, then restored to their
previous values. No player, health, equipment, carrier, inventory or quest instance is
recreated. Dash/swing motion is cancelled at passage boundaries. HP and stamina remain
on the same CombatController/CombatHealth; the project has no separate MP system.

The old teleport network remains in Willowmere. Region-specific fog grids are saved
by `ExplorationService`; discovery IDs and portal activations remain global. Each
level has its own map image and landmark registry entries. Returning restores the
original surface map and fog. Legacy saves without region grids remain supported.

## Blender execution and sources

Executable actually used:
`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`

Verified version: **Blender 5.2.2 LTS**, hash `d13f752e3b9c`. `bpy` and the glTF
exporter were executed in background mode. No software was downloaded or installed.

| Editable Blender source | Export integrated in the game |
|---|---|
| `assets/blender/phase6/runewood_terrain.blend` | `assets/generated/phase6/runewood_terrain.glb` |
| `assets/blender/phase6/runewood_newmap_dressing.blend` | `assets/generated/phase6/runewood_newmap_dressing.glb` |

The terrain is an original triangulated height field with a sculpted valley, road
cut-ins, elevations, brook bed and an irregular mountain/cliff boundary. Grass
materials vary coherently across the landscape; roads and banks use separate material
regions. The bridge uses smooth collision ramps rather than snagging on decorative
mesh edges. `world_layout.json` provides the exact height samples and scenery collider
positions used to assemble the Godot level. Trees and rocks leave the main and side
paths clear. Boundary collision follows the mountain ring.

The dressing source imports actual models from
`assets/newmap/FreeVersion/AllModelsInOne/AllAssets_with_texture.glb`: Bridge01,
Stylized Hut01, Streetlamp01, Bench01, Barrel03, Box01, Wall_Stone01, Trunk02,
Trunk04, Foliage01 and RockMedium. Existing Quaternius CommonTree_1 complements the
deadwood with leafy forest clusters. Export-copy FBX materials are made opaque;
the original pack files are unchanged. Texture copies are packed into the Blender
source/export; Godot also extracts embedded textures beside the GLB during import.

The dungeon reuses the original Blender-authored modular kit already created in this
workspace. Its active source/export pairs are under `assets/blender/` and
`assets/generated/blender/`, with matching stems:

- `runewood_dungeon_entrance`, `crypt_stairway`, `crypt_wall_4m`, `crypt_floor_4m`
- `crypt_pillar`, `sentinel_rune_stone`, `amethyst_cluster`, `boss_heart_altar`
- `sentinel_boss_arena`, `crypt_brazier`, `ironbound_treasure_chest`

The side reliquary also places actual `Chest_Wood.gltf` and
`Vase_Rubble_Medium.gltf` models from `assets/newmap/fantasy/Exports/glTF/`.
Visual architecture is GLB-based; simple Godot shapes are used for collision and
attack telegraphs. Original material colors, metre scale and ground/grip origins
are retained. No fishing, tool, gear-upgrade or inventory features were added for
this map task. Earlier prototype assets remain on disk, but their village remodeling
and same-level underground prototype are not instanced by the active game.

Rebuild commands:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python tools/build_phase6_world.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --import
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/assemble_phase6_world.gd
```

`assets/blender/.gdignore` prevents duplicate automatic imports of editable `.blend`
sources. Keep generator changes in `tools/build_phase6_world.py` and
`tools/assemble_phase6_world.gd`; regenerate the corresponding outputs.

## Monsters and boss

Exact source models, used directly without replacing their geometry or rig:

- `assets/Bestiary - Dungeon Monsters Kit[Standard]/Exports/GLB (Godot-Unreal)/Imp.glb`
- `assets/Bestiary - Dungeon Monsters Kit[Standard]/Exports/GLB (Godot-Unreal)/Puglin.glb`

Both contain an Armature/skeleton and **zero animation clips**, confirmed by parsing
the GLB animation arrays. `scripts/phase6/bestiary_visual.gd` supplies limited
procedural breathing, locomotion limb swing, attack poses, hit flash/recoil and a
death fall. These are not claimed to be pack-supplied or authored animation clips.
The models are oriented to the existing enemy controller's -Z facing direction.

The guard hall contains an Imp and Puglin; the side reliquary has another Imp. They
reuse `ForestSlime` melee behavior and the existing `Enemy`/`CombatHealth` damage
architecture with the actual Bestiary models.

**Gorvath, Keeper of the Hollow** uses the larger Puglin model and 260 real HP:

- Detects the player in the final sanctuary, chases, and uses a 3.4 m close sweep
  with a red ground ring and 1.15 s windup (16 damage).
- Alternates with three delayed ground rune eruptions aimed at the courier's earlier
  position (13 damage), allowing movement and existing dash invulnerability to avoid hits.
- Uses the same CombatHealth and enemy collision layer as existing weapons/projectiles.
- Reacts to hits, falls on death, and grants **300 gold + 25 reputation** once.
- Stores `sentinel_defeated` in SaveGame's additive `world_progress` field, preventing
  repeat payouts and leaving the boss defeated in later loaded sessions.

The boss HUD is a top-centre dark panel with gold trim, boss name, red fill, smoothed
depletion and real current/max HP text. It binds directly to that boss's CombatHealth,
appears only during the encounter, and hides on arena exit or victory.

## Validation and captures

`tests/phase6_newmap_tests.gd` runs the real game from Willowmere. It uses real
interaction input and camera-relative movement over the main road, bridge and optional
ruin path; enters the dungeon; walks its stairs and chambers; kills the regular
monsters; takes a telegraphed boss hit; observes both attacks; checks the HP bar; defeats
the boss with existing live Magic Bolt projectiles; checks the one-time reward; walks
back out and returns along the outdoor road to Willowmere. It never reduces enemy HP
directly. It also verifies unchanged player/inventory identity, an in-progress quest,
HP/stamina across transitions, and the existing portal network after the trip.

`tests/phase6_world_state_tests.gd` covers independent map fog, discovery/portal
retention, region filtering, legacy save compatibility and saved boss victory flags.

Run headless for checks or omit `--headless` for actual GPU captures at 1600x900:

```powershell
$env:APPDATA = 'D:/courier-phase5f-integrated/validation/phase6/appdata'
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1600x900 --script res://tests/phase6_newmap_tests.gd
```

The APPDATA override isolates validation saves and avoids the session's restricted
normal user-data folder. The player's regular save is not used by these checks.

Actual rendered screenshots are under `docs/validation/phase6-newmap/`:

| File | Content |
|---|---|
| `01_newmap_overview.png` | Complete new terrain, roads, brook, forest and landmarks |
| `02_moonbrook_bridge_and_valley.png` | Traversed bridge and valley terrain |
| `03_broken_watch_landmark.png` | Optional elevated ruin route |
| `04_dungeon_entrance.png` | Reachable stone gate in the new map |
| `05_dungeon_interior.png` | Stairway and guard hall |
| `06_bestiary_guards.png` | Actual Bestiary models in the playable dungeon |
| `07_reliquary_chamber.png` | Side chamber encounter area |
| `08_boss_telegraph_and_health_bar.png` | Active boss, close tell and real 260/260 HP |
| `09_boss_rune_attack.png` | Distinct ranged attack telegraphs |
| `10_boss_damaged_hp.png` | Health bar depleted by real player projectiles |
| `11_boss_victory.png` | Defeated boss and awarded gold/reputation |
| `12_return_to_willowmere.png` | Successful return to the original world |

Final logs, asset inspection and suite results are in `validation/phase6-newmap/`.
The final GPU round trip completed **76 passed, 0 failed**, including twelve saved
gameplay captures. All captures were opened and visually inspected. The region/save
suite completed **12 passed, 0 failed**. The full set of **33 test scripts** passed
after targeted reruns: the pre-existing Phase 1 rapid zoom test passed in isolation
(52/0), and World/UI passed (127/0) after guarding the router when preview services
are deliberately absent. The final trip also covers transient HUD timers below
paused village nodes. Normal game startup was executed separately for 180 frames;
the native Godot process exited **0** (`boot.stdout.log`, `boot.stderr.log`).

The generated GLB audit reports **12,976 terrain/water triangles** and **415,587
triangles across 339 dressing mesh instances**, including the reused forest models.
Both new exports have embedded images and no external texture dependencies. See
`generated-mesh-audit.json`; source pack geometry is reused rather than subdivided.

Godot emits a certificate-store startup error in this restricted Windows session.
Raw third-party pack imports also emit existing case-sensitivity warnings. These are
separate from gameplay/script checks and generated asset validation.

## Remaining limits

- Procedural Bestiary posing is intentionally limited; polished authored animation
  clips are absent from the supplied pack.
- Encounter timing and balance have scripted validation, not a human playtest.
- Existing save limitations for deliveries in progress remain unchanged; this task
  preserves those quest objects across scene transitions, not across application quits.
- Git metadata belongs to `D:\courier\.git`, outside this session's writable root.
  Branch/commit creation was denied earlier in the session. No commit, push or merge
  is claimed for this work; review the mixed existing and new changes before staging.
