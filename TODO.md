# TODO

## Phase 1 follow-ups (open)
- [ ] Manual playtest with a real keyboard: WASD, Shift, E, F3, mouse wheel (see DEVELOPMENT_LOG "Not verified").
- [ ] Tune movement feel after the playtest (walk 4.5 / run 7.5 m/s, accel 35, decel 45, turn sharpness 14, follow sharpness 7).
- [ ] Open the project once in the Godot editor UI and confirm the scenes look as authored.
- [ ] Occlusion: trees and stacked crates can hide the player from the fixed camera. Consider fading or dithering occluders.
- [ ] Shadow edges show slight stair-stepping. Tune `directional_shadow_*` once real art exists.
- [ ] Add gamepad bindings (left stick, buttons) to the Input Map.
- [ ] The NPC is a `StaticBody3D`. Switch to `CharacterBody3D` or `AnimatableBody3D` if NPCs need to walk.

## Phase 2 follow-ups (open)
- [ ] Manual playtest of the sandbox with a real keyboard and mouse: E on board/NPCs/pickups, G drop, mouse clicks on Accept, Esc to close.
- [ ] **World/UI integration** (owned by World/UI, see `docs/UI_INTEGRATION.md` §4):
  - [ ] Hide InteractionPrompt while a modal UI is open (it currently shows under the board window).
  - [ ] Decide Autoload vs per-level `gameplay_services.tscn`.
  - [ ] Place board, pickups, the 4 quest NPCs and `forest_clearing` in the real hub/village/forest levels.
- [x] Phase 2 brought onto `main` (fast-forward to `cb67192`, 2026-10-18). `world-ui` not merged.
- [ ] Quest state is not saved yet. `QuestState.to_dict()` exists for the save phase; it needs `from_dict` and wallet serialization.
- [ ] Toasts queue sequentially (about 1 s each while backlogged). Consider stacking if many events fire at once.
- [ ] Board UI is built in code. Move the entry into its own `.tscn` if UI wants to restyle it in the editor.
- [ ] A dropped package lying in the world while its quest is rewarded or failed is freed only on failure. Reward cannot happen without delivering, so this is currently unreachable; revisit when more quest types exist.

## Later phases (not started; do not implement until instructed)
- [x] Data-driven quests and objectives (Resources). Done in Phase 2.
- [x] Basic packages with integrity value, money, reputation. Done in Phase 2.
- [ ] Phase 3: package modifiers (temperature, instability, curse, hydration, deadline) on top of `PackageInstance`.
- [ ] Combat: magic bolt, dash, package shield. Two enemy types.
- [ ] Dialogue system (replaces the speech bubble and `QuestNPCBehaviour` lines), quest journal, inventory.
- [ ] Versioned save/load.
- [ ] Locations: post office hub, village path, small forest.
- [ ] Replace all PLACEHOLDER art with licensed low-poly assets (see ASSET_MANIFEST.md).
