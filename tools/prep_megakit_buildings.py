"""Copy the Phase 5F MegaKit building pieces into the project.

Usage: python tools/prep_megakit_buildings.py "<...>/Medieval Village MegaKit[Standard]" <project root>
Writes a .gltf.import mapping each MegaKit material to its shared .tres when one is
missing; run `godot --headless --path . --import` afterwards.

glTF image/texture references are stripped (the project maps every MegaKit
material to a shared .tres in assets/materials/buildings), and the textures
those materials use are downsized into assets/textures/buildings.
"""
import json, os, shutil, sys
from PIL import Image, ImageOps, ImageEnhance

SRC = sys.argv[1]   # ".../Medieval Village MegaKit[Standard]"
DST = sys.argv[2]   # project root
PIECES = """
Wall_Plaster_Straight Wall_Plaster_Straight_Base Wall_Plaster_WoodGrid Wall_Plaster_Door_Round
Wall_Plaster_Window_Wide_Round Wall_Plaster_Window_Thin_Round
Wall_UnevenBrick_Straight Wall_UnevenBrick_Door_Round Wall_UnevenBrick_Door_Flat Wall_UnevenBrick_Window_Wide_Round
Wall_UnevenBrick_Window_Wide_Flat Wall_UnevenBrick_Window_Thin_Round Wall_Arch
Corner_Exterior_Wood Corner_Exterior_Brick
Door_1_Round Door_8_Flat
Window_Wide_Round1 Window_Wide_Flat1 Window_Thin_Round1
WindowShutters_Wide_Round_Open WindowShutters_Wide_Flat_Open WindowShutters_Thin_Round_Open WindowShutters_Thin_Round_Closed
Roof_RoundTiles_4x4 Roof_RoundTiles_4x6 Roof_RoundTiles_6x6 Roof_Tower_RoundTiles
Roof_Dormer_RoundTile Roof_Front_Brick4 Roof_Front_Brick6 Roof_Wooden_2x1
Prop_Chimney Prop_Chimney2 Prop_Support Balcony_Cross_Straight Balcony_Simple_Straight Floor_WoodDark
""".split()
# MegaKit material -> shared material in assets/materials/buildings.
MATERIALS = {
    "MI_WoodTrim": "timber", "MI_WoodTrim_Wear": "planks", "MI_Plaster": "plaster", "MI_RoundTiles": "roof_tiles",
    "MI_RockTrim": "stone", "MI_UnevenBrick": "uneven_brick", "MI_Brick": "brick", "MI_MetalOrnaments": "iron",
    "MI_WindowGlass": "windows",
}
IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
_subresources={
"materials": {
%s
}
}
"""
# texture -> (max size, desaturate)
TEXTURES = {
    "T_WoodTrim_BaseColor": (1024, False), "T_WoodTrim_Normal": (1024, False), "T_WoodTrim_Roughness": (512, False),
    "T_Plaster_BaseColor": (1024, False), "T_Plaster_Normal": (1024, False), "T_Plaster_ORM": (512, False),
    "T_RoundTiles_BaseColor": (1024, True), "T_RoundTiles_Normal": (1024, False), "T_RoundTiles_Roughness": (512, False),
    "T_UnevenBrick_BaseColor": (1024, False), "T_UnevenBrick_Normal": (1024, False), "T_UnevenBrick_Roughness": (512, False),
    "T_RockTrim_BaseColor": (1024, False), "T_RockTrim_Normal": (1024, False), "T_RockTrim_ORM": (512, False),
    "T_Brick_BaseColor": (1024, False), "T_Brick_Normal": (1024, False), "T_Brick_Roughness": (512, False),
    "T_MetalOrnaments_BaseColor": (512, False), "T_MetalOrnaments_Roughness": (512, False),
}

models = os.path.join(DST, "assets/models/megakit/buildings")
textures = os.path.join(DST, "assets/textures/buildings")
os.makedirs(models, exist_ok=True)
os.makedirs(textures, exist_ok=True)
shutil.copy(os.path.join(SRC, "License_Standard.txt"), models)
materials = set()
for name in PIECES:
    with open(os.path.join(SRC, "glTF", name + ".gltf")) as f:
        gltf = json.load(f)
    for key in ("images", "textures", "samplers"):
        gltf.pop(key, None)
    for mat in gltf.get("materials", []):
        materials.add(mat["name"])
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            mat.pop(key, None)
        pbr = mat.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            pbr.pop(key, None)
    with open(os.path.join(models, name + ".gltf"), "w") as f:
        json.dump(gltf, f, indent=1)
    import_path = os.path.join(models, name + ".gltf.import")
    if not os.path.exists(import_path):
        entries = ",\n".join('"%s": {\n"use_external/enabled": true,\n"use_external/path": "res://assets/materials/buildings/%s.tres"\n}'
                % (key, value) for key, value in MATERIALS.items())
        with open(import_path, "w", newline="\n") as f:
            f.write(IMPORT % entries)
    for buf in gltf["buffers"]:
        shutil.copy(os.path.join(SRC, "glTF", buf["uri"]), models)
for name, (size, desaturate) in TEXTURES.items():
    path = os.path.join(SRC, "Textures", name + ".png")
    if not os.path.exists(path):
        path = os.path.join(SRC, "glTF", name + ".png")
    image = Image.open(path)
    image = image.convert("RGB")
    if desaturate:
        # Neutral tiles so MedievalBuilding.roof_color sets the hue; keep the light/dark detail.
        image = ImageEnhance.Brightness(ImageOps.grayscale(image).convert("RGB")).enhance(1.35)
    image = image.resize((size, size), Image.LANCZOS)
    image.save(os.path.join(textures, name + ".png"), optimize=True)
print(len(PIECES), "pieces; materials:", sorted(materials))
