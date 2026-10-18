# TODO

## Phase 1 follow-ups (open)
- [ ] Manual playtest with a real keyboard: WASD, Shift, E, F3, mouse wheel (see DEVELOPMENT_LOG "Not verified").
- [ ] Tune movement feel after the playtest (walk 4.5 / run 7.5 m/s, accel 35, decel 45, turn sharpness 14, follow sharpness 7).
- [ ] Open the project once in the Godot editor UI and confirm the scenes look as authored.
- [x] Occlusion: trees and cottages fade when they hide the player (CameraOccluder/OccluderFader). Crates and stones still do not.
- [ ] Shadow edges show slight stair-stepping. Tune `directional_shadow_*` once real art exists.
- [ ] Add gamepad bindings (left stick, buttons) to the Input Map.
- [ ] The NPC is a `StaticBody3D`. Switch to `CharacterBody3D` or `AnimatableBody3D` if NPCs need to walk.

## Later phases (not started; do not implement until instructed)
- [ ] Data-driven quests and objectives (Resources).
- [ ] Package definitions and modifiers (integrity, temperature, instability, curse, hydration, deadline).
- [ ] Combat: magic bolt, dash, package shield. Two enemy types.
- [ ] Dialogue *data* (branching, conditions); inventory, money and reputation UI. (Dialogue box and quest journal UI are done on `world-ui`.)
- [ ] Versioned save/load.
- [x] Locations: post office hub, village, forest entrance with clearing. Five NPC scenes (`world-ui`).
- [ ] Replace all PLACEHOLDER art with licensed low-poly assets (see ASSET_MANIFEST.md).

## World & UI follow-ups (branch `world-ui`)
- [ ] After merging `gameplay`: set the exported `npc_id` on the five character scenes (currently metadata), then
      instance `gameplay_services.tscn`, the quest board, package pickups and destination areas at the Marker3D spots.
- [ ] Turn off `QuestJournal.use_sample_data_when_unconnected` once the quest system is always present.
- [ ] Manual playtest: dialogue flow feel, typewriter speed (55 chars/s), journal with mouse and keyboard focus.
- [x] Hide the interaction prompt and location banner while the journal is open (they are only dimmed).
- [ ] Standing stones and small props can still briefly hide the courier; consider occluders for them.
- [ ] Profile the village (12 omni lights, about 120 occluders) on lower-end hardware.
- [ ] Portrait art for the dialogue box (currently a coloured initial).
