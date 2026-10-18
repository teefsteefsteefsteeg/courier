# Phase 4 live HUD and camera polish

Project: `D:\courier-phase4-live`, branch `phase4-live`.
F5 main scene: `res://scenes/levels/village.tscn`.

The active quest tracker is now the shared QuestManager-backed tracker at the
top-left. The secondary Phase 4 presentation tracker is suppressed only in the
live village, retaining its standalone preview behavior. Gold/reputation and
minimap stack at the top-right; combat stays bottom-left; package name/integrity
and magical conditions stack bottom-right using their measured content heights.
Prompts and notices wrap within the middle column. The Journal hint is bottom-center.

The post-office cargo exhibit remains an independent demonstration. Its placard
and models animate sample packages, but it never binds those samples to the
player's cargo HUD. That HUD is bound exclusively to PackageCarrier. The current
quest always comes from QuestManager. Completed objectives are removed from the map.

The isometric camera angles, movement, and zoom limits are unchanged. Intervening
post-office meshes now fade using camera-ray/AABB intersection checks, in addition
to the existing tree/cottage fading. A small YOU marker appears during occlusion.
Combat UI initializes from the current health/shield values when bound.

## Validation

Godot 4.7.2 import: success. All integrated regression suites pass:

| Suite | Checks passed |
| --- | ---: |
| Phase 1 | 52 |
| Phase 2 | 105 |
| Phase 3 | 79 |
| Phase 3 visuals | 123 |
| Phase 3 live demo | 14 |
| Phase 4 gameplay | 183 |
| Phase 4 visuals | 167 |
| Phase 4 presentation | 135 |
| Village quests | 95 |
| World/UI | 127 |
| HUD polish | 170 |

The HUD suite loads the configured main scene and checks player/quest bindings,
pickup, cargo-exhibit isolation, map movement and objective updates, two forest
enemies, Elowen delivery/rewards, cleared cargo panels, wall fading, M toggling,
and panel bounds/nonintersection at 1600x900, 1366x768 and 1280x720.

Rendered captures use the local NVIDIA Vulkan Forward+ renderer, with the real
village and cargo systems, at all three resolutions. Spawn, forest with cargo
warnings, and expanded map images are in `validation/hud-polish/`. They were
visually inspected. Captures automate scene setup and player placement; they are
not a claim of a human keyboard playthrough. Normal main-scene launches at each
resolution also exit 0 with no runtime errors.

One warning remains in `world_ui_tests`: it deliberately removes gameplay services
and the encounter integration reports no QuestManager. Normal village launches
do not emit this warning. The minimap remains the existing marker/grid design;
this change preserves its tracking and expanded-map behavior.

## Manual F5 verification

1. Open this project's `project.godot` (not another worktree) and press F5.
   The courier starts inside the post office at (-15, 0, -5.6). Verify the courier
   is visible, combat is bottom-left, and the minimap is under the wallet.
2. Walk with WASD toward the marked Courier Guild Board, near (-11.6, 0, -10.3).
   Press E when prompted and accept **The Dragon Egg**. Close the board with Esc.
   The top-left tracker should now show this actual quest.
3. Follow the pickup marker to the egg near (-19.2, 0, -2.6); press E. Both cargo
   panels should appear bottom-right. The central cargo exhibit is not this pickup.
   Interact with the exhibit and verify it cannot replace the carried egg's HUD.
4. Leave through the post office's east doorway and follow the path to Whisperwood
   at (14, 0, -20). Space fires Magic Bolt in the facing direction; Shift dashes/runs;
   Q toggles Package Shield while carrying. Fight or evade the Slime and Wisp.
5. Enter the Forest Clearing near (14, 0, -31.2), then talk to Mage Elowen nearby
   with E. Verify rewards, removed cargo panels and cleared objective marker.
   Return to the village along the same path.
6. Press M twice to expand/close the map; press J to open/close the journal.
   Repeat at 1600x900, 1366x768 and 1280x720. Long prompts, notices and warnings
   should wrap without covering the corner panels. Walk behind trees/building
   edges and verify they fade and the courier remains trackable.

Direct launch: `godot --path D:\courier-phase4-live`
