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

## 2026-10-18 — Phase 2: Quest & Delivery System (branch `gameplay`)

### Starting state
- Worktrees: `D:/courier` (main), `D:/courier-gameplay` (**gameplay**, used for this phase) and
  `D:/courier-world` (world-ui). All three were at `408bc64` and clean, with no uncommitted changes to preserve.
- No UI integration contract existed, so I defined one in `docs/UI_INTEGRATION.md`.

### Ownership boundary used
- **Not edited (World/UI-owned):** `scenes/levels/*`, `scenes/ui/*`, `scripts/ui/*`, `scenes/props/*`, `scenes/camera/*`.
- **Edited (gameplay-owned, additive only):**
  - `scripts/npc/npc.gd`: `npc_id`, `say()`, and a child-behaviour hook (`get_interaction_line`).
  - `scenes/player/player.tscn`: added a `PackageCarrier` node.
  - `project.godot`: added the `drop_package` (G) input action.
- **New:** `scripts/quests/`, `scripts/packages/`, `scripts/world_objects/`, `scripts/gameplay_ui/`,
  `scenes/gameplay/**`, `data/packages/`, `data/quests/`, and the tests.
- Integration is demonstrated in the isolated sandbox `scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn`.
  The main scene is still `test_yard.tscn`.

### Architecture
- **Resources (static data):** `QuestDefinition`, `QuestObjective` (TALK_TO_NPC / PICK_UP_PACKAGE /
  REACH_DESTINATION / DELIVER_PACKAGE), `QuestReward`, `PackageDefinition`. Authored as `.tres` in `data/`.
- **Runtime:** `QuestState` (a Resource, ready for saving), `PackageInstance` (RefCounted, holds the
  current integrity), and `QuestManager` (owns every state and enforces the rules). `CourierWallet` holds gold and reputation.
- **No Autoload.** `gameplay_services.tscn` (QuestManager + CourierWallet) is a scene, found through the groups
  `quest_manager` and `courier_wallet`. Promoting it to an Autoload is a World/UI decision.
- **Quest lifecycle:** AVAILABLE → (accept) ACCEPTED → (first objective progress) ACTIVE → (last
  objective) COMPLETED → (reward granted the same frame) REWARDED. ACCEPTED/ACTIVE → FAILED via
  `fail_quest`, which confiscates the package; FAILED → AVAILABLE via `reset_failed_quest`.
- **Rules:** objectives complete strictly in order. Only one delivery may hold the slot. Duplicate
  accepts are rejected. `grant_reward` is guarded by `reward_granted` plus the COMPLETED status.
- **Packages:** `PackagePickup` in source mode is visible only while a quest's current objective is to
  pick it up; in dropped mode it holds the same `PackageInstance`, so integrity is preserved.
  `PackageCarrier` holds one package and spawns a dropped pickup on G. Packages leave play on delivery or failure.
- **NPC delivery:** `QuestNPCBehaviour` checks, in order: delivery attempt (accept or reject) → TALK objective →
  "waiting" line → "after delivery" line → the NPC's default lines.
- **Quests:**

  | Quest | Objectives | Reward |
  |---|---|---|
  | Q001 First Delivery | talk to Postmaster → pick up parcel → deliver to Merchant Mira | 50 Gold, 5 Reputation |
  | Q002 The Dragon Egg | pick up egg → reach Forest Clearing → deliver to Mage Elowen | 120 Gold, 20 Reputation |
  | Q003 Unstable Potion | pick up crate → deliver to Alchemist Corvin | 90 Gold, 15 Reputation |

  All packages behave normally. Temperature, curse and instability are deferred to Phase 3.

### Validation performed (all actually executed, Godot 4.7.2)
1. `--headless --import`: no errors or warnings. `--check-only` on every new and changed script: clean.
2. Booted the main scene (`test_yard`) headless for 120 frames: exit 0, no errors. The player now has a
   carrier but there is no QuestManager in that scene, and that is handled.
3. Booted the sandbox headless: no errors or warnings.
4. **`tests/phase2_tests.gd`: 105/105 passed.** It covers:
   - quest data, NPC ids and dialogue per state;
   - board UI (E opens it, player input freezes, the Accept button works, incompatible contracts are disabled, Esc closes it);
   - duplicate, incompatible and unknown accepts rejected;
   - the TALK objective and pickup gating;
   - pickup, carrying a second package blocked, drop and re-pickup with integrity kept;
   - wrong recipient (2 NPCs), correct delivery, rewards of 50/5 → 170/25 → 260/40;
   - duplicate reward, re-delivery and re-accept blocked;
   - REACH_DESTINATION via a real physics overlap;
   - fail, confiscate, reset and retry;
   - exact state-transition sequences;
   - the HUD tracker, indicator, wallet and toasts;
   - an E-key path through InteractionDetector.
5. **Phase 1 regression `tests/phase1_tests.gd`: 52/52 passed** after the Phase 2 changes.
6. `tests/capture_phase2_screenshots.gd` rendered on the GTX 1060 (Forward+). I inspected the board window,
   tracker, carried parcel, wrong-recipient bubble, delivery bubble and wallet. Screenshots are in `docs/screenshots/phase2/`.

### Issues found and fixed during the phase
- Tracker stayed visible after a reward: REWARDED/FAILED were emitted before the delivery slot was freed.
  The slot is now released first, and the tracker also listens to `active_delivery_changed`.
- Toast backlog lagged behind events: the current toast's time is now capped while messages are queued (1 s each).
- One test assertion was wrong (it expected the default line index to repeat); it now checks the objective index.

### Not verified
- Real keyboard and mouse input. Tests use `Input.parse_input_event`, direct `Interactable.interact()` and
  `Button.pressed.emit()`. Mouse clicking on Accept and keyboard focus navigation in the board were not exercised.
- Opening the project in the editor UI.
- Integration into real World/UI levels. Only the sandbox exists.
- Save/load of quest state (out of scope).
