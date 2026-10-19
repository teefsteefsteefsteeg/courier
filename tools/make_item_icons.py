"""Draw the placeholder pixel-art shop icons (16x16 art, saved 2x = 32x32).

    python tools/make_item_icons.py

Writes assets/ui/item_icons/<item_id>.png for the Armory and Toolwright catalogs and the
gathered materials (data/materials/, by material_id). Shapes are rasterised
on a 16 px grid and get a dark 1 px outline, matching the input prompt keycaps' palette.
"""
import math
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


def bow():
    limb, grip, string, shaft, head, fletch = set(), set(), set(), set(), set(), set()
    # Quarter-circle limb bulging to the upper left, string corner to corner, and an
    # arrow nocked on the string pointing out past the limb.
    for step in range(40):
        angle = math.radians(180 + step * 90 / 39)
        limb.add((round(13 + 11.5 * math.cos(angle)), round(13 + 11.5 * math.sin(angle))))
    for p in list(limb):
        if 4 <= p[0] <= 6 and 4 <= p[1] <= 6:
            grip.add(p)
    line(string, 2, 13, 13, 2)
    line(shaft, 9, 9, 3, 3)
    head.update({(2, 2), (2, 3), (3, 2)})
    fletch.update({(10, 9), (9, 10), (10, 10)})
    return draw([(WOOD, limb), (LEATHER, grip), ((226, 220, 200, 255), string), ((176, 128, 80, 255), shaft),
            ((200, 206, 216, 255), head), ((80, 150, 220, 255), fletch)])


# --- Phase 5H tools and materials -------------------------------------------------------

STEEL = (178, 186, 198, 255)
STEEL_DARK = (118, 126, 140, 255)
STEEL_LIGHT = (226, 232, 240, 255)


def disc(cx, cy, r2):
    return {(x, y) for y in range(16) for x in range(16) if (x - cx) ** 2 + (y - cy) ** 2 <= r2}


def fishing_rod():
    pole, cork, reel, cord, float_red, float_white = set(), set(), set(), set(), set(), set()
    line(pole, 2, 14, 13, 1)
    line(cork, 2, 14, 4, 12)
    reel.update({(5, 12), (6, 12), (5, 13), (6, 13)})
    line(cord, 13, 1, 13, 10)
    float_red.update({(12, 11), (13, 11), (14, 11)})
    float_white.update({(12, 12), (13, 12), (14, 12), (13, 13)})
    return draw([(WOOD, pole), (LEATHER, cork), (STEEL_DARK, reel), ((226, 220, 200, 255), cord),
            ((214, 54, 44, 255), float_red), ((240, 240, 232, 255), float_white)])


def hammer():
    handle, head, face, band = set(), set(), set(), set()
    line(handle, 3, 14, 9, 6)
    for y in range(2, 7):
        for x in range(7, 14):
            if (x - 10) + (y - 4) in range(-4, 5) and abs((x - 10) - (y - 4)) <= 3:
                head.add((x, y))
    face.update({(12, 5), (13, 4), (13, 5), (12, 6)})
    band.update({(8, 7), (9, 7)})
    return draw([(WOOD, handle), (STEEL, head), (STEEL_DARK, face), (LEATHER, band)])


def woodcutter_axe():
    handle, head, edge = set(), set(), set()
    line(handle, 3, 14, 10, 3)
    for i, w in enumerate([2, 3, 4, 4, 3, 2]):
        for x in range(10, 10 + w):
            head.add((x, 2 + i))
    for i, w in enumerate([2, 3, 4, 4, 3, 2]):
        edge.add((9 + w, 2 + i))
    return draw([(WOOD, handle), (STEEL_DARK, head), (STEEL_LIGHT, edge), (WOOD_DARK, {(6, 10)})])


def pickaxe():
    handle, head, tips = set(), set(), set()
    line(handle, 3, 14, 10, 5)
    for x in range(3, 15):
        y = round(4 + ((x - 9) / 6.0) ** 2 * 2.5)
        head.add((x, y))
        head.add((x, y - 1))
    tips.update({(2, 7), (14, 7)})
    return draw([(WOOD, handle), (STEEL, head), (STEEL_LIGHT, tips), (LEATHER, {(9, 7), (8, 8)})])


def shovel():
    handle, grip, blade, shine = set(), set(), set(), set()
    line(handle, 11, 2, 6, 9)
    grip.update({(11, 1), (12, 1), (12, 2), (10, 1)})
    for y in range(9, 15):
        for x in range(2, 9):
            if (x - 5) ** 2 / 9.0 + (y - 11) ** 2 / 12.0 <= 1.0:
                blade.add((x, y))
    shine.update({(4, 10), (4, 11)})
    return draw([(WOOD, handle), (LEATHER, grip), (STEEL, blade), (STEEL_LIGHT, shine)])


def trowel():
    handle, neck, blade, edge = set(), set(), set(), set()
    line(handle, 11, 3, 14, 0)
    line(neck, 10, 4, 9, 6)
    for y in range(6, 15):
        half = (y - 6) * 0.45
        for x in range(16):
            if abs(x - (9 - (y - 6) * 0.55)) <= half + 0.5:
                blade.add((x, y))
    line(edge, 1, 14, 6, 14)
    return draw([(WOOD, handle), (STEEL_DARK, neck), (STEEL, blade), (STEEL_LIGHT, edge)])


def fish(body, belly, fin):
    shape, under, tail, eye = set(), set(), set(), set()
    for y in range(16):
        for x in range(16):
            if ((x - 7) / 5.5) ** 2 + ((y - 8) / 3.2) ** 2 <= 1.0:
                shape.add((x, y))
                if y >= 9:
                    under.add((x, y))
    for i in range(4):
        tail.update({(12 + i, 8 - i), (12 + i, 8 + i), (12 + i, 8)})
    eye.add((4, 7))
    return draw([(fin, tail), (body, shape), (belly, under), (OUTLINE, eye), (fin, {(7, 4), (8, 4), (8, 5)})])


def log():
    bark, end, ring = set(), set(), set()
    for y in range(5, 12):
        for x in range(2, 13):
            bark.add((x, y))
    end.update(disc(12.5, 8.0, 10.5))
    ring.update({(12, 8), (13, 8), (12, 7)})
    return draw([(WOOD_DARK, bark), ((176, 132, 84, 255), end), (WOOD, ring), (LEATHER, {(5, 7), (8, 10), (9, 6)})])


def stone(light, dark, specks=()):
    rock, shade = set(), set()
    for y in range(16):
        for x in range(16):
            if ((x - 7.5) / 6.0) ** 2 + ((y - 9) / 5.0) ** 2 <= 1.0:
                rock.add((x, y))
                if y >= 10 or x >= 11:
                    shade.add((x, y))
    return draw([(light, rock), (dark, shade), ((214, 156, 92, 255), set(specks))])


def clay():
    lump, wet = set(), set()
    for y in range(16):
        for x in range(16):
            if ((x - 7.5) / 6.5) ** 2 + ((y - 10) / 4.2) ** 2 <= 1.0:
                lump.add((x, y))
    wet.update({(5, 8), (6, 8), (9, 9)})
    return draw([((178, 104, 72, 255), lump), ((214, 146, 108, 255), wet)])


def seed_pouch(seed, seed_dark):
    bag, shade, tie, seeds = set(), set(), set(), set()
    for y in range(16):
        for x in range(16):
            if ((x - 7.5) / 5.5) ** 2 + ((y - 10.0) / 4.8) ** 2 <= 1.0:
                bag.add((x, y))
                if x >= 10 or y >= 13:
                    shade.add((x, y))
    for y in range(3, 7):
        for x in range(6, 10):
            bag.add((x, y))
    line(tie, 5, 6, 10, 6)
    seeds.update({(6, 10), (8, 9), (9, 11), (7, 12), (10, 9)})
    return draw([((206, 176, 124, 255), bag), ((170, 140, 96, 255), shade), (LEATHER, tie), (seed, seeds), (seed_dark, {(8, 10), (7, 11)})])


def wheat():
    stalk, grain, light = set(), set(), set()
    for x0 in (5, 8, 11):
        line(stalk, x0, 15, x0 - 1, 7)
        for y in range(2, 8):
            grain.add((x0 - 1 + (y % 2), y))
        light.update({(x0 - 1, 3), (x0, 5)})
    return draw([((122, 150, 64, 255), stalk), ((214, 172, 74, 255), grain), ((244, 214, 120, 255), light)])


def carrot():
    root, shade, leaf = set(), set(), set()
    for y in range(6, 16):
        half = max(0.5, (15 - y) * 0.32)
        for x in range(16):
            if abs(x - 7.5) <= half:
                root.add((x, y))
                if x > 7.5:
                    shade.add((x, y))
    for dx in (-2, 0, 2):
        line(leaf, 7 + dx // 2, 6, 7 + dx, 1)
    return draw([((232, 128, 40, 255), root), ((196, 96, 30, 255), shade), ((88, 160, 64, 255), leaf)])


def pumpkin():
    body, rib, stem = set(), set(), set()
    for y in range(16):
        for x in range(16):
            if ((x - 7.5) / 6.8) ** 2 + ((y - 9.5) / 5.5) ** 2 <= 1.0:
                body.add((x, y))
                if x in (4, 7, 11):
                    rib.add((x, y))
    stem.update({(8, 3), (8, 4), (9, 2)})
    return draw([((228, 134, 40, 255), body), ((190, 98, 28, 255), rib), ((96, 120, 52, 255), stem)])


def vest(cloth, cloth_dark, trim):
    body, shade, edge = set(), set(), set()
    for y in range(3, 15):
        for x in range(3, 13):
            if y < 6 and 6 <= x <= 9:
                continue
            body.add((x, y))
            if x >= 10:
                shade.add((x, y))
    line(edge, 7, 6, 7, 14)
    line(edge, 8, 6, 8, 14)
    return draw([(cloth, body), (cloth_dark, shade), (trim, edge)])


ICONS = {
    "wooden_sword": lambda: sword((182, 132, 78, 255), WOOD_DARK, WOOD_DARK, LEATHER),
    "iron_sword": lambda: sword((178, 184, 194, 255), (122, 128, 140, 255), GOLD, GOLD_DARK),
    "steel_sword": lambda: sword((228, 238, 250, 255), (150, 172, 200, 255), GOLD, GOLD_DARK),
    "battle_axe": axe,
    "magic_staff": staff,
    "wooden_shield": shield,
    "hunting_bow": bow,
    # Phase 5H tools (Toolwright) and gathered materials.
    "fishing_rod": fishing_rod,
    "carpenter_hammer": hammer,
    "woodcutter_axe": woodcutter_axe,
    "miner_pickaxe": pickaxe,
    "garden_shovel": shovel,
    "mason_trowel": trowel,
    "pond_perch": lambda: fish((112, 150, 96, 255), (196, 206, 150, 255), (210, 120, 70, 255)),
    "silver_trout": lambda: fish((150, 168, 190, 255), (226, 232, 240, 255), (196, 120, 150, 255)),
    "golden_carp": lambda: fish((222, 168, 54, 255), (250, 214, 120, 255), (200, 100, 40, 255)),
    "wood": log,
    "stone": lambda: stone((150, 150, 156, 255), (110, 110, 118, 255)),
    "iron_ore": lambda: stone((120, 104, 98, 255), (90, 76, 72, 255), [(5, 7), (8, 9), (10, 6), (6, 11)]),
    "clay": clay,
    # Phase 7 farming: seed pouches and produce.
    "wheat_seeds": lambda: seed_pouch((214, 172, 74, 255), (160, 120, 40, 255)),
    "carrot_seeds": lambda: seed_pouch((232, 128, 40, 255), (170, 84, 24, 255)),
    "pumpkin_seeds": lambda: seed_pouch((240, 226, 180, 255), (190, 170, 120, 255)),
    "wheat": wheat,
    "carrot": carrot,
    "pumpkin": pumpkin,
    # Phase 7 armor.
    "leather_vest": lambda: vest((150, 96, 56, 255), (112, 68, 40, 255), GOLD_DARK),
    "iron_mail": lambda: vest((170, 176, 188, 255), (120, 126, 140, 255), GOLD),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in ICONS.items():
        make().save(OUT / f"{name}.png")
    print(f"wrote {len(ICONS)} icons to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
