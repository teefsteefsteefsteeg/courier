# Phase 4 integration: live encounter presentation (visual)

A self-contained presentation layer that gameplay instances into a level so
that the playable delivery encounter has combat feedback, package warnings and
a colourful forest route. It owns no gameplay state, and every connection is
made by signal or method **name**. With no gameplay present it boots in preview
mode without errors.

It reuses the Phase 4 visual slice unchanged:

| Reused | For |
| --- | --- |
| `scenes/gameplay/phase4_visual/combat_visual_layer.tscn` (CombatVisualAdapter, CombatHUD, Effects) | Magic Bolt, Dash and Package Shield VFX, damage numbers, bottom-left combat HUD |
| `scenes/phase4_visual/enemies/forest_slime.tscn`, `frost_wisp.tscn` | Enemy models plus idle/move/hit/death animation |
| `scripts/phase3_visual/package_status_probe.gd` | Package temperature / instability / integrity detection |

It adds:

* Floating enemy health bars: always on top, facing the camera, with a damage chunk, hit flash and shake, and a fade on death.
* Defeat bursts: a ring and a petal fountain in the enemy's tint.
* A delivery HUD: a top-right quest tracker and a top-centre package warning banner.
* A route indicator: gradient stepping-stone markers with a travelling pulse, flower tufts, and a quest beacon with an optional pinned marker.

## Files

```
scripts/phase4_integration_visual/
  encounter_presentation.gd     root: binding, enemy registry, routing to HUD/route
  enemy_health_bar.gd           floating bar
  defeat_burst_vfx.gd           death burst
  route_indicator.gd            route markers, flowers, quest beacon, pinned markers
  delivery_hud.gd               quest tracker + package banner (CanvasLayer 7)
  integration_assets.gd         material loading for assets/materials/phase4_integration
  encounter_preview.gd          standalone fallback preview (not used by gameplay)
  preview_combat_controller.gd  preview-only CombatController stand-in
  preview_combat_health.gd      preview-only CombatHealth stand-in
  preview_package.gd            preview-only package stand-in
scenes/gameplay/phase4_integration_visual/
  encounter_presentation.tscn   <- gameplay instances this
  encounter_preview.tscn        run on its own to preview
assets/materials/phase4_integration/*.tres   (10 StandardMaterial3D)
tests/phase4_integration_visual_tests.gd
```

## Integrating (gameplay side)

Instance `encounter_presentation.tscn` under the level or encounter root. You
can do it at runtime:

```gdscript
var fx := preload("res://scenes/gameplay/phase4_integration_visual/encounter_presentation.tscn").instantiate()
fx.auto_discover = false                     # optional: bind explicitly
level.add_child(fx)
fx.bind_controller(player.get_node("CombatController"))   # also finds actor + sibling CombatHealth
fx.bind_package(carried_package)             # optional; else auto-discovered
fx.set_route(PackedVector3Array([start, bend, shrine]))
fx.set_destination(shrine, "Moonwell Shrine")
fx.set_quest("Moonpetal Delivery", "Carry the tonic to the shrine.")
# enemies: add them to group "enemies" (auto-registered), or call:
fx.register_enemy(enemy_node)                # kind auto-detected, or pass &"frost_wisp"
# later:
fx.set_quest_state(&"complete")              # available | active | complete | failed | hidden
```

You can also set the NodePath exports instead: `combat_controller_path`,
`player_health_path`, `actor_path` and `package_path`. If `auto_discover` is
left on, the reused adapter searches `current_scene` for the first node that
has a `magic_bolt_fired` signal.

### Signal and method contract (all optional, detected by name)

| Node | Consumed |
| --- | --- |
| CombatController | `magic_bolt_fired(origin, direction)`, `dash_started()`, `dash_finished()`, `shield_changed(active, durability)` (durability 0..1, or 0..100), `target_hit(target, amount)`. Optional polling: `get_bolt_cooldown_remaining()/get_bolt_cooldown()`, `get_dash_cooldown_remaining()/get_dash_cooldown()` |
| CombatHealth (player) | `health_changed(current, maximum)`, `damaged(amount, source_position)` |
| CombatHealth (enemy) | `health_changed(current, maximum)`, `damaged(amount, source_position)`, `died()`. Initial values come from `get_health()`/`get_current_health()` or `current_health`/`health`/`hp`, and from `get_max_health()` or `max_health`/`max_hp` |
| Enemy | A node in group `enemy_group` (default `&"enemies"`) or passed to `register_enemy()`. Its health is the enemy itself, else a child named `CombatHealth`, else any child exposing `damaged`/`health_changed`. Kind comes from meta or a property named `enemy_kind`/`enemy_type`/`kind`, else from the node name (`slime` → forest slime; `wisp`/`frost` → frost wisp), else `default_enemy_kind` |
| Package | Whatever `PackageStatusProbe` detects (temperature, instability, integrity and their `*_changed` signals), plus an optional `damaged(...)` signal. Auto-discovered via `get_carried_package()`, `get_package()` or `carried_package` on the actor or controller |

### Behaviour

* **Enemy visuals.** An existing Phase 4 enemy visual child (any script
  extending `enemy_visual.gd`) is reused. Otherwise a slime or wisp visual is
  instanced as a child named `Phase4Visual`. The layer only frees visuals it
  created itself. Hit and death animations come from the enemy CombatHealth
  through `bind_health`. An enemy without health is driven by `target_hit`.
* **Health bars.** They follow the enemy at a height set per kind. `health_changed`
  sets the value, `damaged` flashes the bar, and `died` fades it out. A
  `health_changed` with a value above 0 after death revives the enemy and its
  visual (this covers respawns).
* **Damage numbers.** The adapter spawns these on `target_hit`. The layer adds
  one for a `damaged` event only if no `target_hit` for that enemy arrived in
  the same frame, so a hit is never counted twice.
* **Defeat.** `enemy_defeated(enemy)` is emitted once, `defeated_count`
  increases, and a burst spawns under Effects.
* **Package warnings.** The banner shows the persistent warning:
  temperature/instability via the probe, integrity at 50% or below for CAUTION
  and 25% or below for CRITICAL. Transient alerts:
  * "Package hit! -N" on an unshielded courier hit.
  * "Shield absorbed the hit" on a shielded hit.
  * "Shield cracking" when durability drops below `low_shield_ratio`.
  * "Shield broken!"
  * "Package damaged! -N" from the package's own `damaged` signal.

  Courier-hit alerts fire even with no package bound unless
  `warn_without_package = false`.
* **Route.** The quest tracker distance and the dimming of passed markers
  update every frame from the actor's position. Within `arrive_radius` the
  tracker reads "Arrived".
* **Freed enemies.** These are pruned automatically, along with their bars.

### Emitted signals (EncounterPresentation)

* `binding_changed(preview_mode)`
* `enemy_registered(enemy, visual)`
* `enemy_unregistered(enemy)`
* `enemy_defeated(enemy)`
* `package_warning_changed(level)`, where level is 0 NONE, 1 CAUTION or 2 CRITICAL

## Standalone preview

Run `scenes/gameplay/phase4_integration_visual/encounter_preview.tscn`. It
builds a colourful clearing with 14 pines in six leaf colours, a courier
stand-in, two slimes and two wisps. It then drives the real presentation scene
through the preview-only stand-ins, which use the same signal names as
gameplay.

Keys: [1] Magic Bolt, [2] Dash, [3] Shield, [4] Take hit, [5] Heat package,
[6] Advance route, [7] Reset, [F] toggle the auto demo.

## Tests

```
godot --headless --path . --script res://tests/phase4_integration_visual_tests.gd
```

The exit code is the number of failed checks. Gameplay nodes are mocked with
runtime GDScript. Covered: materials and scenes, health bar, defeat burst,
standalone boot, combat signal VFX, package hit and shield alerts, enemy
registration, hit and death feedback, damage-number dedupe, revive, kind
detection, health-less enemies, group scan, visual reuse and pruning, package
warning levels and auto-discovery, route, beacon, progress and quest states,
the preview scene, and the auto demo.

## Ownership

These files are the only ones this work owns. It does not edit `village.tscn`,
the Phase 4 visual slice or any gameplay-owned file.
