"""Anatomical surface masks on the approved, continuous MPFB2 rest mesh.
Masks are closed splines in production coordinates, projected onto front/back
surfaces. One mesh, material primitives only: no floating muscle geometry.
"""
import bpy, bmesh, pathlib, os, json, math
from mathutils import Vector
project=pathlib.Path(__file__).resolve().parents[2]
source=pathlib.Path(os.environ.get('BODY_BASE_BLEND',str(project/'art/body_tab/body_tab.blend')))
bpy.ops.wm.open_mainfile(filepath=str(source))
human=bpy.data.objects.get('Athlete') or bpy.data.objects['BodyTabContinuousSource']
for mod in list(human.modifiers): human.modifiers.remove(mod)
human.parent=None; human.matrix_world.identity()
for obj in list(bpy.data.objects):
 if obj!=human: bpy.data.objects.remove(obj,do_unlink=True)
if bpy.data.meshes.get('BodyTabProductionBase'):
 human.data=bpy.data.meshes['BodyTabProductionBase'].copy()
mesh=human.data
# Artist-editable landmarks: sternal/clavicular origins, insertions and muscle
# bellies. Mirroring shares left/right topology. Curves avoid rectangular cuts.
contours={
'pectoralisMajor': [[(.012,1.39),(.082,1.407),(.161,1.396),(.211,1.37),(.197,1.331),(.151,1.282),(.074,1.274),(.016,1.30)]],
'anteriorDeltoid': [[(.173,1.403),(.223,1.418),(.269,1.393),(.29,1.347),(.277,1.307),(.257,1.286),(.231,1.334),(.205,1.375)]],
'posteriorDeltoid': [[(.172,1.402),(.22,1.42),(.27,1.39),(.292,1.343),(.276,1.306),(.255,1.29),(.225,1.333),(.186,1.367)]],
'biceps': [[(.267,1.32),(.292,1.302),(.319,1.27),(.35,1.203),(.351,1.178),(.333,1.174),(.307,1.205),(.286,1.252)]],
'triceps': [[(.265,1.328),(.3,1.31),(.337,1.258),(.364,1.187),(.348,1.162),(.323,1.194),(.303,1.23),(.276,1.271)]],
'forearms': [[(.361,1.188),(.396,1.157),(.439,1.084),(.48,1.009),(.466,.995),(.425,1.048),(.391,1.09),(.354,1.139)]],
'trapezius': [[(.006,1.483),(.055,1.462),(.10,1.423),(.177,1.399),(.166,1.368),(.105,1.326),(.038,1.215),(.008,1.19)]],
'latissimusDorsi': [[(.181,1.351),(.204,1.304),(.188,1.237),(.156,1.164),(.097,1.073),(.032,1.044),(.045,1.157),(.09,1.263),(.128,1.323)]],
'rectusAbdominis': [],
'obliques': [[(.102,1.267),(.16,1.289),(.176,1.239),(.149,1.186),(.132,1.121),(.117,1.047),(.074,1.009),(.086,1.105),(.086,1.195)]],
'gluteus': [[(.011,1.024),(.088,1.055),(.167,1.031),(.21,.967),(.202,.895),(.158,.84),(.076,.856),(.023,.913)]],
'quadriceps': [
[(.11,.889),(.142,.884),(.167,.805),(.185,.707),(.177,.606),(.156,.526),(.131,.554),(.118,.653),(.099,.784)],
[(.164,.909),(.211,.87),(.23,.772),(.224,.665),(.199,.564),(.18,.55),(.192,.675),(.187,.778)],
[(.078,.804),(.105,.736),(.119,.665),(.144,.585),(.147,.534),(.116,.505),(.092,.539),(.087,.643)]],
'hamstrings': [
[(.084,.853),(.12,.862),(.146,.806),(.164,.714),(.167,.603),(.148,.525),(.12,.58),(.095,.701)],
[(.16,.846),(.205,.852),(.229,.784),(.223,.675),(.199,.551),(.178,.515),(.179,.628),(.173,.734)]],
'adductors': [[(.05,.877),(.087,.875),(.105,.797),(.095,.701),(.083,.64),(.058,.697),(.036,.79)]],
'calves': [
[(.121,.478),(.156,.48),(.161,.434),(.154,.354),(.131,.254),(.12,.217),(.104,.303),(.096,.385)],
[(.171,.474),(.2,.461),(.211,.396),(.198,.32),(.166,.229),(.153,.207),(.157,.33)]],
}
# Four paired tapered bellies, separated by linea alba and tendinous bands.
for z,w,h in [(1.245,.067,.024),(1.188,.066,.026),(1.13,.06,.026),(1.069,.05,.028)]:
 contours['rectusAbdominis'].append([(.009,z+h*.8),(w*.6,z+h),(w,z+h*.5),(w*.98,z-h*.6),(w*.6,z-h),(.009,z-h*.7)])
def spline(points):
 out=[]; n=len(points)
 for i in range(n):
  a,b,c,d=[points[j%n] for j in (i-1,i,i+1,i+2)]
  for k in range(8):
   t=k/8
   out.append(tuple(.5*((2*b[q])+(-a[q]+c[q])*t+(2*a[q]-5*b[q]+4*c[q]-d[q])*t*t+(-a[q]+3*b[q]-3*c[q]+d[q])*t*t*t) for q in (0,1)))
 return out
curves={name:[spline(p) for p in ps] for name,ps in contours.items()}
# Bounding boxes skip irrelevant curves; winding determines the actual outline.
shapes={name:[(min(p[0] for p in ps),max(p[0] for p in ps),min(p[1] for p in ps),max(p[1] for p in ps),ps) for ps in polys] for name,polys in curves.items()}
def inside(x,z,shape):
 lo,hi,bottom,top,ps=shape
 if not(lo<=x<=hi and bottom<=z<=top): return False
 hit=False; a=ps[-1]
 for b in ps:
  if (a[1]>z)!=(b[1]>z) and x<(b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:hit=not hit
  a=b
 return hit
front={'pectoralisMajor','anteriorDeltoid','biceps','rectusAbdominis','obliques','quadriceps','adductors'}
back={'posteriorDeltoid','triceps','trapezius','latissimusDorsi','gluteus','hamstrings','calves'}
def region_at(c):
 x,y,z=abs(c.x),c.y,c.z
 for name,polys in shapes.items():
  if name=='forearms' and (x>.456 or z<1.033):continue
  if name in front and y> (-.018 if z>1.0 and x<.21 else .015):continue
  if name in back and y< (.022 if x<.23 else .002):continue
  if any(inside(x,z,shape) for shape in polys):return name
 return 'neutral'
# Refine only mask boundaries (not the whole body). This keeps the mobile
# asset compact while eliminating the coarse decimation's serrated outlines.
# Always refine from the original approved mesh, never repeatedly from exports.
original_mesh=bpy.data.meshes.get('BodyTabProductionBase') or mesh.copy()
original_mesh.name='BodyTabProductionBase';original_mesh.use_fake_user=True
for refinement in range(3):
 bm=bmesh.new();bm.from_mesh(mesh)
 labels={v:region_at(v.co) for v in bm.verts}
 edges=[e for e in bm.edges if labels[e.verts[0]]!=labels[e.verts[1]] or
        region_at((e.verts[0].co+e.verts[1].co)*.5)!=labels[e.verts[0]]]
 bmesh.ops.subdivide_edges(bm,edges=edges,cuts=1,use_grid_fill=True)
 bmesh.ops.triangulate(bm,faces=list(bm.faces))
 bm.to_mesh(mesh);bm.free();mesh.update()
# Keep original geometry and smooth normals; remove exercise color data.
for ca in list(mesh.color_attributes):mesh.color_attributes.remove(ca)
mesh.materials.clear()
for i,mat in enumerate(bpy.data.materials):mat.name='source_material_'+str(i)
names=['neutral']+list(contours)
for name in names:
 mat=bpy.data.materials.new('body_'+name);mat.use_nodes=True
 mat.diffuse_color=(1,1,1,1)
 bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.7
 mesh.materials.append(mat)
regions={name:[] for name in names}
mesh.update()
for face in mesh.polygons:
 name=region_at(face.center);face.material_index=names.index(name);face.use_smooth=True;regions[name].append(face.index)
human.name='BodyTabContinuousSource'
human['body_tab_region_faces']=regions
human['mask_method']='Mirrored anatomical spline contours on one original surface'
# Store separate named face masks for future primary/secondary activation.
for name in contours:
 old=mesh.attributes.get('mask_'+name)
 if old:mesh.attributes.remove(old)
 a=mesh.attributes.new('mask_'+name,'BOOLEAN','FACE')
 for i in regions[name]:a.data[i].value=True
# Save the final editable masks and an unlinked original mesh datablock.
# Rebuilds start from that original, so refinement never accumulates.
bpy.ops.wm.save_as_mainfile(filepath=str(project/'art/body_tab/body_tab.blend'))
output=project/'assets/models/body_tab.glb'
bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',export_animations=False,export_skins=False,export_morph=False,export_cameras=False,export_lights=False,export_extras=False,export_normals=True)
report={'source':str(source),'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),'region_faces':{k:len(v) for k,v in regions.items()},'bytes':output.stat().st_size,'meshes':1,'animations':0,'skins':0}
(project/'art/body_tab/asset_report.json').write_text(json.dumps(report,indent=2))
(project/'art/body_tab/mask_contours.json').write_text(json.dumps(contours,indent=2))
print(report)
if os.environ.get('BODY_RENDER_DIR'):
 out=pathlib.Path(os.environ['BODY_RENDER_DIR']);out.mkdir(parents=True,exist_ok=True)
 for mat in mesh.materials:
  mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.38,.4,.42,1) if mat.name=='body_neutral' else (.55,.015,.025,1)
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=20
 scene.render.resolution_x=720;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
 scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.05,.05,.05,1)
 def aim(obj):obj.rotation_euler=(Vector((0,0,.87))-obj.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=1.95;scene.camera=cam
 for name,pos in [('front',(0,-4,.87)),('side',(4,0,.87)),('back',(0,4,.87))]:
  cam.location=pos;aim(cam)
  bpy.ops.object.light_add(type='AREA',location=(pos[0]-1,pos[1],3));light=bpy.context.object;light.data.energy=450;light.data.size=4;aim(light)
  scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True);bpy.data.objects.remove(light,do_unlink=True)
