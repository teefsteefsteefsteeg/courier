# TODO

## Phase 1 follow-ups (open)
- [ ] Manual playtest with a real keyboard: WASD, Shift, E, F3, mouse wheel (see DEVELOPMENT_LOG "Not verified").
- [ ] Tune movement feel after the playtest (walk 4.5 / run 7.5 m/s, accel 35, decel 45, turn sharpness 14, follow sharpness 7).
- [ ] Open the project once in the Godot editor UI and confirm the scenes look as authored.
- [ ] Occlusion: trees and stacked crates can hide the player from the fixed camera. Consider fading or dithering occluders.
- [ ] Shadow edges show slight stair-stepping. Tune `directional_shadow_*` once real art exists.
- [ ] Add gamepad bindings (left stick, buttons) to the Input Map.
- [ ] The NPC is a `StaticBody3D`. Switch to `CharacterBody3D` or `AnimatableBody3D` if NPCs need to walk.

## Later phases (not started; do not implement until instructed)
- [ ] Data-driven quests and objectives (Resources).
- [ ] Package definitions and modifiers (integrity, temperature, instability, curse, hydration, deadline).
- [ ] Combat: magic bolt, dash, package shield. Two enemy types.
- [ ] Dialogue system (replaces the Phase 1 speech bubble), quest journal, inventory, money, reputation.
- [ ] Versioned save/load.
- [ ] Locations: post office hub, village path, small forest. Four NPCs.
- [ ] Replace all PLACEHOLDER art with licensed low-poly assets (see ASSET_MANIFEST.md).
