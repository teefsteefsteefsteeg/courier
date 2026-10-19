# Phase 6 continuation, 2026-10-19

Work continues in `D:\courier-phase5f-integrated`, on `phase5f-integrated` at `de43cda`.
Main and remotes were not changed. The Phase 5F handoff predates committed Phase 5G/5H
and substantial uncommitted tool gameplay. No separate Phase 6 brief was present; this
continuation completes and validates gaps in that existing tool/gathering loop. It does
not establish that an externally defined Phase 6 roadmap is complete.

The initial tracked diff and status were preserved locally in
`validation/phase6/preexisting.patch` and `preexisting-status.txt`. Existing imports,
map/terrain edits, vendor packs and unfinished gameplay were retained. Additional
Phase 5H documentation and tests appeared during the session; those were preserved too.

## Changes in this continuation

- Harvesting with a full primary material stack refuses work and preserves the resource
  node. A direct completion call cannot deplete a node for zero yield.
- Work stops after leaving the site's reach or changing the equipped tool. Active jobs
  use current positions because physics overlap lists can lag a teleport.
- Fishing initializes each cast's result independently. Cancelling after a fish has
  already landed reports success without adding a second catch. Removed sites cancel safely.
- `ShopService.sell_material` validates merchant catalog, material, quantity and stock
  before transferring materials and gold. The shop delegates sales to it and refuses
  selling through a closed shop.
- Long interaction prompts clear the key guide at narrow widths; material counts use
  light text against the equipment panel, verified in a rendered capture.
- The playable rod uses `assets/generated/tools/fishing_rod.tscn`: 540 triangles,
  grip-centred pivot, metre scale, four shared materials, three line guides, `Tip`
  marker and optional capsule collision disabled while held. The old rod is retained.

## Validation

Godot 4.7.2 console executable: `D:\godot\Godot_v4.7.2-stable_win64_console.exe`.
Set a process-local APPDATA to a writable test folder to isolate saves and satisfy
this session's filesystem restrictions:

```powershell
$env:APPDATA = 'D:/courier-phase5f-integrated/validation/phase6/appdata'
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/phase6_tools_tests.gd
```

`phase6_tools_tests.gd`: 105 checks, 0 failures. Covers purchasing all six tools,
stable target IDs, wrong tool, full stacks, cancellation, reach, changing tools,
harvesting/regrowth, all three repairs and single rewards, early/missed/successful
fishing, repeated casts, cancellation after landing, selling, disk save/load, legacy
state, generated rod geometry/pivot/collision and its playable item reference.

The existing full-suite run and subsequent targeted results are stored under
`validation/phase6/`. An old World/UI assertion expected seven zones; the current
Phase 5H test correctly expects ten and passes 127 checks. The tool-system test's
rod-path assertion was updated to the integrated generated asset. Final results: all 31
suites pass, including 132 tool-system checks and 105 continuation checks. The final
180-frame village boot reports only the certificate-store startup diagnostic below.

Rendered Forward+ runs at 1600x900 were actually captured and inspected:

- `capture_phase5h_screenshots.gd`: 0 reported problems, including tool purchasing,
  bank fishing, chopping, mining, digging, jetty and wall repair, jetty fishing,
  equipment, save/reload and restored world visuals.
- `capture_phase6_screenshots.gd`: 0 reported problems, including the generated rod
  in the real village, readable material counts and the live selling UI; its clay
  Sell all button removes stock and increases gold.
- `capture_generated_assets.gd`: dedicated view of the equipped rod in the village.

Images: `validation/phase6/screenshots/` and `screenshots-final/`. These are local
validation artifacts, excluded from Godot import by `validation/.gdignore`.

Godot emits `Failed to read the root certificate store` in this restricted session.
This engine startup diagnostic also appears in unchanged tests. Initial save-write
failures were resolved by the APPDATA override; the regular player's save was not changed.
Human feel/playtesting remains unverified.

## Commit limitation

Creating `phase6-tools-completion` failed with permission denied on
`D:/courier/.git/refs/heads/phase6-tools-completion.lock`. This worktree's Git metadata
is outside the writable workspace. No commit or push was made. Review the mixed
pre-existing and continuation changes before staging when Git metadata is writable.
