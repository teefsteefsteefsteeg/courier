"""Copies the Quaternius Fantasy Props MegaKit models used by the Phase 8 interiors.

    python tools/copy_fantasy_props.py

Source: assets/newmap/fantasy/Exports/glTF/ (the user's download, not committed; CC0,
"Fantasy Props MegaKit [Standard]" by Quaternius). Writes each model's .gltf and .bin, plus
every texture it references, to assets/models/fantasy_props/ (committed). Textures are
downscaled to at most 1024 px (the shared 2048-4096 px trims are far more than the iso camera
needs, and keep the repository light).
"""
import json
import shutil

from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/newmap/fantasy/Exports/glTF"
TEXTURES = ROOT / "assets/newmap/fantasy/Textures"
OUT = ROOT / "assets/models/fantasy_props"
MAX_TEXTURE = 1024
MODELS = [
    "Bed_Twin1", "Nightstand_Shelf", "Table_Large", "Chair_1", "Stool", "Bench", "Bookcase_2",
    "Cabinet", "Chandelier", "CandleStick_Triple", "Candle_1", "Anvil", "Workbench",
    "Workbench_Drawers", "WeaponStand", "Barrel", "Crate_Wooden", "Chest_Wood", "Shelf_Simple",
    "Shelf_Small_Bottles", "Scroll_1", "Book_Stack_1", "BookStand", "Lantern_Wall", "Pot_1",
    "Cauldron", "Mug", "Coin_Pile", "Dummy", "Peg_Rack", "Banner_1", "Whetstone", "Torch_Metal",
    "Vase_2", "Table_Plate", "Shield_Wooden", "Sword_Bronze", "Bag",
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = set()
    for name in MODELS:
        gltf = SRC / f"{name}.gltf"
        data = json.loads(gltf.read_text(encoding="utf-8"))
        shutil.copy2(gltf, OUT / gltf.name)
        for buffer in data.get("buffers", []):
            shutil.copy2(SRC / buffer["uri"], OUT / buffer["uri"])
        for image in data.get("images", []):
            images.add(image["uri"])
    for uri in sorted(images):
        source = SRC / uri if (SRC / uri).exists() else TEXTURES / uri
        image = Image.open(source)
        if max(image.size) > MAX_TEXTURE:
            image = image.resize((MAX_TEXTURE, MAX_TEXTURE), Image.LANCZOS)
        image.save(OUT / uri, optimize=True)
    print(f"copied {len(MODELS)} models and {len(images)} textures to {OUT}")


if __name__ == "__main__":
    main()
