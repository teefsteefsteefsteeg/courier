"""Crop the input prompt spritesheet into separate pixel-art icons.

    python tools/crop_input_prompts.py [--preview out.png]

Reads assets/ui/input_prompts/input_prompts.png (AI-generated, 1774x887, keys on a
soft ~4 px grid with a semi-transparent glow around each group) and writes one PNG per
keyboard key and mouse icon to assets/ui/input_prompts/icons/, plus regions.json with
the source rectangle of every icon.

How icons are found: opaque pixels (alpha >= OPAQUE) are split into 4-connected
components; each layout row below is a band of the sheet whose components, sorted by x,
must match the expected names exactly, or the script stops. The up and down arrow keys
touch and are split at the seam row. The mouse-wheel icon is the mouse body plus its
two arrow components. Each icon keeps only its own component (grown by EDGE px to
keep the anti-aliased edge), so neighbouring glow and captions are dropped, then it is
box-downsampled (premultiplied alpha) to ICON_HEIGHT px for 1:1 nearest-filter display.

Not exported: gamepad buttons (no gamepad bindings) and the "UI prompt examples" row.
The sheet has no I, O, P, T, U, Y or 0, 7, 8, 9 keys; the game falls back to a drawn keycap.
"""
import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/ui/input_prompts/input_prompts.png"
OUT_DIR = ROOT / "assets/ui/input_prompts/icons"
OPAQUE = 160
EDGE = 2
ICON_HEIGHT = 32
MIN_SIZE = 30

# (name prefix, names left to right, y range, x range) for each band of the sheet.
LAYOUT = [
    ("key", "w a s d q e r f g h j k l".split(), (55, 155), (0, 1420)),
    ("key", "z x c v b n m 1 2 3 4 5 6".split(), (155, 260), (0, 1420)),
    ("key", ["left", "updown", "right"], (60, 260), (1440, 1774)),
    ("key", "tab shift ctrl alt esc f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12".split(), (305, 405), (0, 1774)),
    ("key", "space enter backspace delete insert home end page_up page_down".split(), (445, 545), (0, 1774)),
    ("mouse", ["left", "right", "middle", "wheel", "cursor", "hand"], (585, 690), (0, 640)),
]


def components(mask):
    """Label 4-connected components; returns (labels, list of (y0, x0, y1, x1) inclusive)."""
    h, w = mask.shape
    labels = np.zeros(mask.shape, dtype=np.int32)
    boxes = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if labels[y0, x0]:
            continue
        index = len(boxes) + 1
        labels[y0, x0] = index
        queue = deque([(y0, x0)])
        top, left, bottom, right = y0, x0, y0, x0
        while queue:
            y, x = queue.popleft()
            top, bottom, left, right = min(top, y), max(bottom, y), min(left, x), max(right, x)
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = index
                    queue.append((ny, nx))
        boxes.append((top, left, bottom, right))
    return labels, boxes


def grow(mask, radius):
    out = mask.copy()
    for _ in range(radius):
        shifted = out.copy()
        shifted[1:] |= out[:-1]
        shifted[:-1] |= out[1:]
        shifted[:, 1:] |= out[:, :-1]
        shifted[:, :-1] |= out[:, 1:]
        out = shifted
    return out


def export(rgba, mask, name, regions):
    mask = grow(mask, EDGE) & (rgba[:, :, 3] > 0)
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    pixels = rgba[y0:y1, x0:x1].copy()
    pixels[~mask[y0:y1, x0:x1]] = 0
    icon = Image.fromarray(pixels, "RGBA").convert("RGBa")
    width = max(1, round((x1 - x0) * ICON_HEIGHT / (y1 - y0)))
    icon = icon.resize((width, ICON_HEIGHT), Image.BOX).convert("RGBA")
    icon.save(OUT_DIR / f"{name}.png")
    regions[name] = {"x": int(x0), "y": int(y0), "w": int(x1 - x0), "h": int(y1 - y0), "size": [width, ICON_HEIGHT]}
    return icon


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", help="write a labelled contact sheet here")
    args = parser.parse_args()

    rgba = np.array(Image.open(SHEET).convert("RGBA"))
    labels, boxes = components(rgba[:, :, 3] >= OPAQUE)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    regions = {}
    icons = []
    for prefix, names, (band_top, band_bottom), (band_left, band_right) in LAYOUT:
        found = [
            (left, index + 1) for index, (top, left, bottom, right) in enumerate(boxes)
            if band_top <= top < band_bottom and band_left <= left < band_right
            and bottom - top + 1 >= MIN_SIZE and right - left + 1 >= MIN_SIZE
        ]
        found.sort()
        if len(found) != len(names):
            raise SystemExit(f"{prefix} {names[0]}..: expected {len(names)} icons, found {len(found)}")
        for (left, index), name in zip(found, names):
            mask = labels == index
            if name == "updown":
                # Up sits on top of down and their outlines touch: cut at the thinnest row.
                top, _, bottom, _ = boxes[index - 1]
                middle = range(top + (bottom - top) // 3, top + 2 * (bottom - top) // 3)
                seam = min(middle, key=lambda y: mask[y].sum())
                upper, lower = mask.copy(), mask.copy()
                upper[seam:] = False
                lower[:seam + 1] = False
                icons.append(("key_up", export(rgba, upper, "key_up", regions)))
                icons.append(("key_down", export(rgba, lower, "key_down", regions)))
                continue
            if prefix == "mouse" and name == "wheel":
                # The scroll arrows are separate small components just left of the body.
                top, body_left, bottom, _ = boxes[index - 1]
                for other, (o_top, o_left, o_bottom, o_right) in enumerate(boxes):
                    if o_top >= top - 10 and o_bottom <= bottom and body_left - 30 <= o_left < body_left:
                        mask |= labels == other + 1
            full = f"{prefix}_{name}"
            icons.append((full, export(rgba, mask, full, regions)))

    (OUT_DIR / "regions.json").write_text(json.dumps(regions, indent=1, sort_keys=True) + "\n")
    print(f"wrote {len(icons)} icons to {OUT_DIR.relative_to(ROOT)}")

    if args.preview:
        scale, columns, cell = 2, 8, (200, 100)
        rows = (len(icons) + columns - 1) // columns
        sheet = Image.new("RGBA", (columns * cell[0], rows * cell[1]), (52, 74, 52, 255))
        draw = ImageDraw.Draw(sheet)
        for i, (name, icon) in enumerate(icons):
            x, y = (i % columns) * cell[0], (i // columns) * cell[1]
            big = icon.resize((icon.width * scale, icon.height * scale), Image.NEAREST)
            if big.width > cell[0] - 8:
                big = big.resize((cell[0] - 8, round(big.height * (cell[0] - 8) / big.width)), Image.NEAREST)
            sheet.alpha_composite(big, (x + 4, y + 4))
            draw.text((x + 4, y + cell[1] - 18), name, fill=(255, 255, 255, 255))
        sheet.save(args.preview)


if __name__ == "__main__":
    main()
