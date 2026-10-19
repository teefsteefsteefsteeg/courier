"""Builds the weapon enhancement effect sheets (Phase 7) from the Super Pixel Effects Gigapack.

    python tools/prep_enhancement_vfx.py

Reads the pack as downloaded (assets/Super Pixel Effects Gigapack (Free Version)/, not
committed; "Super Pixel Effects Gigapack - Will Tice / unTied Games", bundling in a game is
allowed, credit required) and writes to assets/vfx/enhancement/:
  sparkle.png  Status Effect: Sparkling 001 (96 px frames)
  aura.png     Lightning Aura 002 (96 px frames)
  burst.png    Round Sparkle Burst 001 (64 px frames)
  impact.png   Symmetrical Impact 001 (hit flash for melee and arrows)
Phase 8 tier effects (EnhancementGlow, AttackEffects), one look per enhancement level:
  spark.png      Sci-fi Spark Burst 001 (+1 silver sparks; whitened)
  nature_burst.png  Round Sparkle Burst 002 (+2 green nature bloom; own colours)
  swirl.png      Spell Absorb 001 (+3 water swirl; whitened)
  bubbles.png    Directional Bubble Burst 001 (+3 droplets; whitened)
  splash.png     Burst Splatter 001 (+3 water impact; whitened)
  bolt_flash.png Lightning Burst 001 (+4 attack flash; own violet colours)
  strike.png     Lightning Strike 001 (+4 electric impact; own colours)
  flame.png      Fire Looping 003A (+5 flames; own orange colours)
  flame_b.png    Fire Looping 004A (+5 flames, second shape; own colours)
  blast.png      Stylized Explosion 001 (+5 impact burst; own colours)
Each is re-packed as a single row of frames. Whitened sheets (colour from luminance, alpha
kept) are tinted per level by VfxStrip; the others keep the pack's colours.
frames.json lists frame size and count; every animation plays at 15 FPS (the pack's guide).
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "assets/Super Pixel Effects Gigapack (Free Version)/spritesheet"
OUT = ROOT / "assets/vfx/enhancement"
SHEETS = {
    "sparkle": "Fantasy Spells/status_sparkling_001/status_sparkling_001_large_yellow",
    "aura": "Lightning/lightning_aura_002/lightning_aura_002_large_blue",
    "burst": "Magic Bursts/round_sparkle_burst_001/round_sparkle_burst_001_large_blue",
    "impact": "Impacts/symmetrical_impact_001/symmetrical_impact_001_large_yellow",
    "spark": "Sci-fi/scifi_spark_burst_001/scifi_spark_burst_001_large_yellow",
    "nature_burst": "Magic Bursts/round_sparkle_burst_002/round_sparkle_burst_002_large_green",
    "swirl": "Fantasy Spells/spell_absorb_001/spell_absorb_001_large_violet",
    "bubbles": "Magic Bursts/directional_bubble_burst_001/directional_bubble_burst_001_large_green",
    "splash": "Splatters/burst_splatter_001/burst_splatter_001_large_red",
    "bolt_flash": "Lightning/lightning_burst_001/lightning_burst_001_large_violet",
    "strike": "Lightning/lightning_strike_001/lightning_strike_001_large_violet",
    "flame": "Fire/fire_looping_003A/fire_looping_003A_large_orange",
    "flame_b": "Fire/fire_looping_004A/fire_looping_004A_large_orange",
    "blast": "Explosions/stylized_explosion_001/stylized_explosion_001_large_yellow",
}
## Sheets that keep the pack's own colours (not whitened for tinting).
KEEP_COLOUR = {"nature_burst", "bolt_flash", "strike", "flame", "flame_b", "blast"}


def frames(folder):
    """(x, y, w, h) of every frame, from the pack's spritesheet.txt."""
    out = []
    for line in (PACK / folder / "spritesheet.txt").read_text().splitlines():
        if "=" in line:
            out.append(tuple(int(v) for v in line.split("=")[1].split()))
    return out


def whiten(image):
    """Keeps the shape and alpha, makes the colour a brightness ramp of white."""
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            lum = max(r, g, b)
            v = int(160 + 95 * lum / 255)
            pixels[x, y] = (v, v, v, a)
    return image


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {}
    for name, folder in SHEETS.items():
        sheet = Image.open(PACK / folder / "spritesheet.png").convert("RGBA")
        boxes = frames(folder)
        w, h = boxes[0][2], boxes[0][3]
        strip = Image.new("RGBA", (w * len(boxes), h))
        for i, (x, y, fw, fh) in enumerate(boxes):
            strip.paste(sheet.crop((x, y, x + fw, y + fh)), (i * w, 0))
        (strip if name in KEEP_COLOUR else whiten(strip)).save(OUT / f"{name}.png")
        meta[name] = {"frame_width": w, "frame_height": h, "frames": len(boxes), "fps": 15, "tinted": name not in KEEP_COLOUR}
    (OUT / "frames.json").write_text(json.dumps(meta, indent=1) + "\n")
    print("wrote", ", ".join(f"{k} ({v['frames']} frames)" for k, v in meta.items()))


if __name__ == "__main__":
    main()
