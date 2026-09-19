"""Blender authoring entry point. Reuses the approved athlete and joint hierarchy.
Source GLBs and previews go to --output, never duplicated in Flutter's bundle.
"""
import bpy, json, math, pathlib, sys
from mathutils import Vector, Matrix, Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(pathlib.Path(__file__).parent))
from anatomy import paint
from author_options import parse_options, prepare_output
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
opt=parse_options(args, ROOT)
catalog=json.loads((pathlib.Path(__file__).parent/'catalog.json').read_text())['exercises']
FPS=24;FRAMES=96

def material(name,rgb,rough=.7,metal=0):
 m=bpy.data.materials.get(name)
 if m:return m
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*rgb,1)
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 return m

def box(name,location,size,mat,bevel=.015):
 bpy.ops.mesh.primitive_cube_add(size=1,location=location);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
 mod=o.modifiers.new('Manufactured edges','BEVEL');mod.width=bevel;mod.segments=3;bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=True
 mod=o.modifiers.new('Surface normals','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
 return o

def cylinder(name,radius,depth,mat,location=(0,0,0),axis=(0,0,1)):
 bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius,depth=depth,location=location);o=bpy.context.object;o.name=name;o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler();o.data.materials.append(mat)
 mod=o.modifiers.new('Machined edge','BEVEL');mod.width=min(.006,radius*.15);mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=True
 return o

def rod(name,a,b,radius,mat):
 a,b=Vector(a),Vector(b);o=cylinder(name,radius,1,mat);set_rod(o,a,b);return o

def set_rod(o,a,b):
 a,b=Vector(a),Vector(b);o.location=(a+b)/2;o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y');o.scale.z=(b-a).length

def key(o):
 for path in ['location','rotation_quaternion' if o.rotation_mode=='QUATERNION' else 'rotation_euler','scale']:o.keyframe_insert(data_path=path)

def two_bone(a,b,l1,l2,hint):
 d=b-a;distance=d.length
 if not abs(l1-l2)+1e-5 < distance < l1+l2-1e-5:raise ValueError(f'Unreachable joint {distance:.4f}; range {abs(l1-l2):.4f}..{l1+l2:.4f}')
 n=d.normalized();along=(l1*l1-l2*l2+distance*distance)/(2*distance);bend=hint-n*hint.dot(n)
 if bend.length<1e-4:raise ValueError('Ambiguous elbow/knee pole')
 return a+n*along+bend.normalized()*math.sqrt(max(0,l1*l1-along*along))

def ease(t):return t*t*t*(10+t*(-15+6*t))
def phase(t):
 if t<.065:return 0.
 if t<.43:return ease((t-.065)/.365)
 if t<.515:return 1.
 if t<.88:return 1-ease((t-.515)/.365)
 return 0.

def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

class Author:
 def __init__(self,spec):
  self.spec=spec;self.id=spec['exerciseId'];self.family=spec['animationId'];self.equipment=spec['equipmentId'];self.metrics=[];self.moving=[]
  bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/bench_press/bench_press.blend'))
  self.human=bpy.data.objects['Athlete'];self.rig=bpy.data.objects['Athlete.rig']
  for o in list(bpy.data.objects):
   if o not in [self.human,self.rig]:bpy.data.objects.remove(o,do_unlink=True)
  self.rig.animation_data_clear();self.rig.matrix_world=Matrix.Identity(4)
  for pb in self.rig.pose.bones:pb.matrix_basis=Matrix.Identity(4);pb.rotation_mode='QUATERNION'
  self.human.matrix_parent_inverse=Matrix.Identity(4);self.human.matrix_basis=Matrix.Identity(4)
  paint(self.human,self.spec)
  self.scene=bpy.context.scene;self.scene.frame_start=1;self.scene.frame_end=FRAMES+1;self.scene.render.fps=FPS
  self.pad=material('Form upholstery',(.045,.055,.065),.85);self.frame=material('Form machine frame',(.12,.14,.16),.45,.45);self.steel=material('Form brushed steel',(.43,.48,.53),.31,.75);self.rubber=material('Form rubber',(.052,.061,.07),.65)
  self.handBasis={}
  for side,sign in [('l',1),('r',-1)]:
   b=self.rig.data.bones;w=b['hand_'+side].head_local.copy();forward=(b['middle_01_'+side].head_local-w).normalized();across=(b['index_01_'+side].head_local-b['pinky_01_'+side].head_local).normalized();across=(across-forward*across.dot(forward)).normalized()
   self.handBasis[side]=(Matrix((across,forward,across.cross(forward))).transposed(),(b['middle_01_'+side].head_local-w)*.65)
   for finger in ('index','middle','ring','pinky','thumb'):
    for index,degrees in enumerate((63,88,55) if finger!='thumb' else (25,48,55),1):
     pb=self.rig.pose.bones[f'{finger}_{index:02d}_{side}'];pb.rotation_mode='XYZ';pb.rotation_euler.x=math.radians(degrees)*(1 if sign>0 else -1)
  bpy.context.view_layer.update()
  self.set_world(Matrix.Identity(4))
 def set_world(self,world):
  self.rig.matrix_world=world;self.world=world;self.inv=world.inverted();bpy.context.view_layer.update()
 def place(self,name,head,tail):
  b=self.rig.data.bones[name];head=self.inv@head;tail=self.inv@tail
  q=(b.tail_local-b.head_local).normalized().rotation_difference((tail-head).normalized());m=q.to_matrix().to_4x4()@b.matrix_local;m.translation=head;self.rig.pose.bones[name].matrix=m;bpy.context.view_layer.update()
 def rest(self,name):return self.world@self.rig.data.bones[name].head_local
 def hand(self,side,grip,pole,forward=Vector((0,0,1)),across=None):
  sign=1 if side=='l' else -1;across=Vector((-sign,0,0)) if across is None else across.normalized();forward=forward.normalized();across=(across-forward*across.dot(forward)).normalized()
  basis,offset=self.handBasis[side];rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed();contact=rotation@offset-across.cross(forward)*sign*.012;wrist=Vector(grip)-contact
  for finger in ('index','middle','ring','pinky'):
   for i,angle in enumerate((63,88,55),1):
    name=f'{finger}_{i:02d}_{side}';pb=self.rig.pose.bones[name];axis=rotation@self.rig.data.bones[name].matrix_local.to_3x3().col[0];pb.rotation_mode='XYZ';pb.rotation_euler.x=math.radians(angle)*(1 if axis.dot(-across*sign)>0 else -1)
  b=self.rig.data.bones;shoulder=self.world@self.rig.pose.bones['upperarm_'+side].head
  elbow=two_bone(shoulder,wrist,b['upperarm_'+side].length,b['lowerarm_'+side].length,Vector(pole))
  self.place('upperarm_'+side,shoulder,elbow);self.place('lowerarm_'+side,elbow,wrist)
  m=rotation.to_4x4()@b['hand_'+side].matrix_local;m.translation=wrist;self.rig.pose.bones['hand_'+side].matrix=self.inv@m;bpy.context.view_layer.update()
  if self.spec['gripType'] in ('neutral','pronated','supinated'):
   # Oppose the thumb toward the index finger instead of retaining the bench
   # thumb's local Euler bend (which points down on a neutral vertical grip).
   thumb_base=self.world@self.rig.pose.bones['thumb_01_'+side].head
   index_contact=self.world@self.rig.pose.bones['index_02_'+side].head
   palm=-across.cross(forward)*sign
   tip=index_contact+palm*.012
   l1,l2,l3=[b[f'thumb_{i:02d}_{side}'].length for i in (1,2,3)]
   span=tip-thumb_base
   if span.length>l1+l2+l3-.006:tip=thumb_base+span.normalized()*(l1+l2+l3-.006)
   joint1=two_bone(thumb_base,tip,l1,l2+l3-.005,-forward+across*.5)
   joint2=two_bone(joint1,tip,l2,l3,palm)
   for i,(a,z) in enumerate([(thumb_base,joint1),(joint1,joint2),(joint2,tip)],1):self.place(f'thumb_{i:02d}_{side}',a,z)
  actual=(self.world@self.rig.pose.bones['hand_'+side].matrix).translation+contact
  error=(actual-Vector(grip)).length
  if error>.002:raise ValueError(f'Hand drift: {error}')
  return error
 def legs_seated(self):
  b=self.rig.data.bones
  for side,sign in [('l',1),('r',-1)]:
   hip=self.rest('thigh_'+side);ankle=Vector((sign*.27,-.75,b['foot_'+side].head_local.z))
   knee=two_bone(hip,ankle,b['thigh_'+side].length,b['calf_'+side].length,Vector((sign*.1,-.15,1)))
   self.place('thigh_'+side,hip,knee);self.place('calf_'+side,knee,ankle)
   foot=b['foot_'+side].matrix_local.copy();foot.translation=ankle;self.rig.pose.bones['foot_'+side].matrix=self.inv@foot;bpy.context.view_layer.update()
 def bench(self,angle):
  pivot=Vector((0,-.22,.50));rotation=Matrix.Rotation(math.radians(angle),4,'X');transform=Matrix.Translation(pivot)@rotation@Matrix.Translation(-pivot)
  self.set_world(transform@Matrix.Translation((0,-1.14,.565))@Matrix.Rotation(-math.pi/2,4,'X'))
  back=box('Backrest',(0,.25,.432),(.3,1.02,.085),self.pad);back.matrix_world=transform@back.matrix_world
  box('Seat',(0,-.36,.432),(.32,.28,.085),self.pad)
  for y in [-.3,.59]:
   box('Bench foot',(0,y,.04),(.55,.14,.08),self.frame);rod('Bench support',(0,y,.06),(0,y,.40),.035,self.frame)
  self.legs_seated()
 def free_weight(self,name,dumbbell=False):
  o=bpy.data.objects.new(name,None);self.scene.collection.objects.link(o)
  shaft=cylinder(name+' grip',.014,.30 if dumbbell else 1.9,self.steel,axis=(1,0,0));shaft.parent=o
  for sign in [-1,1]:
   disc=cylinder(name+' plate',.095 if dumbbell else .19,.075,self.rubber,(sign*(.115 if dumbbell else .74),0,0),(1,0,0));disc.parent=o
  self.moving.append(o);return o
 def setup_press_fly(self):
  angle=self.spec['parameters']['benchAngle'];self.bench(angle)
  self.normal=(self.world.to_3x3()@Vector((0,-1,0))).normalized();self.up=(self.world.to_3x3()@Vector((0,0,1))).normalized();self.chest=self.world@Vector((0,-.08,1.32));self.weights={};self.links={}
  machine=self.equipment.endswith('machine')
  if self.equipment=='barbell':self.bar=self.free_weight('Barbell')
  else:
   for side,sign in [('l',1),('r',-1)]:
    if machine:
     self.weights[side]=cylinder('Machine handle '+side,.015,.16,self.rubber,axis=(1,0,0));self.moving.append(self.weights[side])
     pivot=self.chest+Vector((sign*.20,0,0))-self.normal*.07 if self.family=='fly' else self.chest-self.up*.65+Vector((sign*.35,0,0))+self.normal*.10
     cylinder('Lever pivot '+side,.06,.10,self.steel,pivot,(1,0,0))
     box('Machine foot '+side,(sign*.64,.12,.04),(.16,1.25,.08),self.frame)
     rod('Machine upright '+side,(sign*.64,.38,.06),pivot,.035,self.frame)
     self.links[side]=(pivot,rod('Machine lever '+side,pivot,pivot+Vector((0,-.4,0)),.028,self.frame));self.moving.append(self.links[side][1])
    else:self.weights[side]=self.free_weight('Dumbbell_'+side,True)
 def animate_press_fly(self,down):
  self.legs_seated();errors=[]
  fly=self.family=='fly';width=(.12+.43*down) if fly else (.26+.10*down if self.equipment=='dumbbell' else .35)
  distance=(.48-.26*down) if fly else (.45-.30*down)
  center=self.chest+self.normal*distance+self.up*(.04 if fly else .03)
  if hasattr(self,'bar'):self.bar.location=center
  for side,sign in [('l',1),('r',-1)]:
   grip=center+Vector((sign*width,0,0))
   if side in self.links:
    pivot,_=self.links[side]
    if fly:
     theta=-.14+.98*down;grip=pivot+Vector((sign*.55*math.sin(theta),0,0))+self.normal*(.55*math.cos(theta))
    else:
     radius=math.hypot(.65,.35);theta=math.atan2(.35,.65)*(1-down)+math.asin(.05/radius)*down;grip=pivot+self.normal*(radius*math.sin(theta))+self.up*(radius*math.cos(theta))
   if side in self.weights:self.weights[side].location=grip
   if side in self.links:pivot,link=self.links[side];set_rod(link,pivot,grip)
   pole=Vector((sign,0,0))-self.up*.7-self.normal*.3
   errors.append(self.hand(side,grip,pole))
  return max(errors)
 def setup_hinged_press(self):
  self.bench(self.spec['parameters']['benchAngle'])
  self.press_arms={}
  params=self.spec['parameters']
  for side,sign in [('l',1),('r',-1)]:
   pivot=Vector(params['leverPivot']);pivot.x*=sign
   grip=Vector(params['handleBottom']);grip.x*=sign
   axis=Vector((1,-sign*params['convergenceAxis'],0)).normalized()
   base=Vector((sign*.65,pivot.y,.05))
   box('Press machine base '+side,(base.x,min(pivot.y,.22)/2,.05),(.14,max(1.35,abs(pivot.y)+.65),.10),self.frame)
   rod('Press upright '+side,base,pivot,.035,self.frame)
   cylinder('Press pivot bearing '+side,.065,.15,self.steel,pivot,axis)
   group=bpy.data.objects.new('Rigid press lever '+side,None);self.scene.collection.objects.link(group)
   group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   offset=grip-pivot;corner=Vector((0,offset.y,offset.z))
   def attach(o):o.parent=group;return o
   attach(rod('Press lever main '+side,(0,0,0),corner,.03,self.frame))
   attach(rod('Press handle bend '+side,corner,offset,.022,self.frame))
   attach(cylinder('Press grip '+side,.015,.16,self.rubber,offset,(1,0,0)))
   load=corner*.55+Vector((sign*.09,0,0))
   attach(cylinder('Press plate horn '+side,.025,.32,self.steel,load,(1,0,0)))
   attach(cylinder('Press plate '+side,.19,.06,self.rubber,load+Vector((sign*.07,0,0)),(1,0,0)))
   self.press_arms[side]=(pivot,offset,axis,group)
 def animate_hinged_press(self,down):
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   pivot,offset,axis,group=self.press_arms[side]
   q=Quaternion(axis,math.radians(self.spec['parameters']['leverTravelDegrees'])*(1-down))
   group.rotation_quaternion=q;grip=pivot+q@offset
   errors.append(self.hand(side,grip,Vector((sign*.5,.20,-1)),forward=q@Vector((0,0,1)),across=q@Vector((-sign,0,0))))
  return max(errors)
 def setup_decline_fly(self):
  # Reclined seated fly with fixed-axis independent rigid levers. Reference:
  # Panatta 1FW044. No telescoping rods or below-the-body decline bench.
  self.bench(self.spec['parameters']['benchAngle'])
  self.normal=(self.world.to_3x3()@Vector((0,-1,0))).normalized()
  self.up=(self.world.to_3x3()@Vector((0,0,1))).normalized()
  self.chest=self.world@Vector((0,-.08,1.32))
  tilt=math.radians(self.spec['parameters']['arcDeclination'])
  self.arc_forward=self.normal*math.cos(tilt)-self.up*math.sin(tilt)
  axis=self.arc_forward.cross(Vector((1,0,0))).normalized()
  self.fly_parts={}
  for side,sign in [('l',1),('r',-1)]:
   pivot=self.chest+Vector((sign*.17,0,0))-self.normal*.03-self.up*.06
   bearing=pivot+axis*.55
   box('Fly base '+side,(sign*.62,.15,.06),(.12,1.2,.10),self.frame)
   rod('Fly support '+side,(sign*.62,.15,.06),bearing,.035,self.frame)
   cylinder('Fly bearing '+side,.06,.12,self.steel,bearing,axis)
   group=bpy.data.objects.new('Rigid fly lever '+side,None);self.scene.collection.objects.link(group)
   group.location=bearing;group.rotation_mode='QUATERNION';self.moving.append(group)
   grip=-axis*.55+self.arc_forward*.36
   outer=-axis*.68+Vector((sign*.62,0,0))
   swivel=grip-axis*.13
   def attach(o):o.parent=group;return o
   attach(rod('Fly lever outer '+side,(0,0,0),outer,.027,self.frame))
   attach(rod('Fly lever inner '+side,outer,swivel,.025,self.frame))
   attach(rod('Fly grip support '+side,swivel,grip,.018,self.frame))
   attach(cylinder('Articulated neutral grip '+side,.015,.16,self.rubber,grip,axis))
   load=outer*.55+Vector((sign*.09,0,0))
   attach(cylinder('Fly loading plate '+side,.18,.045,self.rubber,load,(1,0,0)))
   attach(cylinder('Fly weight horn '+side,.025,.26,self.steel,load,(1,0,0)))
   self.fly_parts[side]=(bearing,axis,grip,group)
 def animate_decline_fly(self,opened):
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   bearing,axis,offset,group=self.fly_parts[side]
   q=Quaternion(axis*sign,-.09+1.20*opened)
   group.rotation_quaternion=q;grip=bearing+q@offset
   errors.append(self.hand(side,grip,Vector((sign,0,0))-self.up*.6-self.normal*.2,forward=axis,across=-(q@self.arc_forward)))
  return max(errors)
 def machine_tower(self):
  # The athlete faces -Y. Put the tower in FRONT of the seat, not behind it.
  tower_y=-1.45
  box('Tower base',(0,tower_y,.045),(1.25,.45,.09),self.frame)
  for x in [-.22,.22]:rod('Tower rail',(x,tower_y,.08),(x,tower_y,2.12),.025,self.steel)
  box('Pulley housing',(0,tower_y,2.13),(.58,.30,.12),self.frame)
  for z in [ .16+i*.045 for i in range(12)]:box('Stack plate',(0,tower_y,z),(.42,.25,.035),self.rubber,.005)
  rod('Cable overhead boom',(0,tower_y,2.13),(0,-.53,2.13),.038,self.frame)
  cylinder('Pulley',.07,.05,self.rubber,(0,-.53,2.12),(1,0,0))
  cylinder('Rear pulley',.07,.05,self.rubber,(0,-1.45,2.12),(1,0,0))
  rod('Overhead cable',(0,-1.45,2.19),(0,-.53,2.19),.004,self.rubber)
 def setup_pulldown(self):
  before=set(bpy.data.objects)
  self.bench(85)
  for o in set(bpy.data.objects)-before:
   if o.name!='Seat':bpy.data.objects.remove(o,do_unlink=True)
  rod('Seat post',(0,-.36,.08),(0,-.36,.40),.04,self.frame)
  box('Pulldown chassis',(0,-.85,.075),(.12,1.4,.10),self.frame)
  box('Seat stabilizer',(0,-.18,.04),(.65,.14,.08),self.frame)
  self.machine_tower();self.width=self.spec['parameters']['gripWidth']
  self.handle=bpy.data.objects.new('Pulldown grip',None);self.scene.collection.objects.link(self.handle);self.moving.append(self.handle)
  if self.equipment=='mag_pulldown':
   # Original geometry guided by manufacturer CN001/MN004/WG007 photos.
   # A coated flat web and facing palm supports, not a round lat bar.
   verts=[];faces=[];steps=32
   for i in range(steps+1):
    u=-1+2*i/steps;x=u*self.width/2
    z=.09*max(0,1-abs(u)*1.5)**2-.025*math.sin(math.pi*abs(u))
    for y,dz in [(-.012,-.022),(.012,-.022),(.012,.022),(-.012,.022)]:verts.append((x,y,z+dz))
   for i in range(steps):
    for k in range(4):faces.append((4*i+k,4*i+(k+1)%4,4*(i+1)+(k+1)%4,4*(i+1)+k))
   faces.extend([(3,2,1,0),(4*steps,4*steps+1,4*steps+2,4*steps+3)])
   mesh=bpy.data.meshes.new('Coated grip web');mesh.from_pydata(verts,[],faces);mesh.update()
   o=bpy.data.objects.new('MAG shared web',mesh);self.scene.collection.objects.link(o);o.parent=self.handle;o.data.materials.append(self.rubber)
   bpy.context.view_layer.objects.active=o;o.select_set(True)
   bevel=o.modifiers.new('Rounded coated edge','BEVEL');bevel.width=.006;bevel.segments=3;bpy.ops.object.modifier_apply(modifier=bevel.name)
   for sign in [-1,1]:
    o=box('MAG palm support',(sign*(self.width/2-.008),0,.02),(.018,.10,.085),self.rubber,.008);o.parent=self.handle
    o=cylinder('MAG finger lip',.013,.10,self.rubber,(sign*self.width/2,0,.054),(0,1,0));o.parent=self.handle
   bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=8,location=(0,0,.125),major_radius=.018,minor_radius=.005,rotation=(math.pi/2,0,0))
   o=bpy.context.object;o.name='Grip attachment eye';o.data.materials.append(self.steel);o.parent=self.handle
  else:
   o=cylinder('Lat bar center',.015,self.width+.08,self.steel,axis=(1,0,0));o.parent=self.handle
   for sign in [-1,1]:
    o=rod('Lat bar angled end',(sign*(self.width/2+.04),0,0),(sign*(self.width/2+.18),0,-.10),.015,self.steel);o.parent=self.handle
  self.cable_end_offset=.145 if self.equipment=='mag_pulldown' else .035
  if self.equipment!='mag_pulldown':
   o=rod('Lat bar attachment',(0,0,0),(0,0,.035),.006,self.steel);o.parent=self.handle
  cylinder('Thigh restraint',.065,.58,self.pad,(0,-.58,.62),(1,0,0))
  rod('Thigh pad support',(0,-1.45,.62),(0,-.58,.62),.025,self.frame)
  self.cable=rod('Pulldown cable',(0,-.53,2.12),(0,-.53,1.5),.004,self.rubber);self.moving.append(self.cable)
  self.stack=box('Selected weight plates',(0,-1.45,.77),(.42,.25,.24),self.rubber,.006);self.moving.append(self.stack)
  self.return_cable=rod('Stack cable',(0,-1.45,2.12),(0,-1.45,.89),.004,self.rubber);self.moving.append(self.return_cable)
  shoulder=self.rest('upperarm_l')
  across=Vector((0,1,0)) if self.spec['gripType']=='neutral' else Vector((-1,0,0))
  forward=Vector((0,0,1));basis,offset=self.handBasis['l']
  rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
  contact=rotation@offset-across.cross(forward)*.012
  dx=self.width/2-contact.x-shoulder.x;dy=-.53-contact.y-shoulder.y
  reach=sum(self.rig.data.bones[n+'_l'].length for n in ('upperarm','lowerarm'))-.002
  self.grip_top=shoulder.z+math.sqrt(reach*reach-dx*dx-dy*dy)+contact.z
  self.grip_bottom=shoulder.z+self.spec['parameters'].get('bottomHandHeight',.07)
  self.grip_bottom_y=shoulder.y-self.spec['parameters'].get('bottomHandForward',.12)
 def animate_pulldown(self,down):
  z=self.grip_top+(self.grip_bottom-self.grip_top)*down;y=-.53+(self.grip_bottom_y+.53)*down;self.handle.location=(0,y,z)
  set_rod(self.cable,(0,-.53,2.12),(0,y,z+self.cable_end_offset));self.stack.location.z=.77+down*(self.grip_top-self.grip_bottom)
  set_rod(self.return_cable,(0,-1.45,2.12),(0,-1.45,self.stack.location.z+.12))
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   across=Vector((0,1,0)) if self.spec['gripType']=='neutral' else Vector((-sign,0,0))
   errors.append(self.hand(side,Vector((sign*self.width/2,y,z)),Vector((sign*self.spec['parameters']['elbowPlane'],-.3,-1)),across=across))
  return max(errors)
 def setup_linear_row(self):
  # DELTA DF001A: buttock pad + front footplate + inclined linear rails.
  # The demonstrated start/end positions are from the installed-machine demo.
  angle=math.radians(self.spec['parameters']['torsoLean'])
  hip=Vector((0,0,1))
  self.set_world(Matrix.Translation((0,0,.06))@Matrix.Translation(hip)@Matrix.Rotation(angle,4,'X')@Matrix.Translation(-hip))
  bones=self.rig.data.bones
  for side,sign in [('l',1),('r',-1)]:
   h=self.rest('thigh_'+side);ankle=Vector((sign*.18,-.41,0))
   leg_length=bones['thigh_'+side].length+bones['calf_'+side].length
   ankle.z=h.z-math.sqrt((leg_length*.98)**2-(ankle.x-h.x)**2-(ankle.y-h.y)**2)
   self.foot_height=ankle.z-bones['foot_'+side].head_local.z
   knee=two_bone(h,ankle,bones['thigh_'+side].length,bones['calf_'+side].length,Vector((0,-1,0)))
   self.place('thigh_'+side,h,knee);self.place('calf_'+side,knee,ankle)
   foot=bones['foot_'+side].matrix_local.copy();foot.translation=ankle
   self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
  bpy.context.view_layer.update()
  pad=box('Buttock support',(0,.10,.93),(.35,.09,.36),self.pad)
  pad.rotation_euler.x=angle
  rod('Rear pad post',(0,.32,.08),(0,.13,.94),.035,self.frame)
  box('Front footplate',(0,-.52,self.foot_height-.03),(.74,.38,.06),self.rubber)
  box('Linear row base',(0,-.50,.05),(1.40,1.80,.10),self.frame)
  self.row_start=Vector(self.spec['parameters']['gripStart'])
  self.row_end=Vector(self.spec['parameters']['gripEnd'])
  travel=(self.row_end-self.row_start).normalized()
  self.row_group=bpy.data.objects.new('Linear carriage assembly',None);self.scene.collection.objects.link(self.row_group);self.moving.append(self.row_group)
  grip_width=self.spec['parameters']['gripWidth'];self.row_width=grip_width
  def attach(o):o.parent=self.row_group;return o
  attach(cylinder('Upper carriage crossbar',.02,1.1,self.steel,(0,-.15,.07),(1,0,0)))
  for sign in [-1,1]:
   rail_offset=Vector((sign*.55,-.15,.07))
   a=self.row_start+rail_offset-travel*((self.row_start.z+rail_offset.z-.09)/travel.z);b=self.row_end+rail_offset+travel*.12
   rod('Linear guide',a,b,.022,self.steel)
   rod('Rail frame support',(sign*.55,.29,.08),b,.032,self.frame)
   attach(cylinder('Linear carriage bearing',.035,.16,self.frame,rail_offset,travel))
   attach(rod('Angled handle connection',(sign*.52,-.15,.07),(sign*grip_width/2,0,0),.018,self.steel))
   attach(cylinder('Row pronated grip',.014,.17,self.rubber,(sign*grip_width/2,0,0),(1,0,0)))
   attach(cylinder('Row weight horn',.025,.28,self.steel,(sign*.68,-.15,.07),(1,0,0)))
   attach(cylinder('Row plate',.18,.05,self.rubber,(sign*.68,-.15,.07),(1,0,0)))
 def animate_linear_row(self,pulled):
  center=self.row_start.lerp(self.row_end,pulled);self.row_group.location=center
  return max(self.hand(side,center+Vector((sign*self.row_width/2,0,0)),Vector((sign*.15,1,-.25)),forward=Vector((0,-.3,-.954))) for side,sign in [('l',1),('r',-1)])
 def setup_lever_row(self):
  params=self.spec['parameters'];angle=params['benchAngle'];self.bench(angle)
  bpy.data.objects.remove(bpy.data.objects['Backrest'],do_unlink=True)
  for o in list(self.scene.objects):
   if o.name.startswith(('Bench foot','Bench support')) and o.location.y>0:bpy.data.objects.remove(o,do_unlink=True)
  normal=(self.world.to_3x3()@Vector((0,-1,0))).normalized()
  chest=self.world@Vector((0,-.08,1.32))
  pad=box('Row chest support',chest+normal*.075-Vector((0,0,.035)),(.28,.085,.28),self.pad)
  pad.rotation_euler.x=math.radians(angle-90)
  rod('Chest pad support',(0,pad.location.y,.07),pad.location,.035,self.frame)
  if params.get('thighRestraint',False):
   cylinder('Row thigh restraint',.06,.60,self.pad,(0,-.59,.60),(1,0,0))
   rod('Row thigh support',(0,pad.location.y,.50),(0,-.59,.60),.026,self.frame)
  self.row_levers={}
  for side,sign in [('l',1),('r',-1)]:
   pivot=Vector(params['leverPivot']);pivot.x*=sign
   grip=Vector(params['handleStart']);grip.x*=sign
   axis=Vector((1,-sign*params.get('convergenceAxis',0),0)).normalized()
   box('Row chassis '+side,(sign*.64,-.35,.05),(.14,1.55,.10),self.frame)
   rod('Row front upright '+side,(sign*.64,pivot.y,.07),pivot,.035,self.frame)
   cylinder('Row pivot '+side,.065,.14,self.steel,pivot,axis)
   group=bpy.data.objects.new('Rigid row lever '+side,None);self.scene.collection.objects.link(group)
   group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   offset=grip-pivot;corner=Vector(params.get('leverElbow',(0,offset.y+.30,-.12)));lower=Vector((0,offset.y,offset.z))
   def attach(o):o.parent=group;return o
   attach(rod('Row upper lever '+side,(0,0,0),corner,.03,self.frame))
   attach(rod('Row descending lever '+side,corner,lower,.03,self.frame))
   attach(rod('Row grip offset '+side,lower,offset,.022,self.frame))
   attach(cylinder('Row grip '+side,.015,.17,self.rubber,offset,(1,0,0)))
   loading=Vector(params.get('loadingOffset',corner))
   if (loading-corner).length>.01:attach(rod('Row counter lever '+side,(0,0,0),loading,.03,self.frame))
   attach(cylinder('Row loading horn '+side,.025,.30,self.steel,loading+Vector((sign*.13,0,0)),(1,0,0)))
   attach(cylinder('Row working plate '+side,.19,.06,self.rubber,loading+Vector((sign*.08,0,0)),(1,0,0)))
   self.row_levers[side]=(pivot,offset,axis,group)
 def animate_lever_row(self,pulled):
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   pivot,offset,axis,group=self.row_levers[side]
   q=Quaternion(axis,math.radians(self.spec['parameters']['leverTravelDegrees'])*pulled)
   group.rotation_quaternion=q
   pole=Vector(self.spec['parameters'].get('elbowPole',(.3,1,-.2)));pole.x*=sign
   errors.append(self.hand(side,pivot+q@offset,pole,forward=q@Vector(self.spec['parameters'].get('handForward',(0,-1,0)))))
  return max(errors)
 def setup_chin_up(self):
  self.width=self.spec['parameters']['gripWidth'];self.grip_z=2.0
  self.tower_y=-.72
  for x in [-.73,.73]:
   box('Pullup foot',(x,-.25,.04),(.15,1.35,.08),self.frame)
   rod('Pullup column',(x,self.tower_y,.08),(x,self.tower_y,2.12),.04,self.frame)
  rod('Pullup crossbar',(-.73,self.tower_y,2.12),(.73,self.tower_y,2.12),.04,self.frame)
  for x in [-.55,.55]:rod('Overhead bar support',(x,self.tower_y,2.12),(x,-.22,2.0),.025,self.frame)
  cylinder('Pullup grip bar',.015,1.15,self.steel,(0,-.22,self.grip_z),(1,0,0))
  shoulder=self.rest('upperarm_l');dx=self.width/2-shoulder.x;dy=-.22+.012-shoulder.y
  bones=self.rig.data.bones;reach=bones['upperarm_l'].length+bones['lowerarm_l'].length-.035
  self.root_bottom=self.grip_z-.054-shoulder.z-math.sqrt(reach**2-dx*dx-dy*dy)
  self.assist=None;self.assist_links=[];self.assist_radius=.65
  if self.equipment=='assisted_pullup':
   self.animate_chin_up(0)
   knees=[self.world@self.rig.pose.bones['calf_'+side].head for side in ['l','r']]
   self.pad_origin=sum(knees,Vector())/2-Vector((0,0,.05))
   self.assist=box('Assisted knee platform',self.pad_origin,(.47,.30,.09),self.pad);self.moving.append(self.assist)
   self.pad_bracket=rod('Knee platform carrier',self.pad_origin-Vector((0,0,.28)),self.pad_origin,.027,self.frame);self.moving.append(self.pad_bracket)
   for dz in [.13,.27]:
    pivot=self.pad_origin+Vector((0,-self.assist_radius,-dz))
    cylinder('Assist linkage pivot',.055,.16,self.steel,pivot,(1,0,0))
    link=rod('Parallel assistance lever',pivot,self.pad_origin-Vector((0,0,dz)),.023,self.frame)
    self.assist_links.append((pivot,dz,link));self.moving.append(link)
   for sign in [-1,1]:
    for height,y in [(.28,.20),(.51,-.07)]:
     box('Access step',(sign*.52,y,height),(.25,.27,.055),self.rubber)
     rod('Step support',(sign*.52,self.tower_y,height),(sign*.52,y,height),.025,self.frame)
   # Counterweight is driven by the same assist travel, not an unrelated loop.
   self.counterweight=box('Assistance counterweight',(0,self.tower_y-.12,.18),(.34,.22,.24),self.rubber);self.moving.append(self.counterweight)
   for x in [-.19,.19]:rod('Counterweight guide',(x,self.tower_y-.12,.06),(x,self.tower_y-.12,1.23),.012,self.steel)
   rod('Assist pivot support',(0,self.tower_y,.05),(0,self.tower_y,1.45),.03,self.frame)
   self.assist_pulley=Vector((0,self.tower_y-.12,1.45))
   cylinder('Assistance pulley',.065,.055,self.rubber,self.assist_pulley,(1,0,0))
   cable_end=self.pad_origin-Vector((0,0,.27))
   self.assist_cable_length=(cable_end-self.assist_pulley).length
   self.assist_cables=[rod('Assist platform cable',self.assist_pulley,cable_end,.004,self.rubber),rod('Assist counterweight cable',self.assist_pulley,(0,self.tower_y-.12,.67),.004,self.rubber)]
   self.moving.extend(self.assist_cables)
 def animate_chin_up(self,up):
  rise=.34*up
  shift_y=self.assist_radius*(math.sqrt(1-(rise/self.assist_radius)**2)-1) if self.equipment=='assisted_pullup' else 0
  root=self.root_bottom+rise;self.set_world(Matrix.Translation((0,shift_y,root)))
  knees=[];b=self.rig.data.bones
  for side,sign in [('l',1),('r',-1)]:
   hip=self.rest('thigh_'+side);ankle=Vector((sign*.13,.28+shift_y,.56+root));knee=two_bone(hip,ankle,b['thigh_'+side].length,b['calf_'+side].length,Vector((0,-1,0)))
   knees.append(knee);self.place('thigh_'+side,hip,knee);self.place('calf_'+side,knee,ankle)
   foot=Matrix.Rotation(math.radians(65),4,'X')@b['foot_'+side].matrix_local;foot.translation=ankle
   self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
  if self.assist:
   pad=sum(knees,Vector())/2-Vector((0,0,.05));self.assist.location=pad
   set_rod(self.pad_bracket,pad-Vector((0,0,.28)),pad)
   for pivot,dz,link in self.assist_links:
    endpoint=pad-Vector((0,0,dz))
    if abs((endpoint-pivot).length-self.assist_radius)>.002:raise ValueError('Assistance linkage changed length')
    set_rod(link,pivot,endpoint)
   cable_end=pad-Vector((0,0,.27))
   self.counterweight.location.z=.55+(cable_end-self.assist_pulley).length-self.assist_cable_length
   set_rod(self.assist_cables[0],self.assist_pulley,cable_end)
   set_rod(self.assist_cables[1],self.assist_pulley,self.counterweight.location+Vector((0,0,.12)))
  return max(self.hand(side,Vector((sign*self.width/2,-.22,self.grip_z)),Vector((sign*.55,-.12,-1))) for side,sign in [('l',1),('r',-1)])
 def setup_back_extension(self):
  b=self.rig.data.bones
  self.hinge_local=(b['thigh_l'].head_local+b['thigh_r'].head_local)/2
  self.hinge_position=Vector((0,0,1.05))
  self.hinge_angle=math.radians(self.spec['parameters'].get('benchAngle',45))
  self.hinge_base=Matrix.Translation(self.hinge_position)@Matrix.Rotation(self.hinge_angle,4,'X')@Matrix.Translation(-self.hinge_local)
  self.set_world(self.hinge_base)
  self.fixed_legs={}
  for bone in sorted(b,key=lambda x:len(x.parent_recursive)):
   if bone.name in ('thigh_l','thigh_r') or any(p.name in ('thigh_l','thigh_r') for p in bone.parent_recursive):
    self.fixed_legs[bone.name]=self.world@bone.matrix_local
  pad_local=Vector((0,-.135,self.hinge_local.z-.19))
  for sign in [-1,1]:
   local=pad_local+Vector((sign*.13,0,0))
   pad=box('Roman split thigh pad',(0,0,0),(.24,.12,.30),self.pad)
   pad.matrix_world=self.hinge_base@Matrix.Translation(local)
  foot_local=Vector((0,-.10,-.04));foot_world=self.hinge_base@foot_local
  foot=box('Roman foot platform',(0,0,0),(.54,.34,.06),self.rubber)
  foot.matrix_world=self.hinge_base@Matrix.Translation(foot_local)
  calf_world=self.hinge_base@Vector((0,.115,.28))
  cylinder('Roman calf restraint',.065,.50,self.pad,calf_world,(1,0,0))
  pad_world=self.hinge_base@pad_local
  rod('Roman angled frame',foot_world,pad_world,.045,self.frame)
  rod('Roman front support',(0,pad_world.y,.07),pad_world,.035,self.frame)
  rod('Roman calf bracket',foot_world+Vector((0,.10,0)),calf_world,.027,self.frame)
  for y in (pad_world.y,foot_world.y):box('Roman floor foot',(0,y,.045),(.70,.16,.09),self.frame)
  rod('Roman base beam',(0,pad_world.y,.06),(0,foot_world.y,.06),.035,self.frame)
  for sign in [-1,1]:
   rod('Roman access handle',pad_world+Vector((sign*.39,0,-.06)),pad_world+Vector((sign*.39,-.16,.04)),.018,self.rubber)
  self.held_plate=None
  if self.spec['parameters'].get('additionalWeight',0)>0:
   self.held_plate=cylinder('Optional chest plate',.14,.035,self.rubber,axis=(0,1,0));self.moving.append(self.held_plate)
 def animate_back_extension(self,down):
  angle=self.hinge_angle+math.radians(self.spec['parameters'].get('hipFlexionDegrees',80))*down
  self.set_world(Matrix.Translation(self.hinge_position)@Matrix.Rotation(angle,4,'X')@Matrix.Translation(-self.hinge_local))
  for name,matrix in self.fixed_legs.items():
   self.rig.pose.bones[name].matrix=self.inv@matrix;bpy.context.view_layer.update()
  if self.held_plate:
   self.held_plate.matrix_world=self.world@Matrix.Translation((0,-.21,1.28))@Matrix.Rotation(math.pi/2,4,'X')
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   target=self.world@Vector((sign*.13,-.21,1.28) if self.held_plate else (-sign*.12,-.16,1.40))
   rotation=self.world.to_3x3()
   errors.append(self.hand(side,target,rotation@Vector((sign*.4,-.6,-.2)),forward=rotation@Vector((0,0,1)),across=rotation@Vector((-sign,0,0))))
  return max(errors)
 def run(self):
  if self.family=='hinged_press':
   self.setup_hinged_press();animate=self.animate_hinged_press
  elif self.equipment=='lower_chest_fly_machine':
   self.setup_decline_fly();animate=self.animate_decline_fly
  elif self.family in ['press','fly'] and self.equipment in ['barbell','dumbbell','press_machine','fly_machine','shoulder_machine']:
   self.setup_press_fly();animate=self.animate_press_fly
  elif self.family=='pulldown':
   self.setup_pulldown();animate=self.animate_pulldown
  elif self.family=='linear_rail_row':
   self.setup_linear_row();animate=self.animate_linear_row
  elif self.family=='lever_row':
   self.setup_lever_row();animate=self.animate_lever_row
  elif self.family=='back_extension':
   self.setup_back_extension();animate=self.animate_back_extension
  elif self.family=='chin_up':
   self.setup_chin_up();animate=self.animate_chin_up
  else:raise NotImplementedError(f'Authoring family not ready: {self.id}')
  for frame in range(FRAMES+1):
   self.scene.frame_set(frame+1);error=animate(phase(frame/FRAMES)*self.spec['rangeOfMotion'])
   for pb in self.rig.pose.bones:key(pb)
   key(self.rig)
   for o in self.moving:key(o)
   self.metrics.append({'frame':frame,'palmAnchorErrorM':error})
  for o in [self.rig,*self.moving]:
   if not o.animation_data:continue
   action=o.animation_data.action;action.name=self.id+'_'+o.name
   for slot in action.slots:
    for layer in action.layers:
     for strip in layer.strips:
      bag=strip.channelbag(slot)
      if bag:
       for fc in bag.fcurves:
        for k in fc.keyframe_points:k.interpolation='LINEAR'
  # Shared base geometry and skinning stay unchanged; muscles are painted onto
  # the same vertex surface, never separate floating muscle objects.
  self.scene.frame_set(1)
  if opt.preview_only:
   self.fit_camera()
   (opt.output/(self.id+'.preview.metrics.json')).write_text(json.dumps(self.metrics))
   self.preview(draft=True)
   images=[self.id+'_'+label+'.png' for label in ('start','mid','end')]
   if not all((opt.output/name).is_file() and (opt.output/name).stat().st_size>0 for name in images):
    raise RuntimeError('Preview render did not produce all requested images')
   (opt.output/(self.id+'.preview.json')).write_text(json.dumps({
    'exerciseId':self.id,'mode':'preview-only','images':images,
    'frames':[1,24,47],'productionExport':False,'reviewApproved':False,
    'unchecked':['motion loop','Android','iOS','production route','appearance approval'],
   },indent=2))
   print('PREVIEW_ONLY',self.id,str(opt.output),flush=True)
   return
  path=opt.output/(self.id+'.glb')
  bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,export_anim_scene_split_object=False,export_morph=False,export_skins=True,export_def_bones=True,export_cameras=False,export_lights=False,export_extras=True,export_attributes=True,export_all_influences=False,export_materials='EXPORT')
  (opt.output/(self.id+'.metrics.json')).write_text(json.dumps(self.metrics))
  self.fit_camera()
  if opt.preview:
   bpy.ops.wm.save_as_mainfile(filepath=str(opt.output/(self.id+'.blend')))
   self.preview()
  print('AUTHORED',self.id,path.stat().st_size,flush=True)
 def fit_camera(self):
  # Fixed framing derived from evaluated geometry over the whole loop.
  # No per-frame camera movement or scaling of the athlete.
  target=self.spec['cameraTarget'];target=Vector((target[0],-target[2],target[1]))
  eye=self.spec['cameraAngle'];direction=(Vector((eye[0],-eye[2],eye[1]))-target).normalized()
  rotation=(-direction).to_track_quat('-Z','Y')
  axes=[rotation@Vector(v) for v in [(1,0,0),(0,1,0),(0,0,1)]]
  lo=[float('inf')]*3;hi=[-float('inf')]*3
  for frame in [1,24,47,72,97]:
   self.scene.frame_set(frame);graph=bpy.context.evaluated_depsgraph_get()
   for o in self.scene.objects:
    if o.type!='MESH':continue
    obj=o.evaluated_get(graph)
    for corner in obj.bound_box:
     point=obj.matrix_world@Vector(corner)
     for i,axis in enumerate(axes):
      value=point.dot(axis);lo[i]=min(lo[i],value);hi[i]=max(hi[i],value)
  center=sum((axis*((lo[i]+hi[i])/2) for i,axis in enumerate(axes)),Vector())
  eye=center+direction*5.06
  self.spec['cameraTarget']=[center.x,center.z,-center.y]
  self.spec['cameraAngle']=[eye.x,eye.z,-eye.y]
  self.spec['cameraScale']=max(hi[0]-lo[0],hi[1]-lo[1])*.56
  (opt.output/(self.id+'.camera.json')).write_text(json.dumps({k:self.spec[k] for k in ['cameraTarget','cameraAngle','cameraScale']}))
 def preview(self,draft=False):
  self.scene.render.engine='CYCLES';self.scene.cycles.samples=6 if draft else 12
  resolution=420 if draft else 700
  self.scene.render.resolution_x=resolution;self.scene.render.resolution_y=resolution;self.scene.render.resolution_percentage=100
  if draft:self.scene.render.image_settings.file_format='PNG'
  self.scene.world.use_nodes=True;self.scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.04,.05,.065,1);self.scene.world.node_tree.nodes['Background'].inputs[1].default_value=.3
  eye=self.spec['cameraAngle'];bpy.ops.object.camera_add(location=(eye[0],-eye[2],eye[1]));cam=bpy.context.object;target=self.spec['cameraTarget'];aim(cam,(target[0],-target[2],target[1]));cam.data.type='ORTHO';cam.data.ortho_scale=self.spec['cameraScale']*2;self.scene.camera=cam
  for name,pos,power,size in [('Key',(-2,-3,4),550,3),('Fill',(3,-1,3),220,3),('Rim',(0,3,3),600,2)]:
   bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;aim(light,(0,0,.65))
  frames=[(1,'start'),(24,'mid'),(47,'end')] if draft else [(1,'top'),(47,'bottom')]
  for frame,label in frames:
   self.scene.frame_set(frame);self.scene.render.filepath=str(opt.output/(self.id+'_'+label+'.png'));bpy.ops.render.render(write_still=True)

unknown=set(opt.ids.split(','))-{spec['exerciseId'] for spec in catalog}
if unknown:raise ValueError(f'Unknown exercise ids: {sorted(unknown)}')
for spec in catalog:
 if spec['exerciseId'] in opt.ids.split(','):
  if not spec.get('references') or not spec.get('review',{}).get('equipmentReference'):
   raise ValueError(f'Review actual equipment and usage before authoring {spec["exerciseId"]}')
prepare_output(opt)
for spec in catalog:
 if spec['exerciseId'] in opt.ids.split(','):
  Author(spec).run()
