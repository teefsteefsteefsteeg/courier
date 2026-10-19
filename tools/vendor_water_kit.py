"""Vendors the water shader sample used by Wyrmfall Vale (Phase 8).

    python tools/vendor_water_kit.py

Source: assets/waternature/ (the user's download, a separate Godot project, not committed):
"Godot Water Shader Kit - Free Sample" by REEBOO Labs. Its licence allows use and
modification in commercial and non-commercial games; the files may not be redistributed
as-is or as an asset pack. Copies the lake shader, its include, the four seamless textures
and the two pond presets to assets/vfx/water_kit/, rewriting res://addons/water_kit/ paths.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/waternature/addons/water_kit"
OUT = ROOT / "assets/vfx/water_kit"
FILES = [
    "shaders/lake.gdshader", "shaders/water_common.gdshaderinc",
    "textures/caustics.png", "textures/foam.png", "textures/water_normal_a.png", "textures/water_normal_b.png",
    "presets/lake/pond_clear.tres", "presets/lake/pond_toon.tres",
]
TEXT = {".gdshader", ".gdshaderinc", ".tres"}


def main():
    for rel in FILES:
        source = SRC / rel
        target = OUT / rel.replace("presets/lake/", "presets/")
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix in TEXT:
            text = source.read_text(encoding="utf-8").replace("res://addons/water_kit/presets/lake/", "res://assets/vfx/water_kit/presets/")
            text = text.replace("res://addons/water_kit/", "res://assets/vfx/water_kit/")
            # Drop uids: the copies are new resources.
            text = "\n".join(line for line in text.splitlines() if not line.startswith("uid=")).replace(' uid="', ' _uid="')
            text = "\n".join(_strip_uid(line) for line in text.splitlines()) + "\n"
            target.write_text(text, encoding="utf-8")
        else:
            target.write_bytes(source.read_bytes())
    (OUT / "LICENSE.txt").write_text((ROOT / "assets/waternature/LICENSE.txt").read_text(encoding="utf-8"), encoding="utf-8")
    print("vendored", len(FILES), "files to", OUT)


def _strip_uid(line):
    if ' _uid="' in line:
        start = line.index(' _uid="')
        end = line.index('"', start + 7) + 1
        return line[:start] + line[end:]
    return line


if __name__ == "__main__":
    main()
