"""Blender-only terrain and authored landscape assembly for the playable Phase 6 map.
Run: blender --background --factory-startup --python tools/build_phase6_world.py
Imports the actual user-supplied newmap pack; never modifies the source pack.
"""
import bpy, math, random, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools'))
import build_blender_assets as B
OUT=ROOT/'assets/generated/phase6'
SRC=ROOT/'assets/blender/phase6'
OUT.mkdir(parents=True,exist_ok=True); SRC.mkdir(parents=True,exist_ok=True)
random.seed(606)
PATH=[(-40,36,.9),(-30,21,1.5),(-18,13,2.0),(-8,11,2.0),(-8,-3,2.0),(1,-9,2.8),(15,-18,3.8),(27,-27,5.4),(29,-35,6.2)]
SIDE=[(-30,21,1.5),(-39,5,3.6),(-27,-9,5.4),(-15,-15,3.2),(1,-9,2.8)]

def closest(x,z,points=PATH):
 best=(1e9,0)
 for a,b in zip(points,points[1:]):
  dx=b[0]-a[0]; dz=b[1]-a[1]; t=max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)))
  d=math.hypot(x-a[0]-dx*t,z-a[1]-dz*t)
  if d<best[0]: best=(d,a[2]+(b[2]-a[2])*t)
 return best

def river_z(x): return 4+2.4*math.sin((x+8)*.075)

def height(x,z):
 d,h=closest(x,z); ds,hs=closest(x,z,SIDE)
 if ds<d: d,h=ds,hs
 hills=3+2.2*math.sin(x*.12)*math.cos(z*.095)+2.4*math.sin(x*.065+z*.071)
 hills+=6*math.exp(-((x+33)**2+(z+17)**2)/230)+5*math.exp(-((x-34)**2+(z+32)**2)/220)
 w=max(0,min(1,(d-3.0)/8)); w=w*w*(3-2*w)
 base=h*(1-w)+max(.5,hills)*w
 r=abs(z-river_z(x))
 if r<4.5 and abs(x)<47:
  weight=max(0,min(1,(r-2.0)/2.5)); weight=weight*weight*(3-2*weight)
  base=-.65*(1-weight)+base*weight
 radius=math.hypot(x/60,z/60)
 angle=math.atan2(z,x)
 # Organic mountain rim rather than a square wall. The road cuts a valley into it.
 rim=max(0,min(1,(radius-.77)/.22))
 rim=rim*rim*(3-2*rim)
 base+=(7+2.2*math.sin(angle*5)+1.4*math.cos(angle*3))*rim*w
 if radius>1.0:
  edge=max(0,min(1,(radius-1.0)/.055))
  base=base*(1-edge)-3*edge
 return base

def export(name,objects=None):
 bpy.context.preferences.filepaths.save_version=0
 bpy.context.scene.unit_settings.system='METRIC'
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects or list(bpy.context.scene.objects): o.select_set(True)
 bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,use_selection=True,export_apply=True)
 print('PHASE6_BLEND_GLB',name)

# Low-poly height field, with road cut-ins and valley erosion authored in Blender.
B.reset()
palette=[B.material('Fern meadow',(.16,.30,.10)),B.material('Sunlit grass',(.18,.32,.12)),
 B.material('Forest meadow',(.14,.28,.085)),B.material('Ochre dirt road',(.36,.22,.10)),
 B.material('Road verge',(.29,.31,.12)),B.material('Cliff basalt',(.25,.28,.25)),B.material('Silty bank',(.25,.23,.16))]
N=92; STEP=1.4
verts=[]; faces=[]
for j in range(N+1):
 for i in range(N+1):
  x=(i-N/2)*STEP; z=(j-N/2)*STEP
  verts.append((x,-z,height(x,z)))
for j in range(N):
 for i in range(N):
  a=j*(N+1)+i
  x=(i-N/2+.5)*STEP; z=(j-N/2+.5)*STEP
  if math.hypot(x,z)<63.2:
   faces.extend([(a,a+N+1,a+1),(a+1,a+N+1,a+N+2)])
terrain=B.mesh('Runewood sculpted valley',verts,faces,'stone')
terrain.data.materials.clear()
for m in palette: terrain.data.materials.append(m)
for p in terrain.data.polygons:
 x=sum(verts[v][0] for v in p.vertices)/3; z=-sum(verts[v][1] for v in p.vertices)/3
 d,_=closest(x,z); ds,_=closest(x,z,SIDE); d=min(d,ds)
 variation=math.sin(x*.075+z*.04)+.4*math.cos(z*.14-x*.03)
 idx=1 if variation>.55 else (2 if variation<-.55 else 0)
 if d<2.15: idx=3
 elif d<3.3: idx=4
 if abs(z-river_z(x))<3: idx=6
 slope=max(abs(height(x+1,z)-height(x-1,z)),abs(height(x,z+1)-height(x,z-1)))
 if slope>2.4 or height(x,z)>12: idx=5
 p.material_index=idx
water=B.material('Moonbrook water',(.10,.34,.40),.15)
water.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.2
wv=[]; wf=[]
for i in range(81):
 x=-50+i*1.25
 for side in [-1,1]: wv.append((x,-river_z(x)+side*1.9,.12))
for i in range(80): wf.append((i*2,i*2+2,i*2+3,i*2+1))
stream=B.mesh('Moonbrook stream',wv,wf,'dark'); stream.data.materials.clear();stream.data.materials.append(water)
export('runewood_terrain')

# Actual Alefran newmap models, copied, normalized and arranged in Blender.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/newmap/FreeVersion/AllModelsInOne/AllAssets_with_texture.glb'))
templates={}
for o in list(bpy.context.scene.objects):
 if o.type!='MESH': continue
 data=o.data.copy(); coords=[o.matrix_world@v.co for v in data.vertices]
 cx=(min(v.x for v in coords)+max(v.x for v in coords))*.5
 cy=(min(v.y for v in coords)+max(v.y for v in coords))*.5
 low=min(v.z for v in coords)
 for v,c in zip(data.vertices,coords): v.co=c-Vector((cx,cy,low))
 templates[o.name]=data
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
# Reuse a proper leafy tree as a complement to the supplied pack's gnarled deadwood.
# This existing Quaternius asset already matches the game's art direction.
bpy.ops.import_scene.fbx(filepath=str(ROOT/'assets/models/quaternius/ultimate_nature/CommonTree_1.fbx'))
for o in list(bpy.context.scene.objects):
 if o.type=='MESH':
  data=o.data.copy(); coords=[o.matrix_world@v.co for v in data.vertices]
  center=Vector(((min(v.x for v in coords)+max(v.x for v in coords))*.5,(min(v.y for v in coords)+max(v.y for v in coords))*.5,min(v.z for v in coords)))
  for v,c in zip(data.vertices,coords):v.co=c-center
  # Blender's FBX importer reads these CC0 colors with Alpha=0 despite solid
  # diffuse colors. Rebuild only the export-copy materials as opaque PBR colors.
  for i,m in enumerate(list(data.materials)):
   data.materials[i]=B.material('Reused tree '+m.name,tuple(m.diffuse_color[:3]))
  templates['CommonTree_1']=data
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
# Downsample in-memory export copies only. Original pack images stay untouched.
for image in bpy.data.images:
 if image.size[0]>1024 or image.size[1]>1024:
  ratio=1024/max(image.size); image.scale(max(1,int(image.size[0]*ratio)),max(1,int(image.size[1]*ratio)))
  image.pack()
placements=[]

def place(key,x,z,scale=1,yaw=0,y=None,solid=0):
 o=bpy.data.objects.new('Reused_'+key,templates[key]);bpy.context.collection.objects.link(o)
 h=height(x,z) if y is None else y
 o.location=(x,-z,h); o.rotation_euler.z=-yaw
 o.scale=(scale,scale,scale) if isinstance(scale,(float,int)) else scale
 if solid: placements.append({'x':x,'z':z,'y':h,'radius':solid,'height':3})
 return o

place('Bridge01',-8,4,(1.15,1.15,.65),0,.75)
place('Stylized Hut01',-37,24,.7,.45,solid=2.7)
place('Streetlamp01',-37,30,.8,0,solid=.3)
place('Bench01',-36,22,1,.5,solid=.5)
place('Barrel03',-29,25,1,0,solid=.45)
place('Box01',-30,26,1,0,solid=.5)
for x,z,a in [(-29,-9,.4),(-25,-9,-.25),(-29,-14,1.5)]: place('Wall_Stone01',x,z,1.25,a,solid=.6)
for x,z in [(-30,-14),(-26,-15)]: place('Trunk02',x,z,1.2,random.random()*6)
for i in range(200):
 if i%3:
  cx,cz=random.choice([(-25,-30),(30,5),(-22,10),(25,25)])
  x=max(-46,min(46,random.gauss(cx,10)));z=max(-44,min(43,random.gauss(cz,10)))
 else:x=random.uniform(-45,45);z=random.uniform(-44,43)
 if min(closest(x,z)[0],closest(x,z,SIDE)[0])<4.8 or math.hypot(x+33,z-25)<7 or abs(z-river_z(x))<4: continue
 # Supplied 9 m gnarled tree is a strong ancient forest silhouette.
 if i%4==0:place('Trunk04',x,z,random.uniform(.5,.85),random.random()*6,solid=.55)
 else:place('CommonTree_1',x,z,random.uniform(1.8,2.5),random.random()*6,solid=.48)
for i in range(170):
 x=random.uniform(-48,48);z=random.uniform(-46,45)
 if min(closest(x,z)[0],closest(x,z,SIDE)[0])<3.5 or abs(z-river_z(x))<2.5:continue
 place('Foliage01',x,z,random.uniform(.4,1.2),random.random()*6)
for i in range(55):
 x=random.uniform(-48,48);z=random.uniform(-46,45)
 if min(closest(x,z)[0],closest(x,z,SIDE)[0])<4.8:continue
 place('RockMedium',x,z,random.uniform(1.3,4),random.random()*6)
export('runewood_newmap_dressing')
# JSON provides exact terrain samples and simple gameplay colliders independently of
# the visually detailed scenery. Renderer and physics consume the same elevations.
samples=[[round(height((i-N/2)*STEP,(j-N/2)*STEP),5) for i in range(N+1)] for j in range(N+1)]
(OUT/'world_layout.json').write_text(json.dumps({'grid':N,'step':STEP,'heights':samples,'path':PATH,'side_path':SIDE,'solids':placements,'arrival':[-40,height(-40,36)+.2,36],'dungeon':[29,height(29,-35),-35],'bridge_deck':2.0},indent=1))
print('PHASE6_WORLD_COMPLETE',bpy.app.version_string,len(placements),'colliders')
