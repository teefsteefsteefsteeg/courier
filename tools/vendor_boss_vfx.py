"""Vendors the effects of the Wyrmfall dragon fight (Phase 8).

    python tools/vendor_boss_vfx.py

Sources (the user's downloads, not committed):
- assets/brackeys_vfx_bundle/flipbooks/ (Brackeys VFX bundle, CC0; flipbooks by Thomas
  Iche): fire_01 (8x8), explosion_01 (8x8), wispy_smoke_01 (8x8), converted to PNG at
  512 px -> assets/vfx/boss/{fire,explosion,smoke}_8x8.png.
- assets/bossEffect/tornado/ (owner-supplied "bossEffect" Godot sample, no licence file):
  the vortex scene (node_3d.tscn), its visual shader (whiteT.tres), two vortex meshes
  (.obj) and three noise textures -> assets/vfx/boss_tornado/, res:// paths rewritten and
  uids dropped (the sample was its own project). TGA noises become PNG.
"""
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRACKEYS = ROOT / "assets/brackeys_vfx_bundle/flipbooks"
TORNADO = ROOT / "assets/bossEffect/tornado"
OUT_BOSS = ROOT / "assets/vfx/boss"
OUT_TORNADO = ROOT / "assets/vfx/boss_tornado"
FLIPBOOKS = {"fire_01_8x8.tga": "fire_8x8.png", "explosion_01_8x8.tga": "explosion_8x8.png", "wispy_smoke_01_8x8.tga": "smoke_8x8.png"}
NOISES = {"FireNoise1.tga": "fire_noise.png", "Noise_17.tga": "noise_17.png", "Noise_18.tga": "noise_18.png"}


def main():
    OUT_BOSS.mkdir(parents=True, exist_ok=True)
    OUT_TORNADO.mkdir(parents=True, exist_ok=True)
    for source, target in FLIPBOOKS.items():
        original = Image.open(BRACKEYS / source)
        image = original.convert("RGBA")
        if original.mode == "RGB":
            # Fire on black: brightness becomes alpha, so it also works with alpha blending.
            image.putalpha(original.convert("L").point(lambda v: min(255, v * 2)))
        image.resize((512, 512), Image.LANCZOS).save(OUT_BOSS / target)
    for source, target in NOISES.items():
        Image.open(TORNADO / source).save(OUT_TORNADO / target)
    for name in ["tornado.obj", "tornado2.obj"]:
        # The sample has no .mtl files; drop the references so the import is clean.
        lines = (TORNADO / name).read_text(encoding="utf-8").splitlines()
        kept = [line for line in lines if not line.startswith(("mtllib", "usemtl"))]
        (OUT_TORNADO / name).write_text("\n".join(kept) + "\n", encoding="utf-8")
    shader = (TORNADO / "whiteT.tres").read_text(encoding="utf-8")
    (OUT_TORNADO / "vortex_shader.tres").write_text(_rewrite(shader), encoding="utf-8")
    scene = (TORNADO / "node_3d.tscn").read_text(encoding="utf-8")
    (OUT_TORNADO / "vortex.tscn").write_text(_rewrite(scene), encoding="utf-8")
    print("vendored boss vfx")


def _rewrite(text):
    text = re.sub(r' uid="uid://[a-z0-9]+"', "", text)
    text = text.replace("res://whiteT.tres", "res://assets/vfx/boss_tornado/vortex_shader.tres")
    for name in ["tornado.obj", "tornado2.obj"]:
        text = text.replace("res://" + name, "res://assets/vfx/boss_tornado/" + name)
    for source, target in NOISES.items():
        text = text.replace("res://" + source, "res://assets/vfx/boss_tornado/" + target)
    return text


if __name__ == "__main__":
    main()
