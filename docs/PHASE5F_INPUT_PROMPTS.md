# Phase 5F: pixel-art input prompts

Branch `phase5f-gameplay-ui`. Replaces the text key hints (`[E]`, `[J]`, ...) in the gameplay HUD
with keycaps cropped from the supplied pixel-art sheet, and adds a keycap that floats beside the
focused NPC or object. Key names always come from the Godot InputMap.

## The sheet and the crops
`assets/ui/input_prompts/input_prompts.png`, 1774x887, AI-generated. It arrived as
`601f027d-f495-417a-9a52-8d86fcf11972.png` in that folder and was renamed to the expected path.

What the inspection found:
- Keys are opaque (alpha ~250) on a soft ~4 px pixel grid. Each group sits on a semi-transparent
  glow (alpha ~5-200) that must not end up in the icons, and the gaps between keys are near
  transparent (alpha ~20), so icons separate cleanly at alpha >= 160.
- Spacing is irregular (keys 86-93 px wide, rows offset by a few px), so regions are found from the
  pixels rather than a fixed grid.
- The up and down arrow keys touch and come out as one shape; they are split at the thinnest row.
  `key_down`'s top outline is hidden under `key_up` in the sheet, so its top edge is flatter than
  other keys'. Usable.
- The mouse-wheel icon is three shapes (body and two arrows) and is merged.
- Missing from the sheet: letters I, O, P, T, U, Y and digits 0, 7, 8, 9. No other keys are
  unusable.

`tools/crop_input_prompts.py` (Pillow + numpy; `tools/` has a `.gdignore`) does the cropping:
connected components per layout band, matched to the expected names left to right (it stops if
a band's count is off), with each icon keeping only its own pixels plus a 2 px anti-aliased edge,
so neighbouring glow and captions are dropped. Each icon is box-downsampled (premultiplied alpha)
to 32 px tall: at 1/4 scale (the native grid) the text on wide keys (Shift, Backspace) became
illegible, while at 32 px everything stays crisp. Output is 62 PNGs in
`assets/ui/input_prompts/icons/` (`key_w`, `key_shift`, `key_f3`, `key_space`, `mouse_left`,
`mouse_wheel`, ...) and `regions.json` with every source rectangle. Not exported: gamepad buttons
(the game has no gamepad bindings) and the "UI prompt examples" row (composites, not icons).
Re-run with `python tools/crop_input_prompts.py --preview <png>` to get a labelled contact sheet.

The icons import with the default lossless 2D settings and no mipmaps. Every node that draws one
uses `TEXTURE_FILTER_NEAREST` at an integer scale. The full sheet is never displayed.

## Runtime
| Script | Role |
|---|---|
| `scripts/ui/input_prompts/input_prompt_icons.gd` (`InputPromptIcons`) | Binding -> icon. `primary_event(action)` reads `InputMap.action_get_events` (first event with an icon, else first key, else first mouse button); physical keys are named for the player's layout (`DisplayServer.keyboard_get_keycode_from_physical`, skipped on the headless server). |
| `scripts/ui/input_prompts/input_prompt.gd` (`InputPrompt`, scene `scenes/ui/input_prompt.tscn`) | Reusable component: one keycap per action plus optional text. `refresh()` after a rebind. A key without an icon gets a drawn keycap in the sheet's colours with the key name; an unbound action shows `?`. |
| `scripts/ui/input_prompts/input_prompt_label.gd` (`InputPromptLabel`) | Overlay for an existing hint `Label`: draws its `[E] Talk   [Escape] Close` text with keycaps. The label keeps its text (code and tests still read it) and only its own glyphs are hidden. It follows text and colour changes, keeps wrapping, and grows the label's minimum height for the 32 px keycaps. |

`InputHints.key_for()` uses the same layout-aware key name, so hint text and icons always agree.

### Where prompts appear
- **Interaction prompt** (bottom centre): `[E] Talk to Postmaster Bram` / `[E] Deliver ... to ...`
  with the E keycap. Context colours are kept.
- **World keycap** (`InteractionPrompt.world_badge`): beside the focused NPC's head (1.9 m) or 0.9 m
  above other interactables (overridable with `prompt_anchor_height` metadata). It shows only while
  the prompt line does, so it hides with nothing in range, a disabled interactable, an open
  dialogue, journal, quest board or expanded map. It also hides when off screen, over the prompt
  line, or over any visible control in `InputPrompt.AVOID_GROUP`: quest tracker, wallet,
  onboarding, package indicator, package status, toasts, compact and expanded minimap, and the
  dialogue box.
- **Onboarding** (`[E] Read the quest board...`, `[J] Journal  [M] Map`), **journal** hint and close
  hint, **dialogue** hint (`[E] Next / Talk`, `[Escape] Close`), **package** panel (`[G] Drop`),
  **expanded map** (`[M] / [Escape] Close`).
- **Movement guide** (`scripts/gameplay_ui/movement_guide.gd`, `GameplayHUD.movement_guide`): the four
  movement bindings as an inverted-T of keycaps with "Move", bottom-left, stacked above the
  Phase 4 combat panel. Keys come from `move_forward/left/back/right` in the InputMap (W A S D in
  this project), and the guide rebuilds itself within 0.5 s of a rebind (arrow keys show arrows).
  It hides when `UISettings.SHOW_MOVEMENT_GUIDE` is off (`scripts/ui/ui_settings.gd`, saved to
  `user://ui_settings.cfg`, read every frame so a future settings menu applies instantly). It
  also hides when it would overlap another panel: on canvases narrower than ~1100 px the 960 px
  dialogue box reaches the left edge, so the guide steps aside while dialogue is open.
  Verified in a GPU window (`tests/capture_movement_guide_screenshots.gd`) at 1600x900, 1280x720
  and 1024x576 windows (the canvas scales, layout unchanged) and at unscaled 1280x720 and
  1024x600 canvases: visible, W A S D icons, no overlaps.
  Before this the HUD had no movement hint at all; the earlier pass only converted the hints
  that already existed (`[E]`, `[J]`, `[M]`, `[G]`, `[Esc]`).
- The journal's bottom-centre hint now stands down while the dialogue box is open. It sat inside the
  box's area before; the taller keycap made the overlap visible.
- The minimap drops an NPC's name label while the objective marker sits on that NPC, so the two
  labels don't overprint.

Bindings in this project (from `project.godot`): WASD move, Shift run and dash, E interact, G drop,
Space magic bolt, Q shield, J journal, M map, F3 debug HUD, mouse wheel / `=` `-` zoom, plus Godot's
default Escape / Enter for `ui_cancel` / `ui_accept`. All of them have icons.

## Not changed
- The Phase 3 cargo exhibit's world-space `[E] View ...` text (a 3D label in the Phase 3 showcase)
  and the Phase 4 combat HUD rows (`Bolt: Ready`...) and their forest notice text. They belong to the
  Phase 3/4 visual layers, and the combat panel's layout is pinned by the Phase 4 HUD tests. Both
  can use `InputPrompt` later.
- No gameplay, input bindings, environment or building assets.

## Tests
`tests/input_prompt_tests.gd` (64 checks):
- **Icons:** all 62 load, are 32 px tall and have no mipmaps; single crops, never the sheet.
- **Bindings:** every gameplay binding resolves to an icon; expected icons are derived from the
  InputMap; zoom shows the wheel; missing keys have no icon.
- **Component:** rebinding (W to Up, a key without an icon gets a fallback keycap, unbound shows `?`),
  nearest filtering, 1:1 and 2x scale, and the scene.
- **Hint parsing.**
- **Village HUD:** the onboarding, journal, map, package, prompt and dialogue hints draw the right
  keycaps; the journal hint stands down under the dialogue.
- **World keycap:** shown beside Bram, on screen and clear of the prompt and HUD; hidden out of
  range, under the dialogue, journal and map, and for a disabled interactable; hidden under a HUD
  panel and back after; follows a rebind.

`tests/capture_input_prompt_screenshots.gd` renders seven views (spawn, Bram, board, dialogue,
carrying at Mira, journal, map) in a GPU window for visual review.

## Limitations
- With `canvas_items` stretch at a window size other than 1600x900, the 2D canvas scales by a
  non-integer factor, so nearest-filtered pixels become slightly uneven.
- The Space keycap is 161 px wide, the art's proportion.
- Layout-aware key names were only exercised on the US layout (headless has no layout).
