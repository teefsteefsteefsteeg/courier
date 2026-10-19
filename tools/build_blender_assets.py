"""Mystic Courier original low-poly environment kit. Run in Blender background mode.

blender --background --factory-startup --python tools/build_blender_assets.py -- <project>
Metres, Blender Z-up; glTF converts to Godot Y-up. No external textures or dependencies.
Every output has its own editable .blend and a triangulated .glb; no vendor pack is edited.
"""
import bpy
import math
import random
import json
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else Path.cwd()
SOURCE = ROOT / 'assets/blender'
OUT = ROOT / 'assets/generated/blender'
SOURCE.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
random.seed(621)
REPORT = []


def material(name, rgb, metal=0, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = .72 if metal == 0 else .38
    p.inputs['Metallic'].default_value = metal
    p.inputs['Emission Color'].default_value = (*rgb, 1)
    p.inputs['Emission Strength'].default_value = emission
    return m


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for data in list(bpy.data.meshes):
        if data.users == 0:
            bpy.data.meshes.remove(data)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    global M
    M = {
        'stone': material('Basalt blue grey', (.24, .30, .34)),
        'edge': material('Worn limestone edges', (.43, .49, .50)),
        'dark': material('Deep slate joints', (.105, .145, .18)),
        'moss': material('Sage lichen', (.26, .36, .22)),
        'wood': material('Walnut timber', (.29, .135, .065)),
        'grain': material('Honey cut wood', (.52, .29, .115)),
        'iron': material('Forged blue iron', (.14, .20, .26), .65),
        'brass': material('Aged courier brass', (.64, .43, .16), .65),
        'rune': material('Turquoise rune inlay', (.12, .73, .66), .25, 1.7),
        'crystal': material('Amethyst facets', (.37, .18, .64), .25, .5),
        'tip': material('Lilac crystal tips', (.66, .40, .86), .15, .7),
        'flame': material('Amber flame core', (1.0, .42, .055), 0, 2.5),
        'flame_tip': material('Warm flame tips', (1.0, .77, .24), 0, 2),
        'cork': material('Rod cork', (.70, .49, .27)),
        'wrap': material('Courier blue leather', (.14, .28, .44)),
    }


def assign(o, mat):
    o.data.materials.append(M[mat])
    return o


def bevel(o, width=.025):
    mod = o.modifiers.new('Single segment hand worn chamfer', 'BEVEL')
    mod.width = width
    mod.segments = 1
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


def box(name, pos, size, mat='stone', chamfer=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(o, mat)
    if chamfer:
        bevel(o, min(chamfer, min(size) * .22))
    return o


def mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    assign(o, mat)
    return o


def rod(name, a, b, radius, mat='iron', sides=8, top=None):
    d = Vector(b) - Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius,
                                  radius2=radius if top is None else top,
                                  depth=d.length, location=(Vector(a) + Vector(b)) * .5)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return assign(o, mat)


def ring(name, pos, major, minor, mat='brass', rotation=None, count=12):
    bpy.ops.mesh.primitive_torus_add(major_segments=count, minor_segments=4,
                                   location=pos, major_radius=major, minor_radius=minor)
    o = bpy.context.object
    o.name = name
    if rotation:
        o.rotation_euler = rotation
    return assign(o, mat)


def beam(name, a, b, width, mat='wood'):
    d = Vector(b) - Vector(a)
    o = box(name, (Vector(a) + Vector(b)) * .5, (width, width, d.length), mat)
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return o


def glyph(pos, scale=.35, mat='rune', plane='front'):
    # A distinctive split diamond / fork rune, engraved as narrow solid inlays.
    strokes = [((0, 1), (-.55, .25)), ((-.55, .25), (0, -.5)),
               ((0, -.5), (.55, .25)), ((.55, .25), (0, 1)),
               ((0, -.5), (0, -1)), ((0, .0), (.7, -.65))]
    def p(v):
        if plane == 'floor':
            return (pos[0] + v[0] * scale, pos[1] + v[1] * scale, pos[2])
        return (pos[0] + v[0] * scale, pos[1], pos[2] + v[1] * scale)
    for i, (a, b) in enumerate(strokes):
        rod('Inset rune stroke %02d' % i, p(a), p(b), scale * .045, mat, 4)


def crystal(name, pos, radius=.35, height=1.3, tilt=0, mat='crystal'):
    n = 5
    verts = []
    for z, r in [(0, radius * .8), (.18 * height, radius), (.78 * height, radius * .72)]:
        verts += [(math.cos(i * math.tau / n) * r, math.sin(i * math.tau / n) * r, z) for i in range(n)]
    verts.append((radius * .25, 0, height))
    faces = [tuple(reversed(range(n)))]
    for row in range(2):
        for i in range(n):
            faces.append((row*n+i, row*n+(i+1)%n, (row+1)*n+(i+1)%n, (row+1)*n+i))
    for i in range(n):
        faces.append((2*n+i, 2*n+(i+1)%n, 3*n))
    o = mesh(name, verts, faces, mat)
    o.data.materials.append(M['tip'])
    for poly in o.data.polygons:
        if poly.index % 4 == 0:
            poly.material_index = 1
    o.location = pos
    o.rotation_euler = (tilt, tilt*.4, random.uniform(0, math.tau))
    return o


def stone(name, pos, radius=1, height=1, mat='stone'):
    n = 7
    verts = []
    radii = [random.uniform(.85, 1.1) for _ in range(n)]
    for z, factor in [(0, .85), (.3*height, 1), (.83*height, .78), (height, .40)]:
        for i in range(n):
            a = math.tau*i/n
            verts.append((math.cos(a)*radius*radii[i]*factor, math.sin(a)*radius*radii[i]*factor, z))
    faces = [tuple(reversed(range(n))), tuple(range(3*n, 4*n))]
    for row in range(3):
        for i in range(n):
            faces.append((row*n+i, row*n+(i+1)%n, (row+1)*n+(i+1)%n, (row+1)*n+i))
    o = mesh(name, verts, faces, mat)
    o.location = pos
    return o


def wedge(name, ri, ro, a0, a1, low, high, mat='stone', arch=False):
    verts = []
    # Either a horizontal ring segment, or an arch voussoir in XZ with Y depth.
    if arch:
        for y in [low, high]:
            verts += [(r*math.cos(a), y, 2.0 + r*math.sin(a)) for r,a in [(ri,a0),(ro,a0),(ro,a1),(ri,a1)]]
    else:
        for z in [low, high]:
            verts += [(r*math.cos(a), r*math.sin(a), z) for r,a in [(ri,a0),(ro,a0),(ro,a1),(ri,a1)]]
    return bevel(mesh(name, verts, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], mat), .018)


def finish(name):
    # Tools use explicit hand-grip origin. Environment assets use ground centre.
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.preferences.filepaths.save_version = 0
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for parent in [o for o in bpy.context.scene.objects if o.type == 'EMPTY']:
        children = [o for o in meshes if o.parent == parent]
        if len(children) > 1:
            bpy.ops.object.select_all(action='DESELECT')
            for o in children:
                o.select_set(True)
            bpy.context.view_layer.objects.active = children[0]
            bpy.ops.object.join()
            bpy.context.object.name = 'HingedLid'
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    # Join material islands except the chest lid, whose local hinge must be preserved.
    roots = [o for o in meshes if o.parent is None]
    if roots:
        bpy.ops.object.select_all(action='DESELECT')
        for o in roots:
            o.select_set(True)
        bpy.context.view_layer.objects.active = roots[0]
        bpy.ops.object.join()
        joined = bpy.context.object
        joined.name = name + '_Geometry'
        bpy.context.scene.cursor.location = (0,0,0)
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in meshes:
        tri = o.modifiers.new('Explicit export triangulation', 'TRIANGULATE')
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=tri.name)
        for poly in o.data.polygons:
            poly.use_smooth = False
    bpy.context.view_layer.update()
    coords = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    triangles = sum(len(o.data.polygons) for o in meshes)
    bounds = [[round(min(v[i] for v in coords), 4), round(max(v[i] for v in coords), 4)] for i in range(3)]
    assert triangles < 12000, (name, triangles)
    assert all(not m.use_nodes or not any(n.type == 'TEX_IMAGE' for n in m.node_tree.nodes) for m in bpy.data.materials)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (name + '.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB',
                              export_yup=True, export_apply=True, export_extras=True)
    REPORT.append(dict(name=name, triangles=triangles, blender_xyz_bounds=bounds,
                       blend='assets/blender/'+name+'.blend', glb='assets/generated/blender/'+name+'.glb'))
    print('MYSTIC_ASSET', name, triangles, bounds)


def entrance():
    reset()
    for side in [-1,1]:
        box('Stepped foundation', (side*2.05,0,.16), (1.7,2.0,.32), 'dark', .07)
        box('Plinth cap', (side*2.05,0,.43), (1.45,1.65,.22), 'edge', .05)
        for row in range(4):
            box('Quarried jamb course', (side*2.0,0,.75+row*.44), (1.05,1.28,.42), 'stone' if row%2 else 'edge', .055)
        glyph((side*2.0,-.65,1.25), .36)
        box('Wing wall', (side*3.2,.35,.9), (1.35,1.4,1.8), 'stone', .09)
        box('Sloped wing coping', (side*3.2,.35,1.9), (1.5,1.55,.25), 'moss', .06)
        stone('Buttress boulder', (side*3.7,.9,0), 1.1,2.0)
    for i in range(11):
        wedge('Radial arch voussoir',1.48,2.26, i*math.pi/11+.012,(i+1)*math.pi/11-.012,-.66,.66,'edge' if i%3==0 else 'stone',True)
    box('Keystone', (0,-.05,4.13), (.52,1.45,.68), 'edge', .07)
    glyph((0,-.79,4.15), .19)
    # Untextured, sealed darkness behind the arch reads as a passage from the iso view.
    box('Recessed tunnel darkness', (0,.74,1.5), (2.9,.15,3.0), 'dark', .02)
    for i in range(5):
        box('Threshold worn stones', ((i-2)*.6,-.8,.06), (.58,1.0,.12), 'edge', .04)
    for side in [-1,1]:
        for i in range(3):
            stone('Lichen ledge', (side*(2.7+i*.35),-.4,.08), .18,.12,'moss')
    finish('runewood_dungeon_entrance')


def staircase():
    reset()
    for i in range(12):
        y = -2.75 + i*.5
        h = .18*(12-i)
        box('Worn tread %02d'%i,(0,y,h*.5),(3.4,.51,h),'edge' if i%3==0 else 'stone',.035)
        for x in [-1.87,1.87]:
            box('Stepped stringer',(x,y,h*.5+.22),(.28,.51,h+.44),'dark',.025)
    # Walk from Godot +Z at top to -Z at foot, using a separate Godot ramp collider.
    finish('crypt_stairway')


def wall():
    reset()
    box('Recessed mortar core',(0,0,1.45),(4,.5,2.9),'dark',.02)
    for row in range(5):
        cuts = [-2,-1,0,1,2] if row%2==0 else [-2,-1.5,-.5,.5,1.5,2]
        for i in range(len(cuts)-1):
            x=(cuts[i]+cuts[i+1])*.5
            box('Staggered masonry',(x,-.03,.29+row*.55),(cuts[i+1]-cuts[i]-.035,.66,.52),'stone' if (row+i)%4 else 'edge',.04)
    box('Coping course',(0,0,2.93),(4.08,.8,.22),'edge',.045)
    box('Foundation moulding',(0,0,.12),(4.12,.82,.24),'dark',.035)
    finish('crypt_wall_4m')


def floor():
    reset()
    for x in range(4):
        for y in range(4):
            box('Flagstone',(x-1.5,y-1.5,-.12+random.uniform(-.005,.005)),(.976,.976,.24), 'edge' if (x+y)%4==0 else 'stone', .035)
    finish('crypt_floor_4m')


def pillar():
    reset()
    for z, r,h,mat in [(.14,.73,.28,'dark'),(.36,.60,.16,'edge'),(1.45,.39,2.05,'stone'),(2.53,.54,.16,'brass'),(2.74,.67,.28,'edge')]:
        rod('Octagonal carved pier',(0,0,z-h*.5),(0,0,z+h*.5),r,mat,8)
    for a in range(4):
        x,y=math.cos(a*math.pi/2)*.395,math.sin(a*math.pi/2)*.395
        rod('Bronze pier fillet',(x,y,.68),(x,y,2.24),.025,'brass',5)
    glyph((0,-.405,1.5),.24)
    finish('crypt_pillar')


def runestone():
    reset()
    stone('Hexagonal standing stone',(0,0,0),.64,2.35,'stone')
    glyph((0,-.56,1.38),.46)
    box('Stone foot',(0,0,.1),(1.5,1.18,.2),'dark',.09)
    for x,y in [(-.42,-.45),(.4,.3)]:
        stone('Lichen fleck',(x,y,.15),.22,.07,'moss')
    finish('sentinel_rune_stone')


def crystals():
    reset()
    stone('Crystal basalt socket',(0,0,0),.8,.35,'dark')
    for x,y,r,h,t in [(0,0,.36,1.9,.05),(-.44,.08,.23,1.1,-.3),(.44,.13,.26,1.35,.3),(.1,-.38,.19,.8,.38)]:
        crystal('Five-sided crystal',(x,y,.16),r,h,t)
    for a in range(5):
        ring('Mineral seam',(0,0,.18),.67,.024,'brass',count=10)
        break
    finish('amethyst_cluster')


def altar():
    reset()
    for z,r,h,mat in [(.12,1.55,.24,'dark'),(.34,1.3,.2,'edge'),(.84,.83,.85,'stone'),(1.31,1.13,.18,'brass'),(1.45,1.28,.16,'dark')]:
        rod('Altar carved octagon',(0,0,z-h*.5),(0,0,z+h*.5),r,mat,8)
    for i in range(8):
        a=i*math.tau/8
        rod('Sacrificial crown prong',(math.cos(a)*.98,math.sin(a)*.98,1.5),(math.cos(a)*.8,math.sin(a)*.8,1.95),.07,'brass',6,top=.015)
    crystal('Suspended heart crystal',(0,0,1.68),.42,1.35,0)
    glyph((0,-.85,.85),.28)
    ring('Turquoise focus ring',(0,0,1.58),.70,.035,'rune',count=16)
    finish('boss_heart_altar')


def arena():
    reset()
    rod('Arena foundation',(0,0,-.28),(0,0,-.06),7.7,'dark',32)
    # Radial rings of individually bevelled wedge flags; centre remains traversable.
    rod('Octagonal heart flag',(0,0,-.08),(0,0,.0),1.8,'stone',12)
    for ri,ro,n in [(1.85,4.4,24),(4.45,6.4,28),(6.45,7.6,32)]:
        for i in range(n):
            wedge('Radial floor flag',ri,ro,i*math.tau/n+.008,(i+1)*math.tau/n-.008,-.08,0,'edge' if i%5==0 else 'stone')
    for r in [1.8,6.42]:
        ring('Concentric brass inlay',(0,0,.012),r,.028,'brass',count=48)
    for i in range(12):
        a=i*math.tau/12
        glyph((math.cos(a)*5.5,math.sin(a)*5.5,.025),.33,'rune','floor')
    finish('sentinel_boss_arena')


def brazier():
    reset()
    rod('Octagonal base',(0,0,0),(0,0,.17),.43,'dark',8)
    rod('Bronze pedestal',(0,0,.17),(0,0,1.14),.14,'brass',8,top=.10)
    rod('Scalloped bowl',(0,0,1.06),(0,0,1.4),.18,'iron',8,top=.43)
    ring('Brass rim',(0,0,1.40),.41,.034,'brass',count=12)
    for i in range(6):
        a=i*math.tau/6
        rod('Curved basket tine',(math.cos(a)*.32,math.sin(a)*.32,1.38),(math.cos(a)*.42,math.sin(a)*.42,1.72),.025,'brass',5,top=.008)
    crystal('Faceted flame',(0,0,1.34),.27,.78,.1,'flame')
    crystal('Flame tongue',(.15,0,1.33),.14,.52,-.2,'flame_tip')
    finish('crypt_brazier')


def chest():
    reset()
    # Body planks with forged bands; arched lid has its own rear hinge empty.
    for i in range(6):
        for y in [-.39,.39]:
            box('Chest wall board',(-.625+i*.25,y,.4),(.236,.10,.64),'wood' if i%2 else 'grain',.02)
    box('Recessed interior floor',(0,0,.14),(1.56,.8,.13),'wood',.015)
    for x in [-.78,.78]:
        box('End grain side',(x,0,.4),(.09,.92,.72),'wood',.025)
    for x in [-.53,.53]:
        box('Body iron strap',(x,-.44,.4),(.105,.055,.7),'iron',.01)
        box('Body back strap',(x,.44,.4),(.105,.055,.7),'iron',.01)
        for z in [.15,.6]:
            rod('Copper rivet',(x,-.49,z),(x,-.45,z),.034,'brass',6)
    box('Chest foot',(0,0,.07),(1.75,1.0,.14),'dark',.035)
    bpy.ops.object.empty_add(type='PLAIN_AXES',location=(0,.44,.74))
    hinge=bpy.context.object
    hinge.name='LidHinge'
    parts=[]
    for i in range(8):
        a0=i*math.pi/8
        a1=(i+1)*math.pi/8
        verts=[]
        for x in [-.82,.82]:
            verts += [(x,-math.cos(a)*.47,.74+math.sin(a)*.40) for a in [a0,a1]]
        o=mesh('Arched lid stave',verts,[(0,1,3,2)],'wood' if i%2 else 'grain')
        bpy.context.view_layer.objects.active=o
        thickness=o.modifiers.new('Solid curved wooden stave','SOLIDIFY')
        thickness.thickness=.028
        bpy.ops.object.modifier_apply(modifier=thickness.name)
        parts.append(o)
    for x in [-.53,.53]:
        for i in range(8):
            a0=i*math.pi/8; a1=(i+1)*math.pi/8
            parts.append(rod('Lid forged strap',(x,-math.cos(a0)*.488,.74+math.sin(a0)*.417),(x,-math.cos(a1)*.488,.74+math.sin(a1)*.417),.052,'iron',4))
    # Closed polygonal end caps keep the lid solid from either side.
    for x in [-.83,.83]:
        verts=[(x,-.46,.74)]+[(x,-math.cos(i*math.pi/8)*.46,.74+math.sin(i*math.pi/8)*.39) for i in range(9)]
        parts.append(mesh('Lid end cap',verts,[tuple(range(len(verts)))],'wood'))
    parts.append(box('Brass lock plate',(0,-.485,.66),(.22,.07,.28),'brass',.025))
    for o in parts:
        o.parent=hinge
        o.matrix_parent_inverse=hinge.matrix_world.inverted()
    finish('ironbound_treasure_chest')


def gate():
    reset()
    # Open pedestrian gate with decorative fixed side panels; 2.8 m clear aperture.
    for side in [-1,1]:
        for x in [side*1.6,side*3.1]:
            box('Tapered post foot',(x,0,.13),(.4,.4,.26),'dark',.025)
            beam('Oak gatepost',(x,0,.1),(x,0,1.9),.23)
            rod('Post finial',(x,0,1.9),(x,0,2.15),.2,'grain',4,top=0)
        for z in [.55,1.25]:
            box('Fence rail',(side*2.35,0,z),(1.55,.14,.14),'grain',.025)
        for i in range(5):
            x=side*(1.8+i*.26)
            box('Split oak pale',(x,-.03,.85),(.13,.12,1.48),'wood',.018)
            rod('Pale pointed cap',(x,-.03,1.59),(x,-.03,1.74),.092,'grain',4,top=0)
        beam('Diagonal braced fence',(side*1.65,-.13,.3),(side*3.02,-.13,1.45),.10,'wood')
    finish('wayfarer_open_gate')


def waypost():
    reset()
    box('Stone socket',(0,0,.15),(.55,.55,.3),'dark',.05)
    beam('Octagonal carved post',(0,0,.05),(0,0,2.5),.18,'wood')
    # Arrow-shaped board with a broad silhouette, bevelled edge and parcel emblem.
    v=[(-.95,-.11,1.7),(.55,-.11,1.7),(1.0,-.11,1.95),(.55,-.11,2.2),(-.95,-.11,2.2)]
    v += [(x,.11,z) for x,y,z in v]
    faces=[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
    bevel(mesh('Routed direction board',v,faces,'grain'),.03)
    glyph((-.37,-.14,1.95),.15,'brass')
    box('Blue guild badge',(.18,-.14,1.95),(.34,.045,.25),'wrap',.02)
    beam('Parcel tie horizontal',(.01,-.18,1.95),(.35,-.18,1.95),.025,'brass')
    beam('Parcel tie vertical',(.18,-.18,1.83),(.18,-.18,2.07),.025,'brass')
    finish('courier_waypost')


def fishing_rod():
    reset()
    # Hand grip at origin. A curved octagonal taper with metal ferrules and line guides.
    rod('Cork grip',(0,0,-.18),(0,0,.20),.036,'cork',10,top=.032)
    rod('End ferrule',(0,0,-.21),(0,0,-.17),.039,'brass',10)
    points=[(0,0,.19),(.015,0,.60),(.055,0,1.05),(.13,0,1.48),(.24,0,1.78)]
    for i in range(len(points)-1):
        rod('Tapered ash blank',points[i],points[i+1],.028-i*.005,'wood',8,top=.023-i*.005)
    for x,y,z in [points[1],points[2],points[3],points[4]]:
        rod('Blue ferrule binding',(x,y,z-.03),(x,y,z+.03),.027 if z<1.3 else .018,'wrap',8)
        ring('Fishing line guide',(x,.038,z),.027 if z<1.5 else .018,.006,'brass', (0,0,0),8)
    # Reel axle on the front of the grip; spool and crank are modelled, not a painted mark.
    rod('Reel mounting foot',(0,0,.08),(0,.09,.08),.018,'iron',6)
    rod('Reel spool',(0,.07,.08),(0,.14,.08),.073,'iron',12)
    for y in [.07,.14]:
        ring('Reel brass flange',(0,y,.08),.075,.011,'brass',(math.pi/2,0,0),12)
    for y in [.088,.10,.112,.124]:
        ring('Wound fishing line',(0,y,.08),.055,.005,'cork',(math.pi/2,0,0),12)
    beam('Reel crank',(.015,.16,.08),(.08,.16,.035),.014,'brass')
    rod('Blue crank handle',(.08,.16,.015),(.08,.16,.065),.016,'wrap',8)
    bpy.ops.object.empty_add(type='PLAIN_AXES',location=(.24,.038,1.78))
    bpy.context.object.name='Tip'
    # Convert Blender Z shaft to glTF +Y; match existing item hand attachment pose.
    finish('courier_fishing_rod')


if __name__ == '__main__':
    for build in [entrance,staircase,wall,floor,pillar,runestone,crystals,altar,arena,brazier,chest,gate,waypost,fishing_rod]:
        build()
    (OUT/'asset_manifest.json').write_text(json.dumps({'blender_version':bpy.app.version_string,'assets':REPORT},indent=2))
    print('MYSTIC_COMPLETE', len(REPORT), 'assets')
