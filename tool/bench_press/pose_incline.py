import os
import bpy, math, json, pathlib
from mathutils import Vector, Matrix
ROOT=pathlib.Path(os.environ.get('SETKEEP_ART_WORK', os.environ.get('MUSCLEMORY_ART_WORK', '/private/tmp/musclemory-3d-tools')))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'base.blend'))
human=bpy.data.objects['Athlete'];rig=bpy.data.objects['Athlete.rig']
scene=bpy.context.scene
scene.frame_start=1;scene.frame_end=121;scene.render.fps=30
rig.rotation_euler=(-math.pi/2,0,0);rig.location=(0,-1.14,.565)
bpy.context.view_layer.update()
pivot=Vector((0,-.22,.50))
incline=Matrix.Rotation(math.radians(45),4,'X')
rig.matrix_world=Matrix.Translation(pivot)@incline@Matrix.Translation(-pivot)@rig.matrix_world
bpy.context.view_layer.update()
world=rig.matrix_world.copy();inv=world.inverted()
def make_mat(name,rgb,rough=.7,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m.use_nodes=True;n=m.node_tree.nodes.get('Principled BSDF');n.inputs['Base Color'].default_value=m.diffuse_color;n.inputs['Roughness'].default_value=rough;n.inputs['Metallic'].default_value=metal;return m
pad=make_mat('Bench upholstery',(.045,.055,.065),.85)
frame=make_mat('Bench frame',(.12,.14,.16),.45,.45)
steel=make_mat('Brushed bar steel',(.43,.48,.53),.31,.75)
rubber=make_mat('Weight plates',(.052,.061,.07),.65)
def box(name,loc,scale,mat,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
 m=o.modifiers.new('Soft manufactured edges','BEVEL');m.width=bevel;m.segments=3;bpy.ops.object.modifier_apply(modifier=m.name)
 for p in o.data.polygons:p.use_smooth=True
 m=o.modifiers.new('Weighted surface normals','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=m.name)
 return o
back=box('Incline backrest',(0,.25,.432),(.3,1.02,.085),pad)
back.matrix_world=Matrix.Translation(pivot)@incline@Matrix.Translation(-pivot)@back.matrix_world
box('Incline seat',(0,-.36,.432),(.32,.28,.085),pad)
box('Bench spine',(0,.15,.35),(.07,1.04,.08),frame,.012)
for y in (-.3,.59):
 box('Bench leg',(0,y,.19),(.06,.07,.33),frame,.01)
 box('Bench foot',(0,y,.036),(.55,.13,.065),frame,.012)
 for x in (-.25,.25):box('Bench rubber foot',(x,y,.021),(.10,.15,.042),rubber,.008)
dumbbells={}
for side,sign in [('l',1),('r',-1)]:
 bpy.ops.object.empty_add();weight=bpy.context.object;weight.name='Dumbbell_'+side;dumbbells[side]=weight
 for label,x,radius,depth,mat in [('Grip',0,.014,.16,steel),('Plate_inner',-.115,.095,.07,rubber),('Plate_outer',.115,.095,.07,rubber),('Shaft',0,.019,.30,steel)]:
  bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=radius,depth=depth,location=(x,0,0),rotation=(0,math.pi/2,0))
  obj=bpy.context.object;obj.name=side+'_'+label;obj.parent=weight;obj.data.materials.append(mat)
  bevel=obj.modifiers.new('Rounded edges','BEVEL');bevel.width=.006;bevel.segments=3;bpy.ops.object.modifier_apply(modifier=bevel.name)
  for poly in obj.data.polygons:poly.use_smooth=True
def rotation_for_direction(bone,head,tail):
 rest=(bone.tail_local-bone.head_local).normalized()
 q=rest.rotation_difference((tail-head).normalized())
 m=q.to_matrix().to_4x4()@bone.matrix_local
 m.translation=head
 return m
def place(name,head_world,tail_world):
 b=rig.data.bones[name];pb=rig.pose.bones[name]
 pb.matrix=rotation_for_direction(b,inv@head_world,inv@tail_world)
 bpy.context.view_layer.update()
def two_bone(a,b,l1,l2,hint):
 d=b-a;dist=d.length
 if not abs(l1-l2)+1e-5<dist<l1+l2-1e-5:raise ValueError(('IK reach',dist,l1,l2))
 n=d.normalized();along=(l1*l1-l2*l2+dist*dist)/(2*dist)
 bend=hint-n*hint.dot(n);bend.normalize()
 return a+n*along+bend*math.sqrt(max(0,l1*l1-along*along))
hands={}
for side,sign in [('l',1),('r',-1)]:
 b=rig.data.bones[f'hand_{side}'];w=b.head_local.copy()
 forward=(rig.data.bones[f'middle_01_{side}'].head_local-w).normalized()
 across=(rig.data.bones[f'index_01_{side}'].head_local-rig.data.bones[f'pinky_01_{side}'].head_local).normalized();across=(across-forward*across.dot(forward)).normalized()
 rest=Matrix((across,forward,across.cross(forward))).transposed()
 f=Vector((0,0,1));a=Vector((-sign,0,0));desired=Matrix((a,f,a.cross(f))).transposed()
 rotation=desired@rest.transposed()
 offset=(rig.data.bones[f'middle_01_{side}'].head_local-w)*.65
 # The shaft rests against the palm, on the finger side of the wrist.
 contact=rotation@offset+Vector((0,-.012,0))
 hands[side]=(rotation,contact)
 for finger in ('index','middle','ring','pinky'):
  for i,angle in enumerate((63,88,55),1):
   name=f'{finger}_{i:02d}_{side}';pb=rig.pose.bones[name]
   axis=rotation@rig.data.bones[name].matrix_local.to_3x3().col[0]
   pb.rotation_mode='XYZ';pb.rotation_euler.x=math.radians(angle)*(1 if axis.x>0 else -1)
 # Flex the thumb around the medial side of the shaft.
 for i,angle in enumerate((25,48,55),1):
  pb=rig.pose.bones[f'thumb_{i:02d}_{side}'];pb.rotation_mode='XYZ';pb.rotation_euler.x=math.radians(angle)*(1 if sign>0 else -1)
 for lower,upper in [('calf','thigh')]:
  hip=world@rig.data.bones[f'{upper}_{side}'].head_local
  ankle=Vector((sign*.31,-.80,rig.data.bones[f'foot_{side}'].head_local.z))
  knee=two_bone(hip,ankle,rig.data.bones[f'{upper}_{side}'].length,rig.data.bones[f'{lower}_{side}'].length,Vector((sign*.15,-.1,1)))
  place(f'{upper}_{side}',hip,knee);place(f'{lower}_{side}',knee,ankle)
  foot=rig.data.bones[f'foot_{side}'].matrix_local.copy();foot.translation=ankle
  rig.pose.bones[f'foot_{side}'].matrix=inv@foot
  bpy.context.view_layer.update()
def ease(t):return t*t*t*(10+t*(-15+6*t))
metrics=[]
for frame_index in range(121):
 scene.frame_set(frame_index+1)
 if frame_index<8:down=0
 elif frame_index<52:down=ease((frame_index-8)/44)
 elif frame_index<62:down=1
 elif frame_index<106:down=1-ease((frame_index-62)/44)
 else:down=0
 for side,sign in [('l',1),('r',-1)]:
  dumbbells[side].location=(sign*(.23+.15*down),.08-.06*down,1.43-.34*down)
  dumbbells[side].keyframe_insert(data_path='location')
 errors=[]
 for side,sign in [('l',1),('r',-1)]:
  rotation,contact=hands[side]
  grip=dumbbells[side].location.copy();wrist=grip-contact
  shoulder=world@rig.data.bones[f'upperarm_{side}'].head_local
  elbow=two_bone(shoulder,wrist,rig.data.bones[f'upperarm_{side}'].length,rig.data.bones[f'lowerarm_{side}'].length,Vector((sign*1,-.8,-.45)))
  place(f'upperarm_{side}',shoulder,elbow);place(f'lowerarm_{side}',elbow,wrist)
  b=rig.data.bones[f'hand_{side}'];m=rotation.to_4x4()@b.matrix_local;m.translation=wrist
  rig.pose.bones[f'hand_{side}'].matrix=inv@m
  bpy.context.view_layer.update()
  actual=(world@rig.pose.bones[f'hand_{side}'].matrix).translation+contact
  errors.append((actual-grip).length)
 for pb in rig.pose.bones:
  pb.keyframe_insert(data_path='location');pb.keyframe_insert(data_path='rotation_euler' if pb.rotation_mode=='XYZ' else 'rotation_quaternion');pb.keyframe_insert(data_path='scale')
 metrics.append({'frame':frame_index,'left_weight':list(dumbbells['l'].location),'right_weight':list(dumbbells['r'].location),'palm_anchor_error_m':max(errors)})
# Linear samples of smooth quintic movement; identical end points close the loop.
for obj in (rig,*dumbbells.values()):
 if obj.animation_data and obj.animation_data.action:
  obj.animation_data.action.name='InclineDumbbellPressLoop_'+obj.name
  for slot in obj.animation_data.action.slots:
   for layer in obj.animation_data.action.layers:
    for strip in layer.strips:
     bag=strip.channelbag(slot)
     if bag:
      for fc in bag.fcurves:
       for k in fc.keyframe_points:k.interpolation='LINEAR'
(ROOT/'incline_motion_metrics.json').write_text(json.dumps(metrics,indent=2))
def aim(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.8,-3.4,2.5));cam=bpy.context.object;cam.name='FixedFormCamera';aim(cam,(0,-.13,.58));cam.data.type='ORTHO';cam.data.ortho_scale=2.45;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.04,.05,.065,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.3
for name,pos,power,size in [('Key',(-2,-3,4),550,3),('Fill',(3,-1,3),220,3),('Rim',(0,3,3),600,2)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,.5))
floor=box('Floor',(0,0,-.04),(5,5,.05),make_mat('Floor matte',(.025,.033,.044)),.01)
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'incline.blend'))
for f,name in [(1,'top'),(56,'bottom')]:
 scene.frame_set(f);scene.render.filepath=str(ROOT/f'incline_{name}.png');bpy.ops.render.render(write_still=True)
