# Phase 5F: courier status HUD redesign

Branch `phase5f-integrated`. The Phase 4 combat panel (bottom-left: four flat label/bar rows) is
now a compact fantasy-RPG status panel in the top-left corner. It is the same `CombatHUD`
(`scripts/phase4_visual/combat_hud.gd`, layer 6) with the same API, so every push from the
combat visual adapter and the showcase preview still works.

Screenshots: `docs/validation/phase5f/status_hud/`. `before_after_panel.png` puts the old and new
panels side by side. There are in-game captures at 1600x900, 1280x720 and a phone's 19.5:9
landscape (1560x720 window, logical 1950x900), covering full health, a hit, low health, a rank-up
and an active quest tracker. Regenerate with
`godot --path . --resolution <WxH> --script res://tests/capture_status_hud_screenshots.gd -- <dir>`.

## Look
- **Panel:** dark charcoal-brown, a 1 px antique-gold border, 10 px corners and a soft drop
  shadow (`StyleBoxFlat`).
- **Portrait:** the courier's own KayKit Ranger, rendered to `assets/ui/hud/courier_portrait.png`
  by `tools/render_courier_portrait.gd` (GPU window) and clipped to a circle by
  `assets/shaders/circle_mask.gdshader`, inside a thin gold ring.
- **Level badge:** a small gold-rimmed disc on the portrait's lower right showing the courier
  rank. It pulses on a rank-up.
- **Name:** the courier's rank title in warm gold, with a fading gold divider under it.
- **Bars:** each sits on a dark track with a thin dark-gold edge, has a vertical
  `GradientTexture2D` fill (`StyleBoxTexture`) and a soft top highlight, with the value text
  drawn over it.
  - Ruby health, 20 px.
  - Sapphire shield, 14 px.
  - Warm-gold EXP, 6 px.
- **Chips:** small Bolt / Dash readiness labels over 3 px cooldown bars, and "Rep 17 / 35" on
  the right.

## What the bars show
The game has no mana, experience or level systems. The brief asked to keep gameplay unchanged,
so the HUD binds to the closest existing systems:

| Brief | Bound to | Source |
|---|---|---|
| HP | courier health | `CombatHealth` via the combat visual adapter (`set_health`) |
| MP | Package Shield energy (the only spendable, regenerating resource): drained by absorbed hits, regenerates, dimmed while the shield is down | `set_shield_state` (adapter) and `CombatController` (found by group) for the true maximum |
| EXP | reputation progress to the next courier rank | `CourierWallet.get_rank_progress()`, `reputation_changed`, `rank_changed` |
| Level | courier rank (1 Novice to 5 Renowned) | `CourierWallet.get_rank()` |
| Name | rank title ("Novice Courier"); `display_name` export overrides | `CourierWallet.get_rank_title()` |

Fix included: raw shield durability above 1 used to be read as a percentage, so a 60-point
shield at full showed 60% and the Wooden Shield's 85 showed 85%. It is now divided by the
courier's real `shield_max_durability`. The standalone preview, which has no controller, keeps
the old percentage reading.

## Animation
The bars always show the exact value, and existing tests read them. Changes animate on top:
- **Damage** leaves a pale chip that holds briefly, then drains to the new value; bigger chips
  drain faster. The fill flashes lighter.
- **Healing** flashes the restored segment, then fades.
- **Shield** loss drains the same way.
- **Reputation** slides the EXP bar.
- **Rank-up** pulses the badge and brightens the number.
- **Low health** (25% or less) makes the health fill pulse gently.

## Layout
The panel is anchored top-left with a 16 px margin and sized by its containers. It scales
between 0.72 and 1.0 with the logical viewport height, so it is full size from 820 px up.
`GameplayHUD` now places the quest tracker and the onboarding text below the panel, and keeps the
WASD guide in the bottom-left corner. The toasts and delivery banner are centred, so they never
reach the panel. Long titles are clipped, so the panel keeps its width.

## Tests
- `tests/status_hud_tests.gd` (41 checks) runs in the village:
  - Health text and bar, the damage chip and its drain, the heal flash and its fade, low health.
  - Shield ratio against the real maximum, and the 50% and Broken states.
  - Rank 1 to 2 with title, badge, reputation text, EXP slide and badge pulse; a stable width.
  - Bolt and Dash chips.
  - At 1600x900, 1366x768, 1280x720 and 1950x900: the panel sits in the corner, the tracker is
    below it, nothing overlaps (tracker, wallet, minimap, journal hint, toasts, quick bar, WASD
    guide), every label stays inside the panel, and the scale stays in range.
- `tests/phase4_visual_tests.gd`: the anchor check now expects top-left.
- Every other suite passes unchanged, including the Phase 4 checks on label texts
  ("HP 80 / 100", "Bolt: Ready", "Shield: 75%", ...) and HUD overlap at three resolutions.

## Known limitations
- The portrait is a static render; it doesn't change with equipment or animate.
- In-world UI below the panel (tracker, toasts) is unchanged in style. The panel uses the warm
  charcoal and gold brief, while the older panels keep the purple-navy theme.
- There is still no real mana or experience system; if one is added, rebind the sapphire and
  gold bars.
