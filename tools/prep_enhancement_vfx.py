"""Builds the weapon enhancement effect sheets (Phase 7) from the Super Pixel Effects Gigapack.

    python tools/prep_enhancement_vfx.py

Reads the pack as downloaded (assets/Super Pixel Effects Gigapack (Free Version)/, not
committed; "Super Pixel Effects Gigapack - Will Tice / unTied Games", bundling in a game is
allowed, credit required) and writes to assets/vfx/enhancement/:
  sparkle.png  Status Effect: Sparkling 001 (96 px frames)
  aura.png     Lightning Aura 002 (96 px frames)
  burst.png    Round Sparkle Burst 001 (64 px frames)
  impact.png   Symmetrical Impact 001 (hit flash for melee and arrows)
Each is re-packed as a single row of frames and whitened (colour from luminance, alpha kept) so
EnhancementVfx can tint it per level (+1 silver, +2 green, +3 blue, +4 purple, +5 gold).
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
}


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
        whiten(strip).save(OUT / f"{name}.png")
        meta[name] = {"frame_width": w, "frame_height": h, "frames": len(boxes), "fps": 15}
    (OUT / "frames.json").write_text(json.dumps(meta, indent=1) + "\n")
    print("wrote", ", ".join(f"{k} ({v['frames']} frames)" for k, v in meta.items()))


if __name__ == "__main__":
    main()
