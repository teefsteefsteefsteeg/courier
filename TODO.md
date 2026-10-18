# TODO

## Phase 1 follow-ups (open)
- [ ] Manual playtest with a real keyboard: WASD, Shift, E, F3, mouse wheel (see DEVELOPMENT_LOG "Not verified").
- [ ] Tune movement feel after the playtest (walk 4.5 / run 7.5 m/s, accel 35, decel 45, turn sharpness 14, follow sharpness 7).
- [ ] Open the project once in the Godot editor UI and confirm the scenes look as authored.
- [x] Occlusion: trees and cottages fade when they hide the player (CameraOccluder/OccluderFader). Crates and stones still do not.
- [ ] Shadow edges show slight stair-stepping. Tune `directional_shadow_*` once real art exists.
- [ ] Add gamepad bindings (left stick, buttons) to the Input Map.
- [ ] The NPC is a `StaticBody3D`. Switch to `CharacterBody3D` or `AnimatableBody3D` if NPCs need to walk.

## Phase 2 follow-ups (open)
- [ ] Manual playtest of the sandbox with a real keyboard and mouse: E on board/NPCs/pickups, G drop, mouse clicks on Accept, Esc to close.
- [x] **World/UI integration** (owned by World/UI, see `docs/UI_INTEGRATION.md` §4):
  - [x] Hide InteractionPrompt while a modal UI is open. The board window joins `ui_modal`; the prompt hides while that group is non-empty.
  - [x] Decide Autoload vs per-level `gameplay_services.tscn`: **per-level**, first child of `village.tscn`. Hub, village and forest are one scene, so nothing needs to survive a level change yet. Revisit with save/load or the first level transition.
  - [x] Place board, pickups, the 4 quest NPCs and `forest_clearing` in the real hub/village/forest levels.
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
- [ ] Dialogue *data* (branching, conditions); inventory, money and reputation UI. (Dialogue box and quest journal UI are done on `world-ui`.)
- [ ] Versioned save/load.
- [x] Locations: post office hub, village, forest entrance with clearing. Five NPC scenes (`world-ui`).
- [ ] Replace all PLACEHOLDER art with licensed low-poly assets (see ASSET_MANIFEST.md).

## World & UI follow-ups (branch `world-ui`)
- [x] After merging `gameplay`: set the exported `npc_id` on the five character scenes (currently metadata), then
      instance `gameplay_services.tscn`, the quest board, package pickups and destination areas at the Marker3D spots.
- [x] Turn off `QuestJournal.use_sample_data_when_unconnected` once the quest system is always present (off in the village; the default stays on for bare scenes).
- [ ] Manual playtest: dialogue flow feel, typewriter speed (55 chars/s), journal with mouse and keyboard focus.
- [x] Hide the interaction prompt and location banner while the journal is open (they are only dimmed).
- [ ] Standing stones and small props can still briefly hide the courier; consider occluders for them.
- [ ] Profile the village (12 omni lights, about 120 occluders) on lower-end hardware.
- [ ] Portrait art for the dialogue box (currently a coloured initial).
- [ ] Q001's pickup objective says "from the counter", but the parcel spot is beside the sorting table. Reword the data (Gameplay) or move `ParcelPickupSpot`.
- [ ] The gameplay HUD (wallet, tracker) stays visible, dimmed, under the open journal. Hide it only if toasts can be queued while hidden.
