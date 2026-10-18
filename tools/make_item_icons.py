"""Draw the placeholder pixel-art shop icons (16x16 art, saved 2x = 32x32).

    python tools/make_item_icons.py

Writes assets/ui/item_icons/<item_id>.png for the Armory catalog. Shapes are rasterised
on a 16 px grid and get a dark 1 px outline, matching the input prompt keycaps' palette.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ui/item_icons"
OUTLINE = (24, 20, 38, 255)
GOLD = (214, 172, 64, 255)
GOLD_DARK = (160, 118, 40, 255)
WOOD = (150, 100, 55, 255)
WOOD_DARK = (110, 70, 38, 255)
LEATHER = (96, 58, 40, 255)


def line(points, x0, y0, x1, y1, width=1):
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        x = round(x0 + (x1 - x0) * i / steps)
        y = round(y0 + (y1 - y0) * i / steps)
        for w in range(width):
            points.add((x + w, y))


def draw(layers):
    """layers: list of (colour, set of (x, y)); later layers paint over earlier ones."""
    grid = {}
    for colour, points in layers:
        for p in points:
            if 0 <= p[0] < 16 and 0 <= p[1] < 16:
                grid[p] = colour
    image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for (x, y), colour in grid.items():
        image.putpixel((x, y), colour)
    for y in range(16):
        for x in range(16):
            if (x, y) in grid:
                continue
            if any((x + dx, y + dy) in grid for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                image.putpixel((x, y), OUTLINE)
    return image.resize((32, 32), Image.NEAREST)


def sword(light, dark, guard, guard_dark):
    blade, edge, hilt, grip, pommel = set(), set(), set(), set(), set()
    line(blade, 5, 10, 13, 2)
    line(edge, 6, 10, 13, 3)
    line(hilt, 3, 9, 6, 12)
    line(hilt, 2, 8, 2, 8)
    line(grip, 3, 12, 2, 13)
    pommel.add((1, 14))
    return draw([(light, blade), (dark, edge), (guard, hilt), (guard_dark, {(6, 12)}), (LEATHER, grip), (guard, pommel)])


def axe():
    handle, head, head_dark, rim = set(), set(), set(), set()
    line(handle, 2, 14, 10, 4)
    widths = [3, 4, 5, 5, 5, 5, 4, 3]
    for i, w in enumerate(widths):
        y = 1 + i
        for x in range(10, 10 + w):
            head.add((x, y))
    for y in range(2, 8):
        head_dark.add((10, y))
    for i, w in enumerate(widths):
        rim.add((9 + w, 1 + i))
    return draw([(WOOD, handle), ((150, 158, 170, 255), head), ((112, 118, 132, 255), head_dark), ((220, 228, 238, 255), rim), (WOOD_DARK, {(5, 10), (8, 7)})])


def staff():
    pole, orb, glow, shine = set(), set(), set(), set()
    line(pole, 4, 15, 9, 5)
    for y in range(16):
        for x in range(16):
            d = (x - 10.5) ** 2 + (y - 3.5) ** 2
            if d <= 7.5:
                orb.add((x, y))
            if d <= 3.0:
                glow.add((x, y))
    shine.add((9, 2))
    return draw([(WOOD, pole), (WOOD_DARK, {(5, 13), (7, 9)}), (GOLD, {(8, 6), (9, 6)}), ((112, 64, 200, 255), orb), ((170, 120, 255, 255), glow), ((240, 225, 255, 255), shine)])


def shield():
    rim, wood, plank, boss = set(), set(), set(), set()
    for y in range(16):
        for x in range(16):
            d = (x - 7.5) ** 2 + (y - 7.5) ** 2
            if d <= 49:
                rim.add((x, y))
            if d <= 30:
                wood.add((x, y))
                if x in (5, 10):
                    plank.add((x, y))
            if d <= 3:
                boss.add((x, y))
    return draw([((140, 146, 158, 255), rim), (WOOD, wood), (WOOD_DARK, plank), (GOLD, boss), (GOLD_DARK, {(8, 8)})])


ICONS = {
    "wooden_sword": lambda: sword((182, 132, 78, 255), WOOD_DARK, WOOD_DARK, LEATHER),
    "iron_sword": lambda: sword((178, 184, 194, 255), (122, 128, 140, 255), GOLD, GOLD_DARK),
    "steel_sword": lambda: sword((228, 238, 250, 255), (150, 172, 200, 255), GOLD, GOLD_DARK),
    "battle_axe": axe,
    "magic_staff": staff,
    "wooden_shield": shield,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in ICONS.items():
        make().save(OUT / f"{name}.png")
    print(f"wrote {len(ICONS)} icons to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
