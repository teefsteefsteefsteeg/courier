"""Vendors the Binbun Stylized Status FX and Battle FX (both CC0, Binbun3D) into the game.

    python tools/vendor_binbun_vfx.py

The packs as downloaded (assets/StatusFXFree/, assets/bossEffect/BattleFXFree/, not committed)
expect to live at res://assets/BinbunVFX_Vol2/, so their scenes do not load where they are, and
both carry the same shared scripts (class_name VFXEmitterBB, VFXControllerBB, ...). This copies
the effects, shaders and scripts into assets/vfx/BinbunVFX_Vol2/ with every res:// path
repaired and the packs' uids dropped (Godot assigns new ones), and puts a .gdignore in both raw
folders so their duplicate classes are not registered.
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/vfx/BinbunVFX_Vol2"
PACKS = [ROOT / "assets/StatusFXFree/assets/BinbunVFX_Vol2", ROOT / "assets/bossEffect/BattleFXFree/assets/BinbunVFX_Vol2"]
RAW_ROOTS = [ROOT / "assets/StatusFXFree", ROOT / "assets/bossEffect"]
KEEP = [
    "shared/script", "shared/shader/checker.gdshader",
    "StatusFX/shader", "StatusFX/script", "StatusFX/effects", "StatusFX/license.txt",
    "BattleFX/shader", "BattleFX/script", "BattleFX/effects", "BattleFX/icons", "BattleFX/license.txt",
]
TEXT = {".gd", ".tscn", ".tres", ".gdshader", ".txt"}


def repair(text):
    text = text.replace("res://assets/BinbunVFX_Vol2/", "res://assets/vfx/BinbunVFX_Vol2/")
    return re.sub(r' uid="uid://[a-z0-9]+"', "", text)


def main():
    copied = 0
    for pack in PACKS:
        for rel in KEEP:
            source = pack / rel
            if not source.exists():
                continue
            files = [source] if source.is_file() else [p for p in source.rglob("*") if p.is_file()]
            for path in files:
                if path.suffix in (".uid", ".import"):
                    continue
                target = OUT / path.relative_to(pack)
                target.parent.mkdir(parents=True, exist_ok=True)
                if path.suffix in TEXT:
                    target.write_text(repair(path.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
                else:
                    shutil.copyfile(path, target)
                copied += 1
    for raw in RAW_ROOTS:
        if raw.exists():
            (raw / ".gdignore").write_text("", encoding="utf-8")
    print("vendored", copied, "files to", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
