# Phase 4 Visual Contract — Combat Visual Slice

Owner: Phase 4 VISUAL worker (branch `phase4-visual`).
Scope: low-poly Forest Slime and Frost Wisp models, idle/move/hit/death animation,
magic bolt / dash / package-shield VFX, floating damage numbers, a compact combat HUD,
a gameplay signal adapter and a standalone forest encounter showcase.
All geometry is procedural (Godot `PrimitiveMesh` re-emitted with flat normals), so
there are no imported or downloaded assets.

## Owned paths

| Path | Contents |
| --- | --- |
| `assets/materials/combat/*.tres` | Shared `StandardMaterial3D`s (slime, wisp, bolt, impact, dash, shield, forest props) |
| `scripts/phase4_visual/lowpoly.gd` | Faceted mesh builders, material loader, triangle counting |
| `scripts/phase4_visual/enemy_visual.gd` | Base enemy visual: state machine, hit flash, knockback, `bind_health()` |
| `scripts/phase4_visual/forest_slime_visual.gd` | Forest Slime model and poses |
| `scripts/phase4_visual/frost_wisp_visual.gd` | Frost Wisp model and poses |
| `scripts/phase4_visual/magic_bolt_vfx.gd` | Bolt projectile, trail, impact burst |
| `scripts/phase4_visual/dash_vfx.gd` | Dash afterimages, wind streak, arrival puff |
| `scripts/phase4_visual/package_shield_vfx.gd` | Package shield bubble and rune ring |
| `scripts/phase4_visual/damage_number_vfx.gd` | Floating damage / "Blocked" numbers |
| `scripts/phase4_visual/combat_hud.gd` | Compact combat HUD (CanvasLayer) |
| `scripts/phase4_visual/combat_visual_adapter.gd` | Signal-name adapter: gameplay → visuals |
| `scripts/phase4_visual/forest_encounter_showcase.gd` | Showcase scene builder and preview triggers |
| `scenes/phase4_visual/forest_encounter_showcase.tscn` | **Showcase / demo scene** |
| `scenes/phase4_visual/enemies/{forest_slime,frost_wisp}.tscn` | Enemy visual scenes |
| `scenes/phase4_visual/vfx/*.tscn` | Single-node VFX scenes (bolt, dash, shield, damage number) |
| `scenes/phase4_visual/ui/combat_hud.tscn` | Standalone HUD scene |
| `scenes/gameplay/phase4_visual/combat_visual_layer.tscn` | Drop-in integration layer (Effects + CombatHUD + CombatVisualAdapter) |
| `tests/phase4_visual_tests.gd` | Headless automated checks |

No other files are touched: not `player.tscn`, `project.godot`, `scripts/ui/**`, the
existing world/UI scenes, or any gameplay combat or enemy code.

## Running

```
godot --headless --path . --import
godot --headless --path . --script res://tests/phase4_visual_tests.gd   # exit code = failures
godot --path . res://scenes/phase4_visual/forest_encounter_showcase.tscn
```

Showcase controls (preview mode only; physical keys, no Input Map changes):
`1` magic bolt · `2` dash · `3` package shield on/off · `4` take a hit ·
`5` enemies move/idle · `R` reset · `P` auto demo on/off. The auto demo runs on boot and
cycles every effect. Pressing any preview key turns it off.

## Gameplay interface consumed (opportunistic)

The adapter connects **by signal name, only if the signal exists**. If no gameplay node is
present, the scene stays in preview mode and boots without errors. Handlers expect these
argument counts:

| Node | Signal | Visual response |
| --- | --- | --- |
| CombatController | `magic_bolt_fired(origin: Vector3, direction: Vector3)` | Bolt VFX from origin (range `bolt_range`, 12 m). Starts the HUD bolt cooldown estimate |
| CombatController | `dash_started()` | HUD "Dash: Dashing". Records the actor position as the dash start |
| CombatController | `dash_finished()` | Afterimage trail from the dash start to the actor. Starts the HUD dash cooldown estimate |
| CombatController | `shield_changed(active: bool, durability: float)` | Shield bubble follows the actor. HUD shield row |
| CombatController | `target_hit(target: Node, amount: float)` | Nearest bolt bursts at the target, damage number, `play_hit` on the target's visual (skipped when that visual is bound to a health node) |
| CombatHealth (player) | `health_changed(current, max)` | HUD health row |
| CombatHealth (player) | `damaged(amount, source_position)` | Red floating damage number over the actor |
| CombatHealth (enemy) | `damaged(amount, source_position)` | `play_hit(source_position)`: flash and knockback away from the source |
| CombatHealth (enemy) | `died()` | `play_death()`, then `death_finished`, then the visual hides |

`durability` is a 0..1 ratio. Values above 1 are treated as points: the shield divides by
`durability_scale` (default 100) and the HUD treats them as a percent.
`apply_damage` is never called. The visual layer is read-only toward gameplay.

Optional methods, polled only if present: `get_bolt_cooldown_remaining()` /
`get_bolt_cooldown()` and `get_dash_cooldown_remaining()` / `get_dash_cooldown()` on the
controller. When they are present the HUD shows exact cooldowns. Otherwise it estimates
them with `bolt_cooldown_estimate` (0.6 s) and `dash_cooldown_estimate` (0.9 s).

## Integration recipe (integrated branch)

1. Instance `res://scenes/gameplay/phase4_visual/combat_visual_layer.tscn` into the
   gameplay level (any Node3D at the world origin works best: effects use its local space).
2. Either set `CombatVisualAdapter.combat_controller_path` / `player_health_path`, or leave
   them empty. With `auto_discover` on, the adapter searches `current_scene` for the first
   node exposing `magic_bolt_fired`, retrying every `discovery_interval` (1 s, up to 10
   times). The controller's parent becomes the `actor`, and a sibling exposing
   `health_changed` becomes the player health.
3. For each enemy, instance `forest_slime.tscn` / `frost_wisp.tscn` as a child of the
   gameplay enemy body and call `adapter.bind_enemy(enemy_combat_health, visual)` (or
   `visual.bind_health(enemy_combat_health)` directly). If `target_hit` reports the enemy
   body, the adapter also finds a visual child automatically.
4. Drive locomotion visuals from gameplay: `visual.play_move()` / `visual.play_idle()`.

The HUD sits on CanvasLayer 6, bottom-left, and never edits the shared HUD.

## Visual API summary

`enemy_visual.gd` (base of both enemies):
`play_idle()`, `play_move()`, `play_hit(source_position := Vector3.INF)`, `play_death()`,
`reset_visual()`, `advance(delta)` (used when `auto_animate = false`), `is_dead()`,
`bind_health(node) -> bool`, `unbind_health()`.
Signals: `state_changed(new, old)`, `hit_played(source)`, `death_finished`.
States: `IDLE, MOVE, HIT, DEAD`. HIT returns to the interrupted loop state after
`hit_duration` (0.35 s). DEAD ignores further input.

Budgets: each enemy stays under 600 triangles (asserted in tests). Slime and wisp
materials are duplicated per instance so hit flashes never leak.

## Tests

`tests/phase4_visual_tests.gd` covers material and scene loading, faceted mesh triangle
counts, the slime and wisp parts and budgets, every animation state with its transitions
and signals, enemy health binding, bolt flight / impact / self-free, dash fade order,
shield raise / durability colour / follow / collapse, damage numbers, all HUD rows,
adapter preview mode, adapter wiring against runtime-mocked CombatController /
CombatHealth nodes (including cooldown polling and no double hits), auto-discovery, and
the full showcase loop (bolt cooldown, enemy defeat and respawn, dash, shield absorb,
health loss, wander, reset, gameplay link disabling preview, auto demo).
