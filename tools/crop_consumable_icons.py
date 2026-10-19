"""Cut the consumable icons out of the user's UI sheet (assets/potion/01_image-01.png).

    python tools/crop_consumable_icons.py

The sheet is one 2048x2048 image of painted UI parts on a mottled brown background. For each
icon below, a square around it is cropped, the background is removed with a flood fill from
the crop's border that follows small colour steps (it stops at the icon's dark outline),
and the result is trimmed, padded and saved as a 64x64 RGBA icon in assets/ui/item_icons/.
"""
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/potion/01_image-01.png"
OUT = ROOT / "assets/ui/item_icons"
# name: (centre x, centre y, half size) in sheet pixels.
ICONS = {
    "health_potion": (1111, 861, 84),
    "mana_potion": (1267, 861, 84),
    "bread_loaf": (1436, 861, 84),
    "red_apple": (1601, 861, 80),
    "fresh_milk": (1749, 861, 84),
    "raw_steak": (1913, 861, 84),
}
STEP = 26  # max colour distance between neighbouring background pixels


def cut(image):
    w, h = image.size
    px = image.load()
    background = [[False] * w for _ in range(h)]
    queue = deque()
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))
    for x, y in queue:
        background[y][x] = True

    def dist(a, b):
        return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])

    while queue:
        x, y = queue.popleft()
        here = px[x, y]
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not background[ny][nx]:
                there = px[nx, ny]
                # Background is dull: never flood into bright or saturated paint.
                lum = (there[0] + there[1] + there[2]) / 3
                sat = max(there[:3]) - min(there[:3])
                if dist(here, there) <= STEP and lum < 140 and sat < 95:
                    background[ny][nx] = True
                    queue.append((nx, ny))
    alpha = Image.new("L", (w, h), 255)
    apx = alpha.load()
    for y in range(h):
        for x in range(w):
            if background[y][x]:
                apx[x, y] = 0
    # Soften the cut by one pixel.
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    result = image.convert("RGBA")
    result.putalpha(alpha)
    return result


def main():
    sheet = Image.open(SHEET).convert("RGB")
    for name, (cx, cy, half) in ICONS.items():
        crop = sheet.crop((cx - half, cy - half, cx + half, cy + half))
        icon = cut(crop)
        box = icon.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        if box:
            icon = icon.crop(box)
        side = max(icon.size)
        square = Image.new("RGBA", (side + 8, side + 8), (0, 0, 0, 0))
        square.paste(icon, ((side + 8 - icon.size[0]) // 2, (side + 8 - icon.size[1]) // 2), icon)
        square.resize((64, 64), Image.LANCZOS).save(OUT / f"{name}.png")
        print("wrote", OUT / f"{name}.png")


if __name__ == "__main__":
    main()
