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
## 2026-10-18 — World & UI (branch `world-ui`)

Scope: fantasy village hub, post office, forest entrance, NPC visual scenes, dialogue UI, quest
journal UI. Gameplay systems (quests, packages, wallet) live on the `gameplay` branch and were
**not** modified here; `npc.gd`, `player.tscn` and the Phase 1 test yard are untouched.

### New content
```
scenes/levels/village.tscn            NEW MAIN SCENE: Willowmere village hub (88 x 88 m playable)
scenes/locations/post_office.tscn     open-front cutaway hall: counter, mail shelves, sorting table,
                                      mailbox, lamp, quest-board / parcel marker spots, zone
scenes/locations/forest_entrance.tscn "Whisperwood" gate, tree wall, path, Moonstone Clearing
                                      (standing stones + glowing crystals), two zones
scenes/props/                         cottage (recolourable @tool), well, lamp_post (OmniLight),
                                      market_stall, signpost (@tool text), barrel, bench, bush,
                                      mushroom_cluster
scenes/npc/characters/                postmaster_bram, merchant_mira, alchemist_corvin,
                                      mage_elowen, villager_pip (instances of npc.tscn + costume)
scenes/ui/                            dialogue_box, quest_journal, location_banner
assets/ui/courier_theme.tres          shared Theme (plum/gold frames, parchment pages, variations)
scripts/world/                        Cottage, Signpost, LocationZone, CameraOccluder, OccluderFader
scripts/ui/                           DialogueBox, QuestJournal, JournalData, LocationBanner, InputHints
tests/world_ui_tests.gd               113 headless checks
tests/capture_world_screenshots.gd    GPU screenshots -> docs/screenshots/world_ui/
```

### Village layout (world metres)
Square and well at the origin. Post office at (-14, -6), entrances east (to the square) and south.
Market stalls at (11..16, -2.6). Alchemy shop at (4, 12). Whisperwood gate at (14, -20), clearing
at (14, -34). Ten cottages, lamp posts, signposts. Invisible boundary at 44 m in each direction,
ringed by trees. Spawn: inside the post office, one step from the counter.

### Integration points for the gameplay branch
- **NPC ids** match the quest data (`postmaster`, `village_merchant`, `village_alchemist`,
  `forest_mage`; plus `villager_pip`). They are stored as `metadata/npc_id` because the `npc_id`
  export only exists on `gameplay`. After merge, set the exported `npc_id` on each character scene
  (or keep the metadata: `JournalData.npc_display_name` reads either).
- **Marker3D spots** for gameplay objects: `PostOffice/Markers/QuestBoardSpot`,
  `PostOffice/Markers/ParcelPickupSpot`, `Markers/MarketDeliverySpot`,
  `Markers/AlchemyDeliverySpot`, `ForestEntrance/Markers/ForestClearingSpot`.
- **Dialogue** binds to every NPC's existing `spoke(npc_name, line)` signal, so gameplay's
  `NPC.say()` and quest-behaviour lines show in the box without code changes.
- **Journal** finds the QuestManager through its `quest_manager` group and reads it by duck typing
  (`get_quest_ids/get_definition/get_state`, `QuestState.Status` resolved by name). There is no
  compile-time dependency, so it works before and after the merge. Without a manager it shows
  clearly labelled preview entries (`use_sample_data_when_unconnected`; disable for release).
- `project.godot`: `toggle_journal` (J) was inserted *before* `toggle_debug_hud` so it does not
  collide with gameplay's `drop_package` added after it. `run/main_scene` now points at the
  village; gameplay's services scene still has to be instanced into the village after merge.

### Design decisions
- **Dialogue box over speech bubbles.** The box hides the NPC's Label3D bubble when it takes a
  line. Interact while typing completes the line; interact afterwards passes through to the player
  so the NPC gives its next line; Escape closes; walking out of range closes. `play_lines()` queues
  scripted sequences. The `[E] Talk to` prompt is suppressed while the box is open.
- **Modal journal.** While open it joins the `ui_modal` group (dialogue ignores input) and pauses
  `PlayerController.input_enabled`, restoring the previous value on close.
- **Location zones** are nested Area3Ds with `zone_priority` (Area3D already has `priority`).
- **Occlusion fading** (Phase 1 TODO). A CameraOccluder under each tree and cottage defines a
  vertical segment plus radius. OccluderFader casts the camera ray from the player's feet and head
  and fades occluders with `GeometryInstance3D.transparency`, so shared materials are untouched.

### Validation performed
1. `godot --headless --import`: no errors or warnings.
2. `--check-only` on every script: no errors or warnings.
3. `godot --headless --path . --quit-after 180` (village boot): exit 0, no output.
4. `tests/phase1_tests.gd`: **52/52** (the prompt refactor did not regress anything).
5. `tests/world_ui_tests.gd`: **113/113** in every run. I ran the full suite three times after
   adding the occlusion tests, and an earlier version six times, with no flakes. It covers:
   - Layout, and each NPC's name, id and costume.
   - Spawn, walking out of the post office, and the walls and counter blocking movement.
   - Passing the forest gate, nested zone banners, and occlusion fading out and back in.
   - The dialogue flow (typing, skip, next line, Escape, walking away) and scripted lines.
   - The journal's tabs, selection, objectives, reward and modal input.
   - The QuestManager adapter against a duck-typed fake: status mapping, giver-name lookup, and a
     live refresh on `quest_state_changed`.
6. `tests/capture_world_screenshots.gd` on the GTX 1060: I inspected all 10 screenshots
   (`docs/screenshots/world_ui/`).

### Issues found and fixed
- `LocationZone.priority` clashed with `Area3D.priority` and caused a parse error. Renamed it to
  `zone_priority`.
- The eave hid the post office sign. Moved the sign to the west inner wall and narrowed the eaves.
- The courier was fully hidden by trees in the clearing. Added occlusion fading.
- A dialogue test was flaky: two physics frames can elapse within one main-loop iteration without
  an input flush. Tests now call `Input.flush_buffered_events()` after injecting events.
- The journal subscribed to the quest manager only at startup. It is now also found lazily on
  refresh.

### Not verified
- A real human with keyboard and mouse. Journal clicks were tested by emitting `pressed`.
- The merge with `gameplay`: the adapter was tested against a fake with the same public surface,
  not the real QuestManager.
- Performance with about 120 fading occluders and 12 omni lights was not profiled.
- Opening the new scenes in the editor UI (only the headless import ran).

## 2026-10-18 — World & UI: journal hides the HUD

### Behavior
- `InteractionPrompt` and `LocationBanner` join the `hidden_by_journal` group
  (`QuestJournal.HIDDEN_WHILE_OPEN_GROUP`). `QuestJournal.open()` hides every layer in that group and
  records its prior visibility; `close()` restores it. A layer that was already hidden stays hidden.
- Only the layer's `visible` is toggled, so the prompt's own state (focus, dialogue suppression) is
  kept and comes back unchanged.

### Tests
- New `_test_journal_hides_hud` in `tests/world_ui_tests.gd`: prompt and banner hidden on open and
  restored on close; a pre-hidden banner stays hidden; opening the journal over dialogue hides the
  HUD and blocks interact; Escape closes only the journal and the prompt stays suppressed until the
  dialogue closes.

### Validation performed
1. `godot --headless --path . --import`: exit 0.
2. `godot --headless --path . --script res://tests/world_ui_tests.gd`: **126/126 passed**.
3. `godot --headless --path . --script res://tests/phase1_tests.gd`: **52/52 passed**.
4. `git diff --check`: passed.
