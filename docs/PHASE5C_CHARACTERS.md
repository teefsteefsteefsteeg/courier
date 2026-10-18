# Phase 5C: character & animation integration

Branch `phase5c-characters`, worktree `D:\courier-phase5c-characters`, based on
`phase5b-environment` @ `77a6ba3`. Press F5 (main scene `village.tscn`): the courier is an
animated KayKit Ranger and every NPC is a KayKit character.

Before/after (left/right, same camera, HUD and labels hidden):
`docs/validation/phase5c/*.png`. Regenerate with
`godot --path . --script res://tests/capture_phase5c_screenshots.gd -- <dir>`.

## Asset audit (KayKit Adventurers 2.0 FREE)

- Location: the pack is not in `D:\MysticCourierAssets\Characters\` (that folder does not
  exist); it was found as untracked files in `D:\courier-phase5a-assets\characters\` plus
  `KayKit_Adventurers_2.0_FREE.zip`. Those were read, not modified.
- License: CC0 1.0 (Kay Lousberg, www.kaylousberg.com); attribution optional.
- Characters (GLB, FBX, FBX for Unity): Barbarian, Knight, Mage, Ranger, Rogue, Rogue_Hooded.
  All share the 23-bone `Rig_Medium` skeleton (`handslot.l/.r` bones for props). Small
  colour-atlas textures (about 14 KB PNGs) per character.
- Animations (GLB + FBX), Rig_Medium only:
  - General: Death_A, Death_A_Pose, Death_B, Death_B_Pose, Hit_A, Hit_B, Idle_A, Idle_B,
    Interact, PickUp, Spawn_Air, Spawn_Ground, T-Pose, Throw, Use_Item
  - MovementBasic: Jump_Full_Long, Jump_Full_Short, Jump_Idle, Jump_Land, Jump_Start,
    Running_A, Running_B, T-Pose, Walking_A, Walking_B, Walking_C
  - Every clip is flagged play-once in the files; looping is set at load for idle/walk/run.
- **Missing in the FREE pack: attack and dash clips** (the pack links to a separate paid
  animation set). No creature/enemy models.
- Props: weapons, shields, staff, wand, spellbooks, mugs, quiver, arrows (glTF + shared textures).

## Implementation

- `scripts/characters/kaykit_character.gd` (`KayKitCharacter`): instances a model under the
  existing `Visual` node, rotates it 180 deg (glTF +Z forward to gameplay -Z), scales 0.85,
  adds an AnimationPlayer with the two shared libraries (cached once), optional prop on
  `handslot.r`, and maps actions to clips with fallbacks:

  | Action | Clip | Note |
  |---|---|---|
  | idle / idle_alt | Idle_A / Idle_B | NPCs drift to Idle_B every 6-12 s |
  | walk / run | Walking_A / Running_A | from MovementComponent state |
  | airborne | Jump_Idle | |
  | attack (magic bolt) | **Throw** | fallback: no attack clip in pack |
  | dash | **Running_B** at 1.8x | fallback: no dash clip in pack |
  | hit | Hit_A | |
  | revive (after knockout) | Spawn_Ground | gameplay respawns instantly, so the death pose is never on screen |
  | death | Death_A | mapped, held; only visible if respawn is ever delayed |
  | interact / pickup | Interact / PickUp | player interacting, NPC talking, parcel pick-up |

- `scripts/characters/player_animator.gd`: listens to existing signals only (movement
  `state_changed`, combat `magic_bolt_fired`/`dash_started`, health `damaged`/`died`/
  `health_changed`, interaction, carrier `package_picked_up`). No gameplay code changed.
- `scripts/characters/npc_animator.gd`: Interact gesture on the NPC's `spoke` signal; NPC.gd's
  existing turn-to-face logic rotates `Visual`, so models face the courier when talking.
- Scenes: `player.tscn`, `npc.tscn` and the five `npc/characters/*.tscn` keep every node; the
  primitive meshes are `visible = false`. Collision capsule (r 0.35, h 1.6), PackageCarrier
  height (2.05 m), interaction areas, speech labels, quest behaviours and names are unchanged.

| Character | Model | Prop |
|---|---|---|
| Courier (player) | Ranger | (packages carried overhead as before) |
| Postmaster Bram | Barbarian | mug |
| Merchant Mira | Rogue | none |
| Alchemist Corvin | Rogue_Hooded | open spellbook |
| Mage Elowen | Mage | staff |
| Villager Pip | Knight (0.85 child scale kept) | one-handed sword |

## Enemies

Not replaced. The pack contains only humanoid adventurers; per the brief, the Forest Slime and
Frost Wisp keep their Phase 4 visuals.

## Validation

Automated (headless): import clean; all 14 suites pass (Phase 1 to 5C), including the new
`tests/phase5c_character_tests.gd` (73 checks): distinct model per character, primitives
hidden, 23-bone skinned models, facing, sensible heights, props attached, every action resolves
to an existing clip, attack/dash fallbacks, idle/walk/run loop, live idle-walk-run-idle from
input, model turns with the facing component, bolt/dash/hit/knockout-revive animations from real
combat calls, unchanged capsule, NPC talk gesture and turn-to-face.

Rendered (GPU window, scripted, not a human playtest): main scene ran 600 frames with no errors;
comparison screenshots above; frame time unchanged from Phase 5B (about 6.7 to 7.6 ms at 1600x900
here).

## Known issues

- `world_ui_tests` "prompt panel also stands down while a modal is open" is intermittent on both
  Phase 5B (1 of 6 runs) and 5C (1 of 10); timing-sensitive 2-frame wait, not caused by 5C.
- Attack and dash use fallback clips (Throw, fast Running_B); a proper cast/dash needs the paid
  KayKit animation pack or custom clips.
- Merchant Mira (Rogue) and Alchemist Corvin (Rogue_Hooded) share the green outfit palette;
  Corvin is distinguished by hood, mask and spellbook.
- Walk/run playback speed is not synced to movement speed; a little foot sliding at run speed.
- Not yet playtested by a human.
