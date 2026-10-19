"""Vendors Binbun's Magic Projectiles (CC0, Binbun3D) for the +5 weapon ultimates (Phase 8).

    python tools/vendor_binbun_projectiles.py

The pack as downloaded (assets/BinbunVFX/, not committed) expects to live at
res://assets/BinbunVFX/. This copies its projectile effects (basic, javelin, wave), their
materials and the shared scripts, shaders and noise/gradient textures to
assets/vfx/BinbunVFX_Magic/ with every res:// path repaired and the uids dropped, and puts a
.gdignore in the raw folder so its classes (VFXController, VFX_Light) are registered once.
Used by scripts/combat/weapon_ultimates.gd: the wave (sword Flame Slash), basic (staff
Arcane Storm bolts) and javelin (bow Thunder Arrow).
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "assets/BinbunVFX"
OUT = ROOT / "assets/vfx/BinbunVFX_Magic"
KEEP = ["magic_projectiles/effects", "magic_projectiles/src/materials", "shared/script", "shared/shader", "shared/texture"]
TEXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc"}
SKIP = {".import", ".ptex", ".uid"}


def repair(text):
    text = text.replace("res://assets/BinbunVFX/", "res://assets/vfx/BinbunVFX_Magic/")
    text = re.sub(r' uid="uid://[a-z0-9]+"', "", text)
    return re.sub(r'\nmetadata/_custom_type_script = "uid://[a-z0-9]+"', "", text)


def main():
    copied = 0
    for rel in KEEP:
        for source in (RAW / rel).rglob("*"):
            if not source.is_file() or source.suffix in SKIP:
                continue
            target = OUT / source.relative_to(RAW)
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.suffix in TEXT:
                target.write_text(repair(source.read_text(encoding="utf-8")), encoding="utf-8")
            else:
                shutil.copyfile(source, target)
            copied += 1
    (RAW / ".gdignore").write_text("", encoding="utf-8")
    print("vendored %d files" % copied)


if __name__ == "__main__":
    main()
