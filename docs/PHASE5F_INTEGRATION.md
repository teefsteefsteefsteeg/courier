# Phase 5F integration

Branch `phase5f-integrated`, worktree `D:\courier-phase5f-integrated`, based on `38be579`
(Phase 5E), which is the merge base of both Phase 5F branches.

| Merged | Head | Content |
|---|---|---|
| `phase5f-building-visual` | `c12261d` | Distinct MegaKit village buildings (`4743d7c`); the Willowmere Armory location with weapon displays and Weaponsmith Brenna (`c12261d`) |
| `phase5f-gameplay-ui` | `f156aca` | NPC markers, context prompts, HUD feedback; giver dialogue, contract retry, modal minimap; pixel-art input prompts and WASD guide; dash animation fix; Armory shop, inventory, equipment and save game |

Both merges applied without textual conflicts; `ASSET_MANIFEST.md` keeps every Phase 5F section.
The branches touch different files apart from the manifest. `village.tscn` is changed by the
visual branch only (it adds the Armory); neither branch changes `project.godot`.

## Integration changes
- **Shop hooked to the Armory.** The visual Armory (`scripts/world/armory.gd`) has
  Weaponsmith Brenna and a `shop_requested` signal but no shop logic. `ShopUI` now attaches a
  `Merchant` with `data/shops/armory.tres` to every Armory's `merchant` NPC at runtime, so
  `[E] Browse wares of Weaponsmith Brenna` opens the shop. `Armory.shop_requested` still fires.
  Embedding `merchant.gd` in Brenna's scene instead worked, but made Godot report leaked scripts
  and resources at every exit, hence the runtime attach. No visual-branch file is modified.
- **`Merchant` binds deferred.** A parent NPC readies after its children, and
  `NPC.interactable` is `@onready`, so a Merchant inside an NPC scene found no Interactable
  (shop never opened). Bug in the gameplay branch, found by the integration.
- **`tools/.gdignore` removed.** The gameplay branch added it to keep Godot out of its Python
  tools, but the visual branch keeps GDScript tools there (`res://tools/generate_armory.gd`,
  `generate_buildings.gd`) that must stay loadable. Godot ignores `.py` files anyway.
- `tests/phase5f_integration_tests.gd` (17 checks): Armory in the village, Brenna's prompt and
  world keycap, her shop opening (and `shop_requested`), buying and equipping, the minimap label,
  the WASD guide, and the HUD staying clear at the counter.
- `tests/capture_phase5f_integrated_screenshots.gd`: rendered walkthrough (spawn, Armory,
  Brenna's prompt and shop, a purchase, a dash ending in Idle).

## Launch
```powershell
& "D:\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\courier-phase5f-integrated"
```
Run the windowed executable so the game is playable. That is a debug build with a window, so
development mode applies: 500 starting gold, granted once per save. Progress (gold, items,
equipment, delivered contracts) is saved to `user://savegame.json`. Start fresh with
`& "D:\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\courier-phase5f-integrated" -- --new-game`.

## Tests
Run each suite with
`godot --headless --path . --script res://tests/<suite>.gd`. The exit code is the number of
failed checks. Results are in the integration commit message.
