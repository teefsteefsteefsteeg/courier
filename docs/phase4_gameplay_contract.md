# Phase 4 Gameplay Contract (combat)

Owner: Phase 4 gameplay worker. This is the public interface the Phase 4 visual worker
(and later phases) can rely on. Everything not listed here is internal and may change.

## Controls

| Action              | Key   | Behaviour                                                   |
|---------------------|-------|-------------------------------------------------------------|
| `combat_magic_bolt` | Space | Fire a Magic Bolt along the aim direction                   |
| `combat_dash`       | Shift | Dash along the aim direction                                |
| `package_shield`    | Q     | Toggle the Package Shield (only while carrying a package)   |

Existing bindings are unchanged. Note: `run` is also bound to Shift, so pressing Shift
starts a dash and holding it keeps running afterwards. That overlap is intentional per the
Phase 4 spec. Rebind `combat_dash` if it should be separate.

Aim direction = current movement input; if there is none, the courier's visual facing.

## Scene layout

```
Player (PlayerController, scenes/player/player.tscn)
└── Combat (CombatController)
    └── Health (CombatHealth)
```

Lookups: `CombatController.find_on(player)` and `CombatHealth.find_on(any_body)` (searches the
node, its children and its grandchildren).

Enemy scenes (`scenes/gameplay/combat/`): `forest_slime.tscn` (ForestSlime), `frost_wisp.tscn`
(FrostWisp). Each is a `CharacterBody3D` with a `Health` (CombatHealth) child and a `Visual`
node holding placeholder meshes that the visual worker can replace. Projectile scenes:
`magic_bolt.tscn` and `frost_shard.tscn` (root = CombatProjectile). If the root has no
children, it builds a glowing placeholder sphere. Adding any child node replaces it.

Sandbox: `scenes/gameplay/combat/combat_sandbox.tscn` (script `scripts/combat/combat_sandbox.gd`).
It depends only on combat, player and camera scenes.

## Physics layers

| Bit | Value | Use                                     |
|-----|-------|-----------------------------------------|
| 1   | 1     | world (walls, floor). Blocks projectiles |
| 2   | 2     | player                                  |
| 5   | 16    | enemies (`CombatController.ENEMY_LAYER`) |

Magic Bolts hit world + enemies (mask 17). Frost Shards hit world + player (mask 3).
Enemies collide only with the world, so they never push the courier or each other.

## CombatHealth (`scripts/combat/combat_health.gd`)

Signals
- `health_changed(current: float, maximum: float)`: the arguments are (current, max). Emitted on damage, heal and reset.
- `damaged(amount: float, source_position: Vector3)`: emitted after health actually drops. `amount` is the damage that got through.
- `died()`: emitted once. `reset()` re-arms it.
- `damage_blocked(amount: float, source_position: Vector3)`: emitted when damage is fully negated (invulnerable, dash, shield).
- `healed(amount: float)`

Methods
- `apply_damage(amount: float, source_position := Vector3.ZERO) -> bool`: returns true only if health dropped.
- `heal(amount) -> float`, `reset()`, `get_health()`, `get_max_health()`, `get_health_ratio()`, `is_dead()`
- Properties: `max_health`, `invulnerable`, `damage_interceptor` (Callable), `last_damage_taken`.

## CombatController (`scripts/combat/combat_controller.gd`)

Signals
- `magic_bolt_fired(origin: Vector3, direction: Vector3)`
- `dash_started()`, `dash_finished()`
- `shield_changed(active: bool, durability: float)`: emitted on raise, lower and break, and on every durability change (absorb or regen).
- `target_hit(target: Node, amount: float)`: a Magic Bolt damaged `target` (the body that was hit).
- `shield_broken()`
- `ability_blocked(ability: StringName, reason: StringName)`: `ability` is one of `magic_bolt`, `dash`, `package_shield`. `reason` is one of `cooldown`, `dashing`, `dead`, `no_body`, `no_package`, `shield_depleted`.

Methods
- `try_magic_bolt(direction := Vector3.ZERO) -> bool`
- `try_dash(direction := Vector3.ZERO) -> bool`
- `set_package_shield_enabled(enabled: bool) -> bool`: returns whether the shield ends up in the requested state.
- `toggle_package_shield() -> bool`
- Queries: `is_dashing()`, `is_shield_active()`, `get_shield_durability()`, `is_carrying_package()`, `get_magic_bolt_cooldown_remaining()`, `is_magic_bolt_ready()`, `get_dash_cooldown_remaining()`, `get_dash_direction()`, `get_aim_direction()`, `get_carrier()`
- `health: CombatHealth`. `advance(delta)` steps the timers. It runs each physics frame while `simulate` is true.

Default tuning: bolt 20 damage, 0.45 s cooldown, 18 m/s, 18 m range. Dash 16 m/s for 0.2 s
(3.2 m) with a 0.9 s cooldown counted from the dash start. Shield 60 durability, raise
threshold 15, regen 8/s after a 2 s delay.

### Damage rules (deterministic, in this order)

1. **Dash:** while dashing, all damage is negated (`damage_blocked`). Shield durability is not used.
2. **Package Shield:** only while raised. It can only be raised while a package is carried
   and durability is at least 15. It absorbs `min(damage, durability)`. The rest reaches health.
   When durability reaches 0, the shield breaks: `shield_changed(false, 0)` then
   `shield_broken`. Dropping, delivering or losing the package lowers it immediately.
   Durability regenerates only while lowered, and only after the regen delay.
3. **Package impact:** damage that reaches health while carrying applies
   `damage × 0.25` impact to the carried package. Absorbed damage never touches the package.
4. **Death:** the shield is lowered, any dash ends, and all abilities refuse with `dead`
   until `health.reset()`.

Dashing while carrying moves fast, so it raises instability on potion crates through the
existing Phase 3 speed mechanic.

## Enemy (`scripts/enemies/enemy.gd`), ForestSlime, FrostWisp

Shared
- `state: Enemy.State`, one of `IDLE`, `CHASE`, `WINDUP`, `RECOVER`, `RETREAT`, `DEAD`. `get_state_name()` returns it as a string.
- Signals: `state_changed(new_state, old_state)`, `attacked(target: Node3D, landed: bool)`, and `defeated(enemy)`, emitted once before the body is freed (`death_free_delay`, 0.6 s by default).
- `health: CombatHealth`, `target` (optional: by default the first node in group `combat_player`), and `provoked`. Any damage provokes an enemy, so it engages from any distance.
- `advance(delta)` runs the AI. It is called each physics frame while `simulate` is true.

ForestSlime (40 HP): chases within 8 m. Within 1.2 m it enters `WINDUP` for 0.35 s (the
tell), then hits for 10 if the target is still within 1.5 m. After that it enters
`RECOVER` for 1 s.

FrostWisp (30 HP, hovers, no gravity): engages within 11 m and holds about 6 m from the
target. Closer than 3.5 m, it enters `RETREAT`. Within 9 m and off cooldown, it enters
`WINDUP` for 0.6 s and emits `attack_telegraphed(aim_position)`, which locks the aim. It
then fires a Frost Shard for 12 damage (`shard_fired(origin, direction)`), with a 2.2 s
cooldown. Moving during the tell dodges the shard.

## Tests

```
godot --headless --path . --import          # registers the new class_names
godot --headless --path . --script res://tests/phase4_gameplay_tests.gd
godot --headless --path . --script res://tests/phase3_tests.gd   # regression
godot --headless --path . --script res://tests/phase2_tests.gd   # regression
```

The exit code is the number of failed checks. AI and abilities are stepped synchronously
with a fixed 1/60 s step. Only projectile flight waits on physics frames.
