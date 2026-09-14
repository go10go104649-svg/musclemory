import os
import bpy, sys, pathlib, json
root = pathlib.Path(os.environ.get('MUSCLEMORY_ART_WORK', '/private/tmp/musclemory-3d-tools'))
ext = root/'extensions'
ext.mkdir(exist_ok=True)
link=ext/'mpfb'
if not link.exists(): link.symlink_to(str(pathlib.Path(os.environ.get('MPFB_REPO', '/private/tmp/musclemory-mpfb2'))/'src/mpfb'), target_is_directory=True)
repo=bpy.context.preferences.extensions.repos.new(name='MUSCLEMORY Tools', module='musclemory', custom_directory=str(ext))
bpy.ops.preferences.addon_enable(module='bl_ext.musclemory.mpfb')
from bl_ext.musclemory.mpfb.services.humanservice import HumanService
from bl_ext.musclemory.mpfb.services.targetservice import TargetService
from bl_ext.musclemory.mpfb.services.exportservice import ExportService
from bl_ext.musclemory.mpfb.services.objectservice import ObjectService
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
macro = TargetService.get_default_macro_info_dict()
print('MACRO',macro)
macro.update(gender=1.0, muscle=1.0, weight=0.32, age=0.5, height=0.5)
human=HumanService.create_human(macro_detail_dict=macro)
human.name='Athlete'
targets=pathlib.Path(os.environ.get('MPFB_REPO', '/private/tmp/musclemory-mpfb2'))/'src/mpfb/data/targets'
for side in ('l','r'):
    for part,weight in [('upperarm-muscle',0.45),('upperarm-shoulder-muscle',0.45),('lowerarm-muscle',0.2)]:
        TargetService.load_target(human,str(targets/'arms'/f'{side}-{part}-incr.target.gz'),weight=weight)
for target,weight in [('torso-muscle-pectoral-incr',0.8),('torso-vshape-incr',0.3),('torso-muscle-dorsi-incr',0.25)]:
    TargetService.load_target(human,str(targets/'torso'/f'{target}.target.gz'),weight=weight)
rig=HumanService.add_builtin_rig(human,'game_engine')
print('RIG',rig.name)
(root/'bones.json').write_text(json.dumps({b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'matrix':[list(row) for row in b.matrix_local]} for b in rig.data.bones},indent=2))
bpy.context.view_layer.objects.active=human
bpy.ops.object.select_all(action='DESELECT')
human.select_set(True)
bpy.ops.object.shape_key_remove(all=True,apply_mix=True)
for mod in list(human.modifiers):
    if mod.type=='MASK': bpy.ops.object.modifier_apply(modifier=mod.name)
for p in human.data.polygons: p.use_smooth=True
mat=bpy.data.materials.new('Neutral mannequin')
mat.diffuse_color=(0.24,0.27,0.29,1)
mat.use_nodes=True
bsdf=mat.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value=mat.diffuse_color
bsdf.inputs['Roughness'].default_value=0.7
human.data.materials.clear();human.data.materials.append(mat)
for name,color in [('Pectoralis major',(0.34,0.018,0.028,1)),('Anterior deltoid',(0.63,0.23,0.22,1)),('Triceps brachii',(0.63,0.23,0.22,1)),('Training shorts',(0.035,0.045,0.052,1))]:
 m=mat.copy();m.name=name;m.diffuse_color=color;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color;human.data.materials.append(m)
from mathutils import Vector
sub=human.modifiers.new('Surface subdivision','SUBSURF');sub.levels=2;sub.render_levels=2
bpy.ops.object.modifier_apply(modifier=sub.name)
for face in human.data.polygons:
 c=sum((human.data.vertices[i].co for i in face.vertices),Vector())/len(face.vertices)
 x,y,z=abs(c.x),c.y,c.z
 if y < -0.035 and abs((x-.118)/.099)**2.5 + abs((z-(1.323-.09*(x-.118)))/.068)**2.5 < 1: face.material_index=1
 elif y < -.022 and ((x-.217)/.067)**2 + ((z-1.354)/.087)**2 < 1: face.material_index=2
 elif y > -.005 and ((x-.284)/.065)**2 + ((z-1.262)/.1)**2 < 1: face.material_index=3
 elif x < .245 and .755 < z < 1.025: face.material_index=4
dec=human.modifiers.new('Mobile mesh reduction','DECIMATE');dec.ratio=.23;dec.delimit={'MATERIAL'}
bpy.ops.object.modifier_apply(modifier=dec.name)
for p in human.data.polygons:p.use_smooth=True
for p in human.data.polygons:p.material_index=0
human.data.materials.clear();human.data.materials.append(mat)
mat.diffuse_color=(1,1,1,1)
bsdf.inputs['Base Color'].default_value=(1,1,1,1)
color=human.data.color_attributes.new(name='MuscleColor',type='FLOAT_COLOR',domain='POINT')
human.data.color_attributes.active_color=color
attrs={name:human.data.attributes.new(name=name,type='FLOAT',domain='POINT') for name in ('muscle_pectoral','muscle_deltoid_anterior','muscle_triceps')}
color=human.data.color_attributes['MuscleColor']
attrs={name:human.data.attributes[name] for name in attrs}
node=mat.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='MuscleColor';mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color'])
def smooth(a,b,v):
 t=max(0,min(1,(v-a)/(b-a)));return t*t*(3-2*t)
for v in human.data.vertices:
 x,y,z=abs(v.co.x),v.co.y,v.co.z
 chest=(abs((x-.118)/.105)**2.5 + abs((z-(1.327-.09*(x-.118)))/.078)**2.5)**(1/2.5)
 pec=(1-smooth(.90,1.02,chest))*smooth(-.015,-.045,y)
 shoulder=(((x-.223)/.077)**2+((z-1.362)/.094)**2)**.5
 delt=(1-smooth(.88,1.03,shoulder))*smooth(.002,-.031,y)*(1-pec)
 arm=(((x-.285)/.073)**2+((z-1.267)/.112)**2)**.5
 tri=(1-smooth(.85,1.03,arm))*smooth(-.014,.015,y)*(1-pec-delt)
 weights=(pec,delt,tri)
 base=(.30,.33,.35);targets_rgb=((.22,.004,.011),(.58,.18,.17),(.58,.18,.17))
 rgb=[base[k]*(1-sum(weights))+sum(weights[j]*targets_rgb[j][k] for j in range(3)) for k in range(3)]
 shorts=0
 rgb=[rgb[k]*(1-shorts)+(.035,.045,.052)[k]*shorts for k in range(3)]
 color.data[v.index].color=(*rgb,1)
 for attr,w in zip(attrs.values(),weights):attr.data[v.index].value=w
human['muscle_region_attributes']={'pectoralis_major':'_MUSCLE_PECTORAL','deltoid_anterior':'_MUSCLE_DELTOID_ANTERIOR','triceps_brachii':'_MUSCLE_TRICEPS'}
print('FINAL_MESH',len(human.data.vertices),len(human.data.polygons))
bpy.ops.wm.save_as_mainfile(filepath=str(root/'base.blend'))
from mathutils import Vector
def aim(obj,point):obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=800;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world.color=(0.1,0.1,0.1)
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(0.04,0.05,0.065,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=0.4
bpy.ops.object.camera_add(location=(2,-5,2.0));cam=bpy.context.object;aim(cam,(0,0,.9));cam.data.type='ORTHO';cam.data.ortho_scale=2.2;scene.camera=cam
for name,pos,power,size in [('Key',(-2,-4,4),650,4),('Fill',(3,-1,2),300,3),('Rim',(0,3,3),700,2)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,1))
scene.render.filepath=str(root/'static_neutral.png');bpy.ops.render.render(write_still=True)
