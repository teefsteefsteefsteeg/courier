# Mystic Courier — Development Log

## 2026-10-18 — Phase 1: Isometric Foundation

### Starting state
- `D:\courier` was empty: no project, no assets.
- Engine: **Godot 4.7.2.stable.official** (`D:\godot\Godot_v4.7.2-stable_win64[_console].exe`).
- Test GPU: NVIDIA GeForce GTX 1060 6GB, Vulkan 1.3, Forward+.

### Folder structure
```
project.godot                 Input Map, physics layers, physics interpolation, Forward+
scenes/
  levels/test_yard.tscn       MAIN SCENE (Phase 1 test yard)
  player/player.tscn          CharacterBody3D + components
  camera/iso_camera_rig.tscn  orthographic isometric rig
  npc/npc.tscn                reusable NPC (static body + Interactable + speech bubble)
  props/placeholder_*.tscn    crate / rock / tree (PLACEHOLDER art)
  ui/debug_hud.tscn, ui/interaction_prompt.tscn
scripts/
  components/                 MovementComponent, FacingComponent, InteractionDetector
  player/ camera/ npc/ ui/ interaction/
assets/materials/placeholder/ flat-colour StandardMaterial3D placeholders (ph_*.tres)
tests/
  phase1_tests.gd             headless automated checks (52)
  capture_screenshots.gd      windowed render + screenshots
```
Planned for later phases (not created yet): `data/` (quests, packages, modifiers as Resources),
`assets/models`, `assets/textures`, `assets/audio`, `scenes/locations/`.

### Design decisions
- **Components, not inheritance.** `PlayerController` only reads input and converts it to a
  world direction. Locomotion (`MovementComponent`), facing (`FacingComponent`) and interaction
  (`InteractionDetector`) are separate nodes wired via exported references, so NPCs and enemies can
  reuse them later.
- **Camera-relative input uses only camera yaw.** The camera's rotation is fixed; the follow only
  translates it, so direction mapping never changes while the camera moves (verified by test).
- **Physics interpolation enabled** (`physics/common/physics_interpolation`). The player moves in
  `_physics_process`; the camera rig follows `get_global_transform_interpolated()` in `_process` and
  has its own interpolation turned off. This avoids follow jitter on high-refresh displays.
- **Facing rotates only the `Visual` child**, never the physics body.
- **Interaction range = overlap of detector sphere (r 1.4 m) and Interactable sphere (r 0.6 m)**,
  i.e. ~2.0 m centre-to-centre. Closest enabled Interactable wins focus.
- **No autoloads** in Phase 1; none needed yet.
- Physics layers: 1 world, 2 player, 3 npc, 4 interactable.

### Controls (Input Map)
| Action | Binding |
|---|---|
| move_forward/back/left/right | W / S / A / D (physical keys) |
| run | Shift |
| interact | E |
| zoom_in / zoom_out | Mouse wheel up/down, `=` / `-` |
| toggle_debug_hud | F3 |

### Validation performed
1. `godot --headless --import`: no errors or warnings.
2. `--check-only` on every script: no errors or warnings.
3. `godot --headless --path . --quit-after 120` (main scene boot): exit 0, no errors.
4. `tests/phase1_tests.gd`: **52/52 passed**. It covers the Input Map bindings, the camera's
   orthographic projection and 45°/-35° angles, all 8 directions within 0.5° of the
   camera-relative target, acceleration and deceleration curves, walk and run speeds, the
   IDLE/WALK/RUN states, smoothed facing, a direction that stays constant while the camera follows,
   collision against a crate, the fence and an NPC, interaction focus at 1.5 m but not at 2.5 m or
   6 m, E doing nothing out of range, the prompt text, the NPC's reply, and zoom clamping and easing.
5. `tests/capture_screenshots.gd` on the GTX 1060: I visually inspected the spawn, moving,
   prompt, talking and zoomed-out screenshots. The iso angle, shadows, prompt and bubble render
   correctly.

### Issues found and fixed during the phase
- The first crate-collision test approached a box corner diagonally, so the player legitimately slid
  around it. I rewrote it as a head-on push into the face, which now verifies there is no
  penetration and no sideways drift.
- The speech-bubble text was jaggy because the font texture was minified about 4×. I retuned the
  Label3D (pixel_size 0.01, font 26).

### Not verified
- **A real human pressing keys.** Tests inject input through `Input.action_press` and
  `Input.parse_input_event`, which bypasses the physical keyboard. Physical W/A/S/D, Shift, E and
  F3 need a manual playtest.
- **Feel and tuning.** Speeds, acceleration, turn rate and follow sharpness are reasonable defaults,
  not playtested values.
- **Opening the project in the editor UI.** Only the headless editor import ran.
- **Performance.** The FPS seen (~55–60) was vsync-capped in a short capture. It was not profiled.
