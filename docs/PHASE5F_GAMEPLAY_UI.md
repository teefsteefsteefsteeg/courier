# Phase 5F: gameplay, NPC interaction, quest and HUD feedback

Branch `phase5f-gameplay-ui`, worktree `D:\courier-phase5f-gameplay-ui`, based on `38be579`
(Phase 5E village overhaul). Scope: player-facing feedback for NPCs, quests, wallet/reputation and the
HUD. Village terrain, buildings, environmental dressing, visual assets, NPC IDs, quest data, routes,
collision and the Phase 5E scene layout are untouched (no `.tres` quest/package data and no
`village.tscn` changes).

## What changed

### NPC quest markers (`scripts/quests/quest_npc_behaviour.gd`)
Every NPC with a `QuestBehaviour` child gets a floating billboard `QuestMarker` (Label3D, added at
runtime, so no NPC scene edits) about 2.85 m above its origin, with a gentle bob:

| Marker | Shown when |
|---|---|
| `!` gold | an in-progress quest's current objective is to talk to this NPC (Bram's Q1 briefing) |
| `?` bright gold | the courier carries this NPC's package and a handover would succeed now |
| `?` dim grey | a delivery for this NPC is under way but not ready (not carried, dropped, or the route is not finished) |
| `✓` green | about 2.5 s after a successful handover |

Markers re-evaluate every 0.15 s and immediately after talk/delivery events. The pure rule is
`QuestNPCBehaviour.marker_for(manager, npc_id, carried_package)`. Villager Pip (no quest behaviour)
has no marker.

### Context interaction prompt
- `Interactable.get_prompt_text_for(interactor)` asks the owner for `get_interaction_prompt(interactor)`
  and falls back to the Phase 1 `get_prompt_text()`.
- `NPC.get_interaction_prompt()` asks child behaviours for `get_prompt_verb()`. The quest behaviour
  returns `Deliver <package> to` only when `QuestManager.check_delivery()` (new, side-effect free)
  says the handover would succeed, so the prompt reads `[E] Deliver Ordinary Parcel to Merchant Mira`,
  highlighted gold. Every other case keeps the old text (`[E] Talk to ...`, `[E] Read Courier Guild Board`).
- `InteractionPrompt` re-checks the text each frame while something is focused, so it updates when a
  package is picked up or a quest advances without a focus change.

### Delivery and quest feedback
- `QuestNotification` toasts now have a kind (`info`, `success`, `warning`, `rank`) that tints the
  text; `push_message(text)` still works (defaults to `info`), and `history` is unchanged. A new
  `kind_history` mirrors it.
- Wrong recipient: `Wrong recipient. Check the address: Merchant Mira, Village Market.`
- New not-ready toast: `Not yet: Carry the egg to the Forest Clearing` (the current objective).
- Courier rank-ups: `Rank up: Apprentice Courier!`, posted deferred, so it follows the delivery toast.
- The quest board feedback line adds the contract's first step after accepting.

### Quest tracker (`scripts/gameplay_ui/quest_tracker.gd`)
- The header reads the stage and step: `CONTRACT ACCEPTED · STEP 1/3`, `ACTIVE DELIVERY · STEP 2/3`,
  `READY TO DELIVER · STEP 3/3` (carrying the package on the deliver step) or `PACKAGE DROPPED · STEP 3/3`
  (past pickup without the package). GameplayHUD binds the player's carrier.
- New reward line: `Reward: 50 Gold, 5 Reputation`.
- The objective line flashes gold for 1.2 s when it changes.
- Title, objective (`▸ ...`) and destination (`To: ...`) keep their Phase 2 format.

### Wallet and reputation
- `CourierWallet` maps reputation to a courier rank: Novice (0), Apprentice (15), Journeyman (35),
  Trusted (75), Renowned (150), and emits `rank_changed`. With the shipped contracts, Q1 leaves the
  courier a Novice (5), Q2 makes them an Apprentice (25) and Q3 a Journeyman (40).
- `WalletDisplay` keeps `Gold: N` / `Reputation: N`. It adds a rank line (`Novice Courier  (10 to next)`),
  a thin progress bar to the next rank, and a payout delta (`+50 g  +5 rep`) that fades after 3 s.
  The panel is about 30 px taller, and the minimap still sits under it (GameplayHUD lays it out from
  the wallet height).
- The onboarding hint mentions the `!` and `?` markers.

### Second pass: dialogue, retry, minimap and modal fixes
Found by driving the real village with scripted input (board, journal, map and dialogue in every
combination) and a failed potion run.

- **Giver dialogue** (`QuestNPCBehaviour.get_giver_line`). When no talk, delivery or recipient
  line applies, the NPC who gave a contract (Bram) now says where things stand, all generated from
  quest data (exported, `%s`-templated lines; no `.tres` edits):
  crate still to collect (`The Unstable Potion Crate is ready for you here. It goes to Alchemist
  Corvin, Village Alchemy Shop.`), en route, package dropped, a failed contract to retry, and
  `Every contract delivered! Not bad at all for a Journeyman Courier.` once the board is done.
  Talking to the giver while carrying their package gives the en-route reminder instead of the
  wrong-recipient refusal (and no "Wrong recipient" toast).
- **Not-ready line** names the missing step: `That's for me? Finish the route first, courier:
  carry the egg to the Forest Clearing.`
- **Bug: failed contracts were soft-locked.** In the village only Q2 was put back on the board (by
  the Phase 4 integration); a failed Q3 stayed FAILED with its button hidden. The board now shows
  `Retry` (status `Failed: <reason>`) and `QuestManager.retry_quest()` / `can_retry()` reset and
  re-accept it in one step, respecting the one-delivery rule. The journal's failed entry says the
  contract can be taken again.
- **Bug: the village minimap was not modal.** `minimap_controller.gd` (the map GameplayHUD
  actually uses) opened the expanded map over the board and journal, let the journal open over
  it, kept the courier walking underneath, ignored Escape, and drew the compact map above the open
  journal. The expanded map now refuses to open over another window, joins `ui_modal` while open,
  pauses the courier's input (restored deferred on close), closes on M or Escape, shows a close
  hint, and the whole layer hides while the journal is open.
- **Minimap content.** No node was in the `npcs` group, so the map showed no NPCs; `NPC` now joins
  it and markers carry the NPC's display name. The objective marker followed only Q2 (via the
  Phase 4 integration); `QuestWaypoint` resolves the current objective of any contract to its NPC,
  source pickup, destination or dropped package, with a matching label. The integration still wins
  where it has a target, so its board/forest routing and the Phase 4 HUD tests are unchanged.
  `PackagePickup` and `DestinationArea` join `package_pickups` / `destination_areas` for lookup.
- The dialogue box hides with the journal and comes back when it closes.

## Tests
New `tests/phase5f_gameplay_ui_tests.gd` (real village plus standalone unit checks):
- Rank thresholds, progress clamping, titles, and `rank_changed` up and down on a standalone wallet.
- The prompt fallback without an owner; no marker without a QuestManager.
- A marker on each of the four quest NPCs, hidden at start, billboarded above the head; none on Pip.
- Default prompts unchanged (Bram with empty hands, the quest board).
- Q1: Bram `!` -> clears after the briefing; Mira dim `?` -> bright `?` with the parcel; tracker
  header through CONTRACT ACCEPTED / ACTIVE DELIVERY / READY TO DELIVER / PACKAGE DROPPED, reward line,
  objective flash; Corvin keeps the talk prompt and posts the address warning; context prompt and
  colour at Mira; payout delta, rank line and bar; the `✓` and the delta both expire.
- Q2: dim `?` and a `Not yet:` warning before the clearing; bright `?` inside it; the rank-up toast
  after the delivery toast; the wallet shows Apprentice.
- Q3: the board feedback names the first step; the tracker header for a two-step contract.
- The tracker and taller wallet stay on screen, apart, and above the minimap.
- Second pass: Elowen's not-ready line names the step; Bram's pickup / en-route / dropped / failed
  / all-done lines and no wrong-recipient toast from the giver; map NPC labels; the map objective
  through Q3 pickup, delivery and a dropped crate; Q3 failure -> journal hint -> board `Retry` with
  the reason -> crate back on the counter -> redelivered; the expanded map as a modal (pauses and
  restores input, hides the prompt, blocks the journal, refused over the board, Escape closes);
  the journal hiding and restoring the map and dialogue layers.

Existing suites were not edited. Compatibility points they rely on are kept: wallet and tracker label
text, `[E] Talk to Postmaster Bram`, `[E] Read Courier Guild Board`, the `Wrong recipient`,
`Contract accepted:`, `Delivery complete:` and `Delivery failed:` toast prefixes, and
`push_message(text)` with one argument.

## Validation

Run headless with Godot 4.7.2 (`D:\godot\Godot_v4.7.2-stable_win64_console.exe`) from the project root
on 2026-10-18, rerun after the second pass with the same results: `--import` clean, `--quit-after 180` boot of the village clean (no errors or warnings).

| Suite | Result |
|---|---|
| phase5f_gameplay_ui_tests | 125 passed, 0 failed (84 after the first pass) |
| phase1_tests | 52 / 0 |
| phase2_tests | 105 / 0 |
| phase3_tests | 79 / 0 |
| phase3_demo_tests | 14 / 0 |
| phase3_visual_tests | 123 checks, 0 failures |
| phase4_gameplay_tests | 183 / 0 |
| phase4_visual_tests | 167 / 0 |
| phase4_integration_visual_tests | 135 / 0 |
| phase4_hud_polish_tests | 170 / 0 |
| phase5a_asset_tests | 198 / 0 |
| phase5b_environment_tests | 43 / 0 |
| phase5c_character_tests | 73 / 0 |
| phase5d_megakit_tests | 64 / 0 |
| phase5e_village_tests | 68 / 0 |
| village_quest_tests | 95 / 0 |
| world_ui_tests | 127 / 0 (see below) |

`world_ui_tests` first failed one check ("prompt panel also stands down while a modal is open").
The prompt only noticed modals in `_process`, and the test waits on physics frames, which can run
several times before the next idle frame; the extra per-frame prompt work made that window easier
to hit. `InteractionPrompt` now also syncs the modal state on physics ticks; three reruns passed.

Run a suite with `godot --headless --path . --script res://tests/<suite>.gd`; the exit code is its
number of failed checks.

## Known limitations
- The built-in default font has no `✓` or `▸`; the project bundles no font, so both render through
  Godot's system font fallback (on by default; Segoe UI Symbol on Windows). The board's
  `Delivered ✓` and the Phase 2 tracker's `▸` already depend on the same fallback.
- Markers draw without depth test, like the existing speech bubbles, so they show through walls
  (Bram's `!` is visible through the post office walls).
- The Phase 5C/5D screenshot scripts hide every Label3D at load; markers re-show themselves on
  their next refresh, so new captures will include them.
- Rank thresholds are tuned to the three shipped contracts; the ranks gate nothing yet.
- Not playtested by a human.
