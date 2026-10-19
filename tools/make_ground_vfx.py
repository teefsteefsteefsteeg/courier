"""Bake the ground-effect decal textures used by scripts/vfx/ground_fx.gd (Phase 8).

    python tools/make_ground_vfx.py

Writes assets/vfx/ground/*.png (white or grey shapes with alpha; GroundFx tints them):
  ring.png         soft shockwave ring (expanding earthquake / impact rings)
  scorch.png       dark, ragged burn mark (fire, lightning strikes)
  cracks.png       branching ground fissures from the centre (Earthquake)
  rune_circle.png  arcane summoning circle: two rings, glyph band, star (Arcane Storm)
  glow.png         soft round glow (ground light under impacts)
Each glowing shape also gets <name>_emission.png: its colour premultiplied by alpha on black,
because a Decal's emission texture ignores alpha (a plain white texture would light up the
whole decal square).
All original procedural art (no third-party pixels).
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/vfx/ground"


def ring(size=256):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    half = size / 2
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - half + 0.5, y - half + 0.5) / half
            # Bright outer edge with a soft inner trail.
            edge = max(0.0, 1.0 - abs(r - 0.9) * 14.0)
            trail = max(0.0, 1.0 - (0.9 - r) * 3.2) * 0.45 if r < 0.9 else 0.0
            a = min(1.0, edge + trail * (r > 0.45))
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def scorch(size=256, seed=7):
    rng = random.Random(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    half = size / 2
    # Overlapping dark blobs make a ragged burn; soot specks outside it.
    for _ in range(40):
        angle = rng.random() * math.tau
        dist = rng.random() ** 1.6 * half * 0.55
        rad = rng.uniform(0.12, 0.3) * half
        cx, cy = half + math.cos(angle) * dist, half + math.sin(angle) * dist
        tone = rng.randint(14, 40)
        draw.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=(tone, tone - 6 if tone > 6 else 0, 0, rng.randint(90, 160)))
    for _ in range(90):
        angle = rng.random() * math.tau
        dist = rng.uniform(0.45, 0.9) * half
        rad = rng.uniform(1.5, 5)
        cx, cy = half + math.cos(angle) * dist, half + math.sin(angle) * dist
        draw.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=(20, 14, 8, rng.randint(80, 170)))
    img = img.filter(ImageFilter.GaussianBlur(3))
    # Keep a hot, slightly brown core.
    core = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(core).ellipse((half * 0.55, half * 0.55, half * 1.45, half * 1.45), fill=(10, 6, 4, 200))
    core = core.filter(ImageFilter.GaussianBlur(14))
    return Image.alpha_composite(img, core)


def cracks(size=512, seed=41):
    rng = random.Random(seed)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    half = size / 2

    def branch(x, y, angle, length, width, depth):
        steps = int(length / 6)
        for i in range(steps):
            angle += rng.uniform(-0.35, 0.35)
            nx, ny = x + math.cos(angle) * 6, y + math.sin(angle) * 6
            w = max(1, int(width * (1.0 - i / steps * 0.7)))
            draw.line((x, y, nx, ny), fill=(255, 255, 255, 255), width=w)
            x, y = nx, ny
            if depth < 2 and rng.random() < 0.06:
                branch(x, y, angle + rng.choice((-1, 1)) * rng.uniform(0.5, 1.0), length * 0.45, width * 0.6, depth + 1)

    for i in range(11):
        angle = math.tau * i / 11 + rng.uniform(-0.15, 0.15)
        branch(half, half, angle, rng.uniform(0.62, 0.95) * half, rng.uniform(5, 9), 0)
    # Soft halo so the fissures glow into the ground around them.
    glow = img.filter(ImageFilter.GaussianBlur(6))
    glow = Image.eval(glow, lambda v: v)
    base = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    a = glow.getchannel("A").point(lambda v: int(v * 0.55))
    base.putalpha(a)
    return Image.alpha_composite(base, img)


def rune_circle(size=512):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    c = size / 2

    def circle(r, w):
        draw.ellipse((c - r, c - r, c + r, c + r), outline=(255, 255, 255, 255), width=w)

    circle(c * 0.97, 7)
    circle(c * 0.86, 3)
    circle(c * 0.56, 5)
    circle(c * 0.5, 2)
    # Glyph band between the outer rings: little rune marks.
    rng = random.Random(3)
    for i in range(28):
        angle = math.tau * i / 28
        r0, r1 = c * 0.885, c * 0.945
        mid = (r0 + r1) / 2
        x, y = c + math.cos(angle) * mid, c + math.sin(angle) * mid
        kind = rng.randint(0, 3)
        tangent = angle + math.pi / 2
        dx, dy = math.cos(tangent) * 7, math.sin(tangent) * 7
        rx, ry = math.cos(angle) * 9, math.sin(angle) * 9
        if kind == 0:
            draw.line((x - rx, y - ry, x + rx, y + ry), fill=(255, 255, 255, 255), width=3)
            draw.line((x - dx, y - dy, x + dx, y + dy), fill=(255, 255, 255, 255), width=3)
        elif kind == 1:
            draw.line((x - rx - dx, y - ry - dy, x + rx, y + ry), fill=(255, 255, 255, 255), width=3)
            draw.line((x + rx, y + ry, x - rx + dx, y - ry + dy), fill=(255, 255, 255, 255), width=3)
        elif kind == 2:
            draw.ellipse((x - 5, y - 5, x + 5, y + 5), outline=(255, 255, 255, 255), width=3)
        else:
            draw.line((x - rx, y - ry, x + rx, y + ry), fill=(255, 255, 255, 255), width=3)
            draw.line((x + rx - dx, y + ry - dy, x + rx + dx, y + ry + dy), fill=(255, 255, 255, 255), width=3)
    # Six-pointed star inside the inner ring, and spokes to the middle ring.
    r = c * 0.5
    for offset in (0.0, math.pi / 3):
        pts = [(c + math.cos(offset + math.tau * k / 3 - math.pi / 2) * r, c + math.sin(offset + math.tau * k / 3 - math.pi / 2) * r) for k in range(3)]
        draw.polygon(pts, outline=(255, 255, 255, 255), width=4)
    for k in range(12):
        angle = math.tau * k / 12
        draw.line((c + math.cos(angle) * c * 0.56, c + math.sin(angle) * c * 0.56, c + math.cos(angle) * c * 0.86, c + math.sin(angle) * c * 0.86), fill=(255, 255, 255, 160), width=2)
    circle(c * 0.12, 4)
    glow = img.filter(ImageFilter.GaussianBlur(5))
    base = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    base.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.7)))
    return Image.alpha_composite(base, img)


def glow(size=128):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    half = size / 2
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - half + 0.5, y - half + 0.5) / half
            a = max(0.0, 1.0 - r) ** 2
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in (("ring", ring()), ("scorch", scorch()), ("cracks", cracks()), ("rune_circle", rune_circle()), ("glow", glow())):
        image.save(OUT / f"{name}.png")
        print("wrote", OUT / f"{name}.png")
        if name != "scorch":
            emission = Image.new("RGB", image.size, (0, 0, 0))
            emission.paste(image.convert("RGB"), mask=image.getchannel("A"))
            emission.save(OUT / f"{name}_emission.png")
            print("wrote", OUT / f"{name}_emission.png")


if __name__ == "__main__":
    main()
