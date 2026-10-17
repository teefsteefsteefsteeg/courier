# Gameplay ↔ World/UI Integration Contract (Phase 2)

Owner of this document: Gameplay (`gameplay` branch).
Audience: World/UI owner (`world-ui` branch).

When Phase 2 started, the repository had no UI integration contract. Phase 2 therefore
**does not edit World/UI-owned files**: `scenes/levels/*`, `scenes/ui/*`, `scripts/ui/*`,
`scenes/props/*` and `scenes/camera/*`. Everything is demonstrated in an isolated sandbox:

```
res://scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn
```

Run it with:
```
godot --path . res://scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn
```

## 1. What to add to a real level (e.g. the post office hub)

| Add | Scene | Notes |
|---|---|---|
| Services, exactly once per running game | `scenes/gameplay/gameplay_services.tscn` | Contains `QuestManager` + `CourierWallet`. Found via groups `quest_manager` / `courier_wallet`. If it should survive level changes, register it as an **Autoload** (Project Settings → Autoload, name `GameplayServices`). That is a `project.godot` change, so World/UI should decide. |
| Quest board | `scenes/gameplay/world/quest_board.tscn` | `StaticBody3D` on layer 1. It joins group `quest_board` automatically. |
| Package pickup points | `scenes/gameplay/packages/package_pickup.tscn` | Set `package_definition` to a `res://data/packages/*.tres`. It is hidden until a quest needs it. |
| Destination volumes | `scenes/gameplay/world/destination_area.tscn` | Set `destination_id` (Q002 uses `forest_clearing`). It detects physics layer 2 (player). |
| Quest NPCs | existing `scenes/npc/npc.tscn` + child `Node` with `scripts/quests/quest_npc_behaviour.gd` | Set `npc_id` on the NPC. The ids used by the data are `postmaster`, `village_merchant`, `forest_mage` and `village_alchemist`. |
| Gameplay HUD | `scenes/gameplay/ui/gameplay_hud.tscn` | Set `player`. It contains the tracker, package indicator, wallet and toasts. |
| Board window | `scenes/gameplay/ui/quest_board_ui.tscn` | No setup needed. It finds boards and QuestManager by group. |

The player scene already contains `PackageCarrier` (child of `Player`, 2.05 m above the feet).

## 2. Signals World/UI can listen to

### QuestManager (`scripts/quests/quest_manager.gd`, group `quest_manager`, `QuestManager.find(get_tree())`)
| Signal | When |
|---|---|
| `quest_state_changed(quest_id, new_status, old_status)` | Every status change (`QuestState.Status`). |
| `quest_accepted(quest_id)` | Contract accepted. |
| `quest_activated(quest_id)` | First objective progress (ACCEPTED → ACTIVE). |
| `objective_progressed(quest_id, objective_index, progress, required)` | Any objective progress. |
| `objective_completed(quest_id, objective_index)` | Objective finished. |
| `quest_completed(quest_id)` | All objectives done (reward follows in the same frame). |
| `quest_rewarded(quest_id, reward: QuestReward)` | Reward paid. Emitted at most once per quest. |
| `quest_failed(quest_id, reason)` | Quest failed. The package is confiscated automatically. |
| `active_delivery_changed(quest_id)` | The single delivery slot was taken (`quest_id`) or freed (`&""`). |
| `delivery_rejected(quest_id, npc_id, result: DeliveryResult)` | Wrong recipient, not ready, etc. |

### CourierWallet (`scripts/quests/courier_wallet.gd`, group `courier_wallet`)
`gold_changed(new_value, delta)` and `reputation_changed(new_value, delta)`. The properties are `gold` and `reputation`.

### PackageCarrier (`scripts/packages/package_carrier.gd`, `PackageCarrier.find_on(player)`)
`carried_package_changed(package_or_null)`, `package_picked_up(package)`, `package_dropped(package)`,
`package_removed(package, reason)` (reason `&"delivered"` or `&"quest_failed"`) and `pickup_blocked(package, reason_text)`.

### QuestBoard / QuestBoardUI
`QuestBoard.opened(board, interactor)`, `QuestBoardUI.contract_accepted(quest_id)` and `QuestBoardUI.closed`.

### NPC
`NPC.spoke(npc_name, line)` (existing). `QuestNPCBehaviour.delivery_accepted(package)` and `delivery_refused(package, result)`.

## 3. Methods UI may call (read-only queries plus accept)

`QuestManager`:
- Queries: `get_quest_ids()`, `get_definition(id)`, `get_state(id)`, `get_status(id)`,
  `get_available_quests()`, `get_in_progress_quests()`, `get_active_delivery_id()`,
  `get_current_objective(id)`, `can_accept(id) -> AcceptResult`.
- Commands: `accept_quest(id) -> AcceptResult`. Use `QuestManager.accept_result_text(result)` for a display string.

UI must **not** call `notify_*`, `try_deliver`, `grant_reward`, `fail_quest` or `reset_failed_quest`.
Those are gameplay-side commands.

`PackageInstance`: `definition` (`PackageDefinition`: `package_name`, `package_description`, …),
`integrity`, and the signal `integrity_changed(new, old)`.

## 4. Requests for World/UI (not done by Gameplay)

1. **Hide `InteractionPrompt` while a modal UI is open.** Today the "[E] Read Quest Board" prompt
   stays visible under the board window (`scenes/ui/interaction_prompt.tscn`). Suggestion: hide it
   while `PlayerController.input_enabled == false`, or listen to `QuestBoardUI` open/closed.
2. Decide on Autoload versus per-level placement of `gameplay_services.tscn` (see §1).
3. Place the four quest NPCs, the board, the pickups and `forest_clearing` in the real hub, village
   path and forest levels.
4. Optionally restyle the gameplay widgets. They use `scenes/gameplay/ui/gameplay_ui_theme.tres`;
   scripts look nodes up by `%UniqueName`, so layout can change freely as long as those names stay.
5. Screen layout used: wallet top-right, tracker under it, package indicator bottom-left, toasts top
   centre. The DebugHUD (top-left) and InteractionPrompt (bottom centre) are unchanged.

## 5. Input
Phase 2 added one action to `project.godot`: `drop_package` = **G**. It is handled by `PackageCarrier`
and ignored while `PlayerController.input_enabled` is false. The board window closes on `ui_cancel` (Esc) or `interact` (E).
