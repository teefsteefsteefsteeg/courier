"""Crops the inventory window pieces (Phase 7) from the Humble Pixel inventory UI pack.

    python tools/prep_inventory_ui.py

Reads assets/inventory/ (the pack as downloaded; licence: use and modify in this game, no
redistribution of the pack) and writes the pieces EquipmentUI uses to assets/ui/inventory/:
frame.png (dark slate window frame), parchment.png (page), tab_on.png / tab_off.png (round
side tabs), icon_tools.png (crossed tools), slot.png / slot_selected.png (round item holders),
button.png / button_hover.png (pill buttons), header.png (pill title bar).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "assets/inventory"
OUT = ROOT / "assets/ui/inventory"
SHEET_BOXES = {  # (x0, y0, x1, y1) in SpriteSheet.png pixels; trimmed to their content
    "frame": (1545, 1982, 2001, 2336),
    "parchment": (731, 2001, 1052, 2312),
}
SPRITES = {
    "tab_on": "Side Tabs/1.png",
    "tab_off": "Side Tabs/0.png",
    "icon_tools": "Side Tabs/8.png",
    "icon_bag": "Side Tabs/5.png",
    "slot": "Holders/3.png",
    "slot_selected": "Holders/4.png",
    "button": "Buttons/12.png",
    "button_hover": "Buttons/13.png",
    "button_outline": "Buttons/11.png",
    "header": "Holders/14.png",
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(PACK / "PNG SpriteSheet/SpriteSheet.png").convert("RGBA")
    for name, box in SHEET_BOXES.items():
        piece = sheet.crop(box)
        piece.crop(piece.getbbox()).save(OUT / f"{name}.png")
    for name, rel in SPRITES.items():
        Image.open(PACK / "Sprites/Content" / rel).convert("RGBA").save(OUT / f"{name}.png")
    print("wrote", len(SHEET_BOXES) + len(SPRITES), "pieces to", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
