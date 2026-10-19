"""Phase 7 props, modelled with bpy (Blender 5.2, background mode).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
        --python tools/build_phase7_props.py -- [prop ...]

Writes the editable source to assets/blender/phase7/<prop>.blend and the game export to
assets/generated/phase7/<prop>.glb. Flat stylized materials (no textures), metre scale, origin
on the ground at the prop's footprint centre. The prop's front faces Blender -Y, which the glTF
exporter turns into Godot +Z.

Props:
  courier_guild_board   the Courier Guild quest notice board (Phase 7, task 1)
  garden_bed            a raised plank garden bed with furrowed soil (Phase 7 farming)
  crop_seedling         a two-leaf seedling, a crop's first growth stage (Phase 7 farming)
"""
import math
import os
import random
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BLEND_DIR = os.path.join(ROOT, "assets", "blender", "phase7")
GLB_DIR = os.path.join(ROOT, "assets", "generated", "phase7")

_materials = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()


def mat(name, color, rough=0.8, metal=0.0, emit=None):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.5
    _materials[name] = m
    return m


def _finish(obj, material, rot, bevel):
    obj.rotation_euler = [math.radians(a) for a in rot]
    if material is not None:
        obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "NONE"
    return obj


def box(name, size, loc, material, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, material, rot, bevel)


def cyl(name, radius, depth, loc, material, rot=(0, 0, 0), verts=12, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, material, rot, bevel)


def cone(name, r1, r2, depth, loc, material, rot=(0, 0, 0), verts=8):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, material, rot, 0.0)


def join(name):
    """Joins every mesh object into one (one mesh with several materials), applying modifiers."""
    bpy.ops.object.select_all(action="SELECT")
    meshes = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    for o in meshes:
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    # Bake every part's transform first, so the joined mesh has its origin at the world
    # origin (the prop's footprint centre) and no leftover rotation from the first part.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.shade_flat()
    return obj


def export(prop):
    os.makedirs(BLEND_DIR, exist_ok=True)
    os.makedirs(GLB_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, prop + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(GLB_DIR, prop + ".glb"), export_format="GLB",
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    print("EXPORTED %s triangles=%d" % (prop, tris))


# --- Courier Guild quest board -----------------------------------------------------------

def courier_guild_board():
    reset()
    rng = random.Random(7)
    wood_dark = mat("WoodDark", (0.27, 0.16, 0.09))
    wood = mat("Wood", (0.42, 0.26, 0.14))
    wood_light = mat("WoodLight", (0.56, 0.38, 0.21))
    shingle = mat("Shingle", (0.44, 0.17, 0.11))
    shingle_dark = mat("ShingleDark", (0.33, 0.12, 0.08))
    stone = mat("Stone", (0.47, 0.47, 0.49), rough=0.95)
    parchment = mat("Parchment", (0.93, 0.85, 0.66))
    parchment_old = mat("ParchmentOld", (0.85, 0.74, 0.52))
    ink = mat("Ink", (0.17, 0.12, 0.10))
    wax = mat("Wax", (0.62, 0.07, 0.08), rough=0.4)
    brass = mat("Brass", (0.86, 0.64, 0.24), rough=0.35, metal=0.8)
    iron = mat("Iron", (0.22, 0.22, 0.24), rough=0.5, metal=0.7)
    guild_blue = mat("GuildBlue", (0.12, 0.20, 0.44), rough=0.6)
    feather = mat("Feather", (0.95, 0.94, 0.90))

    front = -1.0  # Blender -Y is the board's front.
    # Footings and posts.
    for x in (-1.0, 1.0):
        box("Footing", (0.36, 0.36, 0.22), (x, 0, 0.11), stone, rot=(0, 0, rng.uniform(-6, 6)), bevel=0.03)
        box("Post", (0.16, 0.16, 2.55), (x, 0, 1.38), wood_dark, bevel=0.02)
        box("PostCap", (0.2, 0.2, 0.06), (x, 0, 2.66), wood, bevel=0.01)
        # Diagonal braces under the board.
        box("Brace", (0.06, 0.08, 0.5), (x * 0.82, 0.02, 0.62), wood_dark, rot=(0, x * -35, 0), bevel=0.008)
    # Back panel of vertical planks with varied tone and small gaps.
    board_w, board_h, board_z = 1.8, 1.2, 1.45
    planks = 7
    for i in range(planks):
        px = -board_w / 2 + (i + 0.5) * board_w / planks
        tone = (wood, wood_light, wood)[i % 3]
        box("Plank", (board_w / planks - 0.012, 0.05, board_h + rng.uniform(-0.02, 0.02)), (px, 0.02, board_z), tone, bevel=0.006)
    # Frame.
    box("FrameTop", (board_w + 0.16, 0.09, 0.1), (0, -0.02, board_z + board_h / 2 + 0.04), wood_dark, bevel=0.012)
    box("FrameBottom", (board_w + 0.16, 0.09, 0.1), (0, -0.02, board_z - board_h / 2 - 0.04), wood_dark, bevel=0.012)
    box("Ledge", (board_w + 0.1, 0.2, 0.04), (0, -0.1, board_z - board_h / 2 - 0.1), wood, bevel=0.008)
    for x in (-1, 1):
        box("FrameSide", (0.09, 0.09, board_h + 0.12), (x * (board_w / 2 + 0.04), -0.02, board_z), wood_dark, bevel=0.012)
    # Brass corner plates.
    for x in (-1, 1):
        for z in (-1, 1):
            box("Corner", (0.1, 0.02, 0.1), (x * (board_w / 2 + 0.02), -0.075, board_z + z * (board_h / 2 + 0.02)), brass, rot=(0, 45, 0))
    # Pinned notices: parchment, written lines, wax seal or iron pin.
    notices = [(-0.6, 1.72, 0.36, 0.42, 4), (-0.15, 1.78, 0.32, 0.38, -6), (0.33, 1.7, 0.38, 0.46, 3),
               (0.7, 1.5, 0.26, 0.34, -9), (-0.52, 1.18, 0.4, 0.34, -3), (0.05, 1.2, 0.3, 0.4, 7), (0.5, 1.12, 0.34, 0.3, -2)]
    for i, (x, z, w, h, tilt) in enumerate(notices):
        paper = parchment if i % 3 else parchment_old
        y = -0.03 - 0.004 * i
        box("Notice", (w, 0.006, h), (x, y, z), paper, rot=(0, tilt, 0))
        # Folded corner.
        box("NoticeCorner", (0.06, 0.006, 0.06), (x + w * 0.42, y - 0.006, z - h * 0.42), parchment_old, rot=(0, tilt + 45, 0))
        lines = int(h / 0.07)
        for j in range(lines - 1):
            lw = w * rng.uniform(0.45, 0.78)
            lz = z + h / 2 - 0.09 - j * 0.06
            off = -w / 2 + 0.05 + lw / 2
            box("Line", (lw, 0.004, 0.012), (x + off * math.cos(math.radians(tilt)), y - 0.005, lz - off * math.sin(math.radians(tilt))), ink, rot=(0, tilt, 0))
        if i % 2 == 0:
            cyl("Seal", 0.035, 0.012, (x, y - 0.01, z - h / 2 + 0.06), wax, rot=(90, 0, 0), verts=10)
        cyl("Pin", 0.014, 0.03, (x, y - 0.015, z + h / 2 - 0.035), iron, rot=(90, 0, 0), verts=6)
    # A rolled scroll and a quill pot on the ledge.
    cyl("Scroll", 0.035, 0.42, (-0.45, -0.12, board_z - board_h / 2 - 0.045), parchment, rot=(0, 90, 8), verts=10)
    cyl("ScrollTie", 0.038, 0.03, (-0.45, -0.12, board_z - board_h / 2 - 0.045), wax, rot=(0, 90, 8), verts=10)
    cyl("InkPot", 0.05, 0.07, (0.62, -0.12, board_z - board_h / 2 - 0.045), ink, verts=10)
    box("Quill", (0.02, 0.006, 0.26), (0.66, -0.12, board_z - board_h / 2 + 0.07), feather, rot=(0, 20, 0))
    # Gable roof of overlapping shingle rows over a ridge beam.
    roof_z, roof_w, slope = 2.66, 2.55, 30
    box("Ridge", (roof_w + 0.1, 0.1, 0.1), (0, 0, roof_z + 0.3), wood_dark, bevel=0.01)
    for side in (-1, 1):
        for row in range(3):
            depth = 0.26
            dy = side * (0.12 + row * 0.2)
            dz = roof_z + 0.28 - row * 0.115
            tone = shingle if row % 2 == 0 else shingle_dark
            box("Shingles", (roof_w - row * 0.02, depth, 0.035), (0, dy, dz), tone, rot=(-side * slope, 0, 0), bevel=0.006)
    # Header plank under the eave with the Courier Guild emblem: a winged envelope on a blue
    # plaque ringed in brass (under the eave so the iso camera sees it).
    plaque_z = board_z + board_h / 2 + 0.24
    box("Header", (1.1, 0.06, 0.2), (0, front * 0.06, plaque_z), wood, bevel=0.01)
    cyl("PlaqueRim", 0.2, 0.04, (0, front * 0.1, plaque_z), brass, rot=(90, 0, 0), verts=20)
    cyl("Plaque", 0.17, 0.045, (0, front * 0.115, plaque_z), guild_blue, rot=(90, 0, 0), verts=20)
    box("Envelope", (0.15, 0.02, 0.1), (0, front * 0.145, plaque_z), parchment)
    box("FlapL", (0.09, 0.012, 0.012), (-0.035, front * 0.157, plaque_z + 0.018), wax, rot=(0, 30, 0))
    box("FlapR", (0.09, 0.012, 0.012), (0.035, front * 0.157, plaque_z + 0.018), wax, rot=(0, -30, 0))
    for side in (-1, 1):
        for k in range(3):
            box("Wing", (0.12 - k * 0.025, 0.012, 0.028), (side * (0.24 + k * 0.012), front * 0.1, plaque_z + 0.03 - k * 0.032), brass, rot=(0, side * (-20 + k * 18), 0))
    # Hanging lantern on the right post.
    box("LanternArm", (0.3, 0.04, 0.04), (1.12, 0, 2.25), iron)
    cyl("LanternTop", 0.08, 0.05, (1.24, 0, 2.15), iron, verts=8)
    cyl("LanternGlass", 0.06, 0.14, (1.24, 0, 2.05), mat("LanternGlow", (1.0, 0.78, 0.4), rough=0.3, emit=(1.0, 0.6, 0.25)), verts=8)
    cyl("LanternBase", 0.075, 0.03, (1.24, 0, 1.97), iron, verts=8)
    join("CourierGuildBoard")
    export("courier_guild_board")


# --- Garden bed and seedling (farming) ----------------------------------------------------

BED_X, BED_Z = 2.0, 1.6     # outer footprint (Godot X by Z); Blender X by Y
BED_H = 0.3


def garden_bed():
    reset()
    rng = random.Random(11)
    planks = [mat("BedPlank%d" % i, c) for i, c in enumerate([(0.45, 0.29, 0.16), (0.40, 0.25, 0.13), (0.50, 0.33, 0.19)])]
    post = mat("BedPost", (0.30, 0.19, 0.10))
    soil = mat("Soil", (0.24, 0.15, 0.09), rough=1.0)
    ridge = mat("SoilRidge", (0.31, 0.20, 0.12), rough=1.0)
    straw = mat("Straw", (0.78, 0.66, 0.36))
    hx, hy, t = BED_X / 2, BED_Z / 2, 0.07
    board_h = BED_H / 2
    for level in range(2):
        z = board_h * (level + 0.5)
        for sy in (-1, 1):
            box("PlankX", (BED_X, t, board_h - 0.01), (0, sy * (hy - t / 2), z), planks[rng.randrange(3)], bevel=0.01,
                rot=(0, rng.uniform(-0.6, 0.6), 0))
        for sx in (-1, 1):
            box("PlankY", (t, BED_Z - 2 * t, board_h - 0.01), (sx * (hx - t / 2), 0, z), planks[rng.randrange(3)], bevel=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Post", (0.1, 0.1, BED_H + 0.1), (sx * (hx - 0.03), sy * (hy - 0.03), (BED_H + 0.1) / 2), post, bevel=0.015)
            box("PostCap", (0.13, 0.13, 0.03), (sx * (hx - 0.03), sy * (hy - 0.03), BED_H + 0.11), planks[0], bevel=0.008)
    inner_x, inner_y = BED_X - 2 * t, BED_Z - 2 * t
    box("Soil", (inner_x, inner_y, 0.05), (0, 0, BED_H - 0.06), soil)
    # Three furrows along X: the crops stand on the ridges (FarmPlot.CROP_SPOTS).
    for row in (-1, 0, 1):
        y = row * inner_y / 3
        box("Ridge", (inner_x - 0.08, inner_y / 3 * 0.55, 0.05), (0, y, BED_H - 0.02), ridge, bevel=0.02)
    for i in range(10):
        x = rng.uniform(-inner_x / 2 + 0.1, inner_x / 2 - 0.1)
        y = rng.uniform(-inner_y / 2 + 0.05, inner_y / 2 - 0.05)
        box("Straw", (0.12, 0.012, 0.012), (x, y, BED_H + 0.005), straw, rot=(0, 0, rng.uniform(0, 180)))
    join("GardenBed")
    export("garden_bed")


def crop_seedling():
    reset()
    stem = mat("Stem", (0.33, 0.55, 0.18))
    leaf = mat("Leaf", (0.42, 0.70, 0.24))
    cyl("Stem", 0.012, 0.14, (0, 0, 0.07), stem, verts=6)
    for side in (-1, 1):
        box("Leaf", (0.09, 0.04, 0.01), (side * 0.045, 0, 0.13), leaf, rot=(0, side * -25, 0), bevel=0.008)
    box("Bud", (0.03, 0.03, 0.04), (0, 0, 0.16), leaf, bevel=0.01)
    join("Seedling")
    export("crop_seedling")


PROPS = {"courier_guild_board": courier_guild_board, "garden_bed": garden_bed, "crop_seedling": crop_seedling}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(PROPS):
        PROPS[name]()
