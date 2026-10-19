# Weapon elemental VFX (Phase 8 rework)

Request (2026-10-19): enhanced weapons all looked alike (one shared glow per level, only the
placement differed). Now every weapon class has its own element and every level +1..+5 its
own composition; +5 weapons also project their element outward through an ultimate on [C].

## Audit (before)
- `EnhancementGlow` built one recipe per level (+1 silver spark, +2 nature, +3 water,
  +4 lightning, +5 legendary) for every weapon; only `SPAN` (where along the weapon) differed.
- `AttackEffects` added the same per-level trails/impacts to every melee weapon; arrows and
  bolts had none. There was no ultimate system (planned keys Z / X / C, milestone 7).

## Passive (`scripts/vfx/enhancement_glow.gd`, on the held model; no damage)
| Level | Sword (fire / blade) | Axe (earth) | Bow (wind / lightning) | Staff (arcane / water) |
|---|---|---|---|---|
| +1 | Silver Sparks: spark bursts and a glint on the blade | Iron Sparks: spark bursts, falling metal glints | Breeze: drifting wind streaks | Motes: floating violet motes |
| +2 | Blade Trails: world-space streaks that line the edge and trail a swing, edge glow | Stone Dust: falling pebbles, dust puffs | Air Trails: swirls on the grip and lower limb, breeze | Rune Circles: two counter-rotating rune rings at the tip |
| +3 | Ember Edge: embers running grip-to-tip, rising embers, warm light | Earth Runes: a pulsing amber rune ring round the head, pebbles | Wind Spiral: wind streaks orbiting the bow, swirl | Tidal Orbit: water drops orbiting the tip, swirl, bubbles |
| +4 | Wrapped Flames: flames on alternate sides of the blade, embers | Rockbound: twin rune rings, orbiting rocks, rubble bursts | Charged Arcs: electric ring arcs, arc flashes, sparks | Arcane Crystals: orbiting crystals, energy streaming up the shaft, charge ring |
| +5 | Inferno Blade: four large flames, animated fire stream (8x8 flipbook), ember storm, heat flashes | Earthshaker: orbiting boulders, magma, rune ring, dust-ring bursts | Thunderstorm: electric aura, arcs, lightning strike on the lower limb, wind spiral | Arcane Storm: big twin rune rings, four crystals, warp pulses, crackle, streams |

- Shields keep the generic tiers. Names per class: `EnhancementGlow.tier_name(type, level)`.
- Placement: sword along the blade, axe on its crescent head, staff at the top; the bow's
  effects stay on the grip and lower limb (`BOW_TOP`, measured in the world because which
  end is down depends on the hold) and draw over the body, so they show from the gameplay
  camera without covering the courier's face.
- Budget per weapon: at most 6 flipbooks and 60 particles (measured 0-5 and 0-34).

## Active (`scripts/vfx/attack_effects.gd`, cosmetic; damage unchanged)
- Sword: arc in the element colour; +2 icy streaks, +3 ember bursts, +4 a flame at the front
  of the cut, +5 a fire arc, heat flash and fire blast on hit.
- Axe: chop; hits +1 iron sparks, +2 dust, +3 rune flash; the chop's ground point (hit or miss)
  +4 dust ring and rubble, +5 a small quake blast.
- Bow: arrows carry +1/+2 a breeze, +3 a wind spiral, +4/+5 electric arcs; impacts +4 arcs,
  +5 a lightning strike (once per arrow).
- Staff: bolts carry +1 motes, +2 a rune ring at launch, +3 droplets, +4/+5 crystal streams;
  impacts +3 splash, +4 charge burst, +5 warp and light burst.
- `CombatController.projectile_launched(projectile, kind)` lets effects dress arrows and bolts.

## Ultimates (`scripts/combat/weapon_ultimates.gd`, `WeaponUltimates` in GameplayServices)
[C] (`weapon_ultimate`) with a +5 weapon in hand; normal attacks never trigger it. Damage =
the weapon's own (enhanced) damage x a factor, through `CombatHealth`, reported as
`CombatController.target_hit` and `WeaponUltimates.skill_hit`.

| Weapon | Skill | Behaviour | Cooldown |
|---|---|---|---|
| Sword | Flame Slash | a fire wave (Binbun wave projectile + flames + fire stream) travels 12 m; hits each enemy in its 3 m band once; nothing behind or beside; walls stop it; 2.2x melee damage | 8 s |
| Axe | Earthquake | a shockwave expands to 7 m from the chop point (glowing cracks, dust rings, rubble, flying rocks, quake blast); each enemy once, 1.8x; staggers 1.2 s (`Enemy.stagger`, `staggerable` off for bosses) | 10 s |
| Bow | Thunder Arrow | a charged arrow (2x); where it hits, lightning strikes and chains to up to 3 other enemies within 7 m, nearest first, each once (1.3x) | 9 s |
| Staff | Arcane Storm | over the nearest enemy within 10 m (or 6 m ahead): rune circle and storm vortex (the bossEffect tornado), 6 bolts falling 0.38 s apart, each hitting each enemy within 1.6 m once (1.1x) | 12 s |

- MP: the game has no MP yet (milestone 6). The storm's 30 MP is charged from a node in group
  `courier_mana` with `spend(amount) -> bool` when one exists (refusal blocks the skill);
  until then it has only its cooldown. No fake MP is shown.
- HUD: the weapon bar shows "[C] Flame Slash · ready / 6 s" with a +5 weapon; the key guide
  is unchanged.

## Assets
- New Gigapack sheets (`tools/prep_enhancement_vfx.py`): dust_ring, dust_puff, rubble,
  quake_blast, charge, warp, arc_ring, slash_flash, light_burst.
- Binbun Magic Projectiles (CC0), vendored by `tools/vendor_binbun_projectiles.py` to
  `assets/vfx/BinbunVFX_Magic/` (wave: Flame Slash; basic: storm bolts).
- Brackeys VFX bundle fire flipbook (CC0) and the bossEffect tornado, vendored by
  `tools/vendor_boss_vfx.py` to `assets/vfx/boss/` and `assets/vfx/boss_tornado/`.
- Procedural sprites in `EnhancementGlow._texture`: dot, leaf, streak, pebble, rune.

## Validation
- `tests/weapon_elemental_vfx_tests.gd` (94): 24 weapon/level combinations (own elements,
  no element shared between classes at a level, every level different, animated, budget),
  passive harmless, survives teleport and region change, per-weapon attack effects, normal
  damage unchanged, every ultimate's hit rules, cooldowns, +4 refused, MP refusal, real C
  key, HUD line, the Earthquake in Wyrmfall. `phase8_weapon_vfx_tests` and
  `phase7_enhancement_tests` updated to the sword's new elements.
- Rendered (`tests/capture_weapon_elemental_vfx.gd`, real game, GPU) ->
  `docs/validation/weapon-elemental-vfx/`: `passive_<weapon>.png` (+0..+5 close-ups, 24
  combinations), `gameplay_<weapon>_plus5.png`, `moving_<weapon>_plus5.png`,
  `attack_<weapon>_plus3/plus5.png`, `ultimate_<weapon>_1..3.png` (frames of the wave
  travelling, the quake expanding, the lightning chaining, the storm striking),
  `switch_1_pickaxe.png` / `switch_2_q_back_to_sword_plus5.png`.
- Known: +1 and +2 are deliberately restrained; the axe's +1 sparks are small from the
  default camera. No human playtest yet.
