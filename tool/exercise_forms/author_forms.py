"""Blender authoring entry point. Reuses the approved athlete and joint hierarchy.
Source GLBs and previews go to --output, never duplicated in Flutter's bundle.
"""
import bpy, json, math, pathlib, sys
from mathutils import Vector, Matrix, Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(pathlib.Path(__file__).parent))
from anatomy import paint
from author_options import parse_options, prepare_output
from batch_support import run_selected
from motion_checks import validate_resisted_pull
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

def beam(name,a,b,width,depth,mat):
 a,b=Vector(a),Vector(b)
 o=box(name,(a+b)/2,(width,depth,(b-a).length),mat,.008)
 o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
 return o

def bent_tube(name,points,radius,mat):
 # Rounded continuous grip tubing; retain a straight central grasping segment.
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.resolution_u=6
 curve.bevel_depth=radius;curve.bevel_resolution=2;curve.use_fill_caps=True
 spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
 for point,co in zip(spline.bezier_points,points):
  point.co=co;point.handle_left_type='AUTO';point.handle_right_type='AUTO'
 obj=bpy.data.objects.new(name,curve);bpy.context.scene.collection.objects.link(obj);curve.materials.append(mat)
 bpy.ops.object.select_all(action='DESELECT');bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 bpy.ops.object.convert(target='MESH');obj=bpy.context.object;obj.select_set(False)
 return obj

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
  if self.spec['parameters'].get('matchedForearmRoll'):
   # Carry the grip's roll through the forearm, rather than twisting only the wrist.
   rest_axis=(b['lowerarm_'+side].tail_local-b['lowerarm_'+side].head_local).normalized()
   swing=(rotation@rest_axis).rotation_difference((wrist-elbow).normalized())
   forearm=(swing.to_matrix()@rotation).to_4x4()@b['lowerarm_'+side].matrix_local
   forearm.translation=elbow;self.rig.pose.bones['lowerarm_'+side].matrix=self.inv@forearm
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
   hip=self.rest('thigh_'+side);ankle=Vector((sign*self.spec['parameters'].get('seatedFootHalfWidth',.27),-.75,b['foot_'+side].head_local.z))
   if self.spec['parameters'].get('declineLegSupport',False):ankle=Vector((sign*.23,-.84,.32))
   knee=two_bone(hip,ankle,b['thigh_'+side].length,b['calf_'+side].length,Vector((sign*.1,-.15,1)))
   self.place('thigh_'+side,hip,knee);self.place('calf_'+side,knee,ankle)
   foot=b['foot_'+side].matrix_local.copy();foot.translation=ankle;self.rig.pose.bones['foot_'+side].matrix=self.inv@foot;bpy.context.view_layer.update()
 def bench(self,angle):
  pivot=Vector((0,-.22,.50));rotation=Matrix.Rotation(math.radians(angle),4,'X');transform=Matrix.Translation(pivot)@rotation@Matrix.Translation(-pivot)
  self.set_world(transform@Matrix.Translation((0,-1.14,.565))@Matrix.Rotation(-math.pi/2,4,'X'))
  back=box('Backrest',(0,.25,.432),(.3,1.02,.085),self.pad);back.matrix_world=transform@back.matrix_world
  box('Seat',(0,-.36,.432),(.32,.28,.085),self.pad)
  for y in [-.3,.59]:
   support=transform@Vector((0,y,.3895)) if y>0 and self.spec['parameters'].get('inclineBackSupport') else Vector((0,y,.40))
   box('Bench foot',(0,y,.04),(.55,.14,.08),self.frame);rod('Bench support',(0,y,.06),support,.035,self.frame)
  if self.spec['parameters'].get('rebuildAdjustableBench'):
   for obj in list(self.scene.objects):
    if obj.name.startswith(('Bench foot','Bench support')):bpy.data.objects.remove(obj,do_unlink=True)
   # Hinged padded back on a connected spine with a load-bearing adjustment strut.
   beam('Bench base spine',(0,-.40,.26),(0,.72,.26),.075,.10,self.frame)
   for y in [-.36,.67]:
    beam('Bench pedestal',(0,y,.07),(0,y,.26),.08,.08,self.frame)
    beam('Bench stabilizer',(-.27,y,.06),(.27,y,.06),.10,.09,self.frame)
    for x in [-.25,.25]:box('Bench floor cap',(x,y,.037),(.10,.15,.074),self.rubber,.009)
   beam('Bench seat support',(0,-.36,.26),(0,-.36,.38),.07,.09,self.frame)
   back_a=transform@Vector((0,-.25,.37));back_b=transform@Vector((0,.73,.37))
   beam('Bench back spine',back_a,back_b,.075,.07,self.frame)
   cylinder('Bench hinge',.045,.36,self.steel,back_a,(1,0,0))
   beam('Bench hinge support',(0,-.25,.26),back_a,.075,.075,self.frame)
   top=transform@Vector((0,.44,.37));bottom=Vector((0,.58,.29))
   beam('Bench adjustment strut',bottom,top,.055,.06,self.steel)
   for point in [top,bottom]:cylinder('Bench strut pivot',.027,.105,self.steel,point,(1,0,0))
   for y in [.35,.43,.51,.59,.67]:box('Bench ladder notch',(0,y,.305),(.12,.025,.05),self.frame,.003)
  self.legs_seated()
  if self.spec['parameters'].get('declineLegSupport',False):
   # Original generic ankle-restraint assembly; dimensions fit this rig.
   b=self.rig.data.bones;ankle_z=.32
   foot_level=ankle_z-b['foot_l'].head_local.z
   box('Decline foot platform',(0,-.94,foot_level-.02),(.68,.40,.04),self.rubber)
   rod('Decline support spine',(0,-.36,.35),(0,-.91,foot_level-.04),.035,self.frame)
   for sign in [-1,1]:
    rod('Decline restraint upright',(sign*.34,-.95,foot_level),(sign*.34,-.95,.45),.025,self.frame)
   cylinder('Decline ankle restraint',.055,.68,self.pad,(0,-.95,.42),(1,0,0))
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
  if self.spec['parameters'].get('constantElbowFly',False):
   # A fixed wrist radius keeps slight elbow flexion throughout the fly arc.
   # Opt-in recipe: legacy scenes retain their original trajectory.
   theta=math.radians(-5+85*down)
   for side,sign in [('l',1),('r',-1)]:
    across=self.up*sign;forward=self.normal;basis,offset=self.handBasis[side]
    rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
    contact=rotation@offset-across.cross(forward)*sign*.012
    reach=sum(self.rig.data.bones[n+'_'+side].length for n in ('upperarm','lowerarm'))*.96
    wrist=self.rest('upperarm_'+side)+(self.normal*math.cos(theta)+Vector((sign*math.sin(theta),0,0)))*reach
    grip=wrist+contact;self.weights[side].location=grip
    self.weights[side].rotation_mode='QUATERNION';self.weights[side].rotation_quaternion=Vector((1,0,0)).rotation_difference(self.up)
    errors.append(self.hand(side,grip,-self.up,forward=forward,across=across))
   return max(errors)
  fly=self.family=='fly';width=(.12+.43*down) if fly else (.26+.10*down if self.equipment=='dumbbell' else .35)
  distance=(.48-.26*down) if fly else (.45-.30*down)
  along=.04 if fly else .03
  if self.spec['parameters'].get('fullPressReach') and not fly:
   # Solve the top wrist position from this athlete's arm length. Fixed .45m
   # left the flat dumbbell press substantially flexed at its top endpoint.
   shoulder=self.rest('upperarm_l');across=Vector((-1,0,0));forward=Vector((0,0,1))
   basis,offset=self.handBasis['l'];rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
   contact=rotation@offset-across.cross(forward)*.012
   reach=sum(self.rig.data.bones[n+'_l'].length for n in ('upperarm','lowerarm'))*.99
   base=self.chest+self.up*.15+Vector((.26,0,0))-contact-shoulder
   projection=base.dot(self.normal)
   top=-projection+math.sqrt(reach*reach-(base.length_squared-projection*projection))
   bottom_width=self.spec['parameters'].get('bottomGripWidth',.72)/2
   width=.26*(1-down)+bottom_width*down
   bottom_base=self.chest+self.up*.03+Vector((bottom_width,0,0))-contact-shoulder
   projection=bottom_base.dot(self.normal)
   upper=self.rig.data.bones['upperarm_l'].length;lower=self.rig.data.bones['lowerarm_l'].length
   bottom=-projection-math.sqrt(upper*upper-(bottom_base.length_squared-projection*projection))+lower
   distance=top*(1-down)+bottom*down;along=.15*(1-down)+.03*down
  center=self.chest+self.normal*distance+self.up*along
  if self.spec['parameters'].get('barbellPressReach'):
   # A bar keeps the same grip width; the lockout stacks the load above the
   # shoulders rather than remaining perpendicular to an inclined bench.
   width=self.spec['parameters']['gripWidth']/2
   shoulder=self.rest('upperarm_l');across=Vector((-1,0,0));forward=Vector((0,0,1))
   basis,offset=self.handBasis['l'];rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
   contact=rotation@offset-across.cross(forward)*.012
   reach=sum(self.rig.data.bones[n+'_l'].length for n in ('upperarm','lowerarm'))*.99
   dx=width-contact.x-shoulder.x
   top=Vector((0,shoulder.y+contact.y,shoulder.z+math.sqrt(reach*reach-dx*dx)+contact.z))
   bottom=self.chest+self.normal*.15+self.up*.03
   center=top.lerp(bottom,down)
  if hasattr(self,'bar'):self.bar.location=center
  for side,sign in [('l',1),('r',-1)]:
   grip=center+Vector((sign*width,0,0))
   if side in self.links:
    pivot,_=self.links[side]
    if fly:
     radius=self.spec['parameters'].get('flyLeverRadius',.55)
     theta=-.14+.98*down;grip=pivot+Vector((sign*radius*math.sin(theta),0,0))+self.normal*(radius*math.cos(theta))
    else:
     forward=self.spec['parameters'].get('pressLeverForward',.35)
     radius=math.hypot(.65,forward);theta=math.atan2(forward,.65)*(1-down)+math.asin(.05/radius)*down;grip=pivot+self.normal*(radius*math.sin(theta))+self.up*(radius*math.cos(theta))
   if side in self.weights:self.weights[side].location=grip
   if side in self.links:pivot,link=self.links[side];set_rod(link,pivot,grip)
   pole=Vector((sign,0,0))-self.up*.7-self.normal*.3
   if self.spec['parameters'].get('fullPressReach') and not fly:
    across=Vector((-sign,0,0));forward=Vector((0,0,1));basis,offset=self.handBasis[side]
    rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
    wrist=grip-rotation@offset+across.cross(forward)*sign*.012
    desired_elbow=wrist-self.normal*self.rig.data.bones['lowerarm_'+side].length
    pole=desired_elbow-(self.rest('upperarm_'+side)+wrist)/2
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
  self.pulldown_tower_y=-.98
  ty=self.pulldown_tower_y
  # Dedicated HS-PD-style cable station. Frame and adjustable thigh restraint
  # carry the loads; the chrome guide rods are not the structural chassis.
  beam('Pulldown floor spine',(0,.04,.085),(0,ty-.25,.085),.12,.13,self.frame)
  for y,width in [(0,.58),(ty-.18,.72)]:
   beam('Pulldown stabilizer',(-width/2,y,.065),(width/2,y,.065),.12,.10,self.frame)
   for x in [-width/2,width/2]:box('Pulldown floor cap',(x,y,.04),(.14,.17,.08),self.rubber)
  beam('Pulldown seat pedestal',(0,-.18,.09),(0,-.27,.40),.09,.10,self.frame)
  beam('Pulldown cushion support',(0,-.18,.39),(0,-.47,.39),.07,.08,self.frame)
  for x in [-.28,.28]:
   beam('Pulldown structural column',(x,ty,.09),(x,ty,2.13),.09,.10,self.frame)
   beam('Pulldown rear brace',(x,ty-.25,.09),(x,ty,.65),.07,.08,self.frame)
  box('Pulldown rear shroud',(0,ty-.075,1.09),(.49,.04,1.90),self.frame,.025)
  box('Pulldown top crown',(0,ty,2.16),(.65,.22,.12),self.frame,.035)
  for x in [-.16,.16]:rod('Pulldown stack guide',(x,ty+.03,.13),(x,ty+.03,2.08),.013,self.steel)
  for z in [.16+i*.037 for i in range(12)]:box('Pulldown resting plate',(0,ty+.03,z),(.40,.22,.027),self.rubber,.004)
  beam('Pulldown overhead frame',(0,ty,2.16),(0,-.53,2.16),.10,.12,self.frame)
  cylinder('Pulldown front pulley',.065,.05,self.rubber,(0,-.53,2.12),(1,0,0))
  cylinder('Pulldown return pulley',.065,.05,self.rubber,(0,ty+.03,2.12),(1,0,0))
  rod('Pulldown top cable',(0,ty+.03,2.185),(0,-.53,2.185),.004,self.rubber)
  self.width=self.spec['parameters']['gripWidth']
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
  beam('Pulldown thigh adjustment mast',(0,-.67,.10),(0,-.67,.69),.075,.075,self.frame)
  beam('Pulldown thigh sliding post',(0,-.67,.43),(0,-.67,.62),.052,.052,self.steel)
  beam('Pulldown thigh cantilever',(0,-.67,.62),(0,-.58,.62),.07,.07,self.frame)
  for z in [.46,.50,.54,.58]:cylinder('Pulldown thigh height hole',.007,.078,self.rubber,(0,-.67,z),(1,0,0))
  cylinder('Pulldown thigh adjustment pin',.022,.09,self.rubber,(.055,-.67,.54),(1,0,0))
  rod('Pulldown thigh roller axle',(-.31,-.58,.62),(.31,-.58,.62),.017,self.steel)
  for x in [-.17,.17]:cylinder('Pulldown thigh roller',.073,.25,self.pad,(x,-.58,.62),(1,0,0))
  self.pulldown_initial_length=None
  self.cable=rod('Pulldown cable',(0,-.53,2.12),(0,-.53,1.5),.004,self.rubber);self.moving.append(self.cable)
  self.stack=box('Selected weight plates',(0,ty+.03,.77),(.40,.22,.24),self.rubber,.006);self.moving.append(self.stack)
  self.return_cable=rod('Stack cable',(0,ty+.03,2.12),(0,ty+.03,.89),.004,self.rubber);self.moving.append(self.return_cable)
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
  pulley=Vector((0,-.53,2.12));end=Vector((0,y,z+self.cable_end_offset))
  length=(pulley-end).length
  if self.pulldown_initial_length is None:self.pulldown_initial_length=length
  set_rod(self.cable,pulley,end);self.stack.location.z=.77+length-self.pulldown_initial_length
  ty=self.pulldown_tower_y+.03
  set_rod(self.return_cable,(0,ty,2.12),(0,ty,self.stack.location.z+.12))
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   across=Vector((0,1,0)) if self.spec['gripType']=='neutral' else Vector((-sign,0,0))
   errors.append(self.hand(side,Vector((sign*self.width/2,y,z)),Vector((sign*self.spec['parameters']['elbowPlane'],self.spec['parameters'].get('elbowForwardPlane',-.3),-1)),across=across))
  return max(errors)
 def setup_linear_row(self):
  # DELTA DF001A: buttock pad + front footplate + inclined linear rails.
  # The demonstrated start/end positions are from the installed-machine demo.
  angle=math.radians(self.spec['parameters']['torsoLean'])
  hip=Vector((0,0,1))
  self.set_world(Matrix.Translation((0,0,.06))@Matrix.Translation(hip)@Matrix.Rotation(angle,4,'X')@Matrix.Translation(-hip))
  bones=self.rig.data.bones;soles=[]
  for side,sign in [('l',1),('r',-1)]:
   h=self.rest('thigh_'+side);ankle=Vector((sign*.18,-.41,0))
   leg_length=bones['thigh_'+side].length+bones['calf_'+side].length
   ankle.z=h.z-math.sqrt((leg_length*.98)**2-(ankle.x-h.x)**2-(ankle.y-h.y)**2)
   self.foot_height=ankle.z-bones['foot_'+side].head_local.z
   knee=two_bone(h,ankle,bones['thigh_'+side].length,bones['calf_'+side].length,Vector((0,-1,0)))
   self.place('thigh_'+side,h,knee);self.place('calf_'+side,knee,ankle)
   foot=Matrix.Rotation(math.radians(-32.6),4,'X')@bones['foot_'+side].matrix_local;foot.translation=ankle
   self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
   sole_rotation=Matrix.Rotation(math.radians(-32.6),3,'X')
   soles.append(ankle+sole_rotation@Vector((0,-.075,-bones['foot_'+side].head_local.z)))
  bpy.context.view_layer.update()
  pad=box('Buttock support',(0,.10,.99),(.35,.10,.56),self.pad)
  pad.rotation_euler.x=angle
  self.row_start=Vector(self.spec['parameters']['gripStart']);self.row_end=Vector(self.spec['parameters']['gripEnd'])
  # Fit the extended start to the actual wrist anchor, not a guessed hand point.
  shoulder=self.rest('upperarm_l');forward=Vector(self.spec['parameters'].get('handForward',[0,-.3,-.954])).normalized();across=Vector((-1,0,0))
  basis,offset=self.handBasis['l'];rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
  contact=rotation@offset-across.cross(forward)*.012
  dx=self.spec['parameters']['gripWidth']/2-contact.x-shoulder.x;dy=self.row_start.y-contact.y-shoulder.y
  reach=(bones['upperarm_l'].length+bones['lowerarm_l'].length)*.985
  self.row_start.z=shoulder.z+contact.z-math.sqrt(reach*reach-dx*dx-dy*dy)
  travel=(self.row_end-self.row_start).normalized()
  for sign in [-1,1]:
   x=sign*.55
   box('Linear chassis rail',(x,-.25,.065),(.12,1.7,.13),self.frame)
   beam('Rear triangular upright',(x,.47,.10),(x,.30,1.42),.10,.12,self.frame)
   beam('Diagonal guide housing',(x,-.74,.13),(x,.30,1.42),.12,.12,self.frame)
   cylinder('Storage horn',.025,.30,self.steel,(sign*.73,.38,.55),(1,0,0))
  for y,z in [(.47,.10),(-.80,.10),(.30,1.42)]:beam('Linear chassis crossmember',(-.55,y,z),(.55,y,z),.10,.10,self.frame)
  beam('Pad support spine',(0,.42,.1),(0,.20,1.22),.09,.09,self.frame)
  beam('Pad upper bracket',(0,.20,1.22),(0,.12,1.2),.07,.07,self.frame)
  beam('Pad lower bracket',(0,.30,.73),(0,.02,.74),.07,.07,self.frame)
  # Foot support follows the planted sole; use a real plate and connected pedestal.
  sole_center=sum(soles,Vector())/2;normal=sole_rotation@Vector((0,0,1))
  plate_center=sole_center-normal*.03
  plate=box('Front footplate',plate_center,(.78,.40,.06),self.rubber);plate.rotation_euler.x=math.radians(-32.6)
  beam('Footplate pedestal',(0,-.72,.08),plate_center-normal*.04,.13,.13,self.frame)
  cylinder('Footplate angle hinge',.045,.50,self.steel,plate_center-normal*.06,(1,0,0))
  self.row_group=bpy.data.objects.new('Linear carriage assembly',None);self.scene.collection.objects.link(self.row_group);self.moving.append(self.row_group)
  grip_width=self.spec['parameters']['gripWidth'];self.row_width=grip_width
  def attach(o):o.parent=self.row_group;return o
  attach(rod('Upper carriage crossbar',(-.55,-.15,.10),(.55,-.15,.10),.023,self.steel))
  attach(rod('Lower carriage crossbar',(-.55,0,0),(.55,0,0),.022,self.steel))
  for sign in [-1,1]:
   rail_offset=Vector((sign*.55,-.15,.07))
   a=self.row_start+rail_offset-travel*((self.row_start.z+rail_offset.z-.20)/travel.z);b=self.row_end+rail_offset+travel*.20
   beam('Linear rail backing',a+Vector((0,.05,0)),b+Vector((0,.05,0)),.11,.08,self.frame)
   rod('Linear guide',a,b,.027,self.steel)
   # Tie both rail ends into the chassis; the lower guide cannot float ahead of it.
   beam('Rail lower support',(sign*.55,-.80,.10),a+Vector((0,.05,0)),.10,.10,self.frame)
   box('Rail lower end cap',a,(.12,.12,.08),self.frame)
   beam('Rail rear brace',(sign*.55,.47,.10),b,.08,.10,self.frame)
   attach(cylinder('Linear carriage bearing',.049,.23,self.frame,rail_offset,travel))
   attach(beam('Carriage fork',(sign*.55,-.15,.07),(sign*.55,.0,0),.065,.065,self.frame))
   attach(rod('Angled handle connection',(sign*.52,-.15,.10),(sign*grip_width/2,0,0),.021,self.steel))
   attach(cylinder('Row pronated grip',.017,.18,self.rubber,(sign*grip_width/2,0,0),(1,0,0)))
   attach(rod('Row neutral handle',(sign*.17,-.15,.10),(sign*.17,0,0),.017,self.rubber))
   attach(cylinder('Row weight horn',.025,.36,self.steel,(sign*.73,-.15,.07),(1,0,0)))
   for offset in [.65,.715]:attach(cylinder('Row plate',.21,.055,self.rubber,(sign*offset,-.15,.07),(1,0,0)))
 def animate_linear_row(self,pulled):
  center=self.row_start.lerp(self.row_end,pulled);self.row_group.location=center
  pole=self.spec['parameters'].get('elbowPole',[.15,1,-.25])
  return max(self.hand(side,center+Vector((sign*self.row_width/2,0,0)),Vector((sign*pole[0],pole[1],pole[2])),forward=Vector(self.spec['parameters'].get('handForward',[0,-.3,-.954]))) for side,sign in [('l',1),('r',-1)])
 def setup_lever_row(self):
  params=self.spec['parameters'];angle=params['benchAngle'];self.bench(angle)
  if params.get('rebuildDyMachine'):
   self.setup_dy_machine()
   return
  if params.get('rebuildLowRowMachine'):
   self.setup_low_row_machine()
   return
  if params.get('rebuildHighRowMachine'):
   self.setup_high_row_machine()
   return
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
 def setup_dy_machine(self):
  # Original geometry based on observed IL-DRW architecture; no vendor CAD/assets.
  params=self.spec['parameters']
  for obj in list(self.scene.objects):
   if obj.name.startswith(('Backrest','Seat','Bench ')):bpy.data.objects.remove(obj,do_unlink=True)
  # Inclined upholstery, telescoping seat, connected rectangular-tube frame.
  seat=box('DY inclined seat',(0,-.33,.445),(.34,.36,.085),self.pad,.025)
  seat.rotation_euler.x=math.radians(-8)
  beam('DY seat column',(0,-.29,.11),(0,-.29,.395),.08,.08,self.frame)
  beam('DY seat adjustment',(0,-.29,.28),(0,-.29,.405),.053,.053,self.steel)
  cylinder('DY adjustment pin',.025,.06,self.rubber,(.066,-.29,.31),(1,0,0))
  for z in [.19,.225,.26]:cylinder('DY adjustment hole',.007,.081,self.rubber,(0,-.29,z),(1,0,0))
  normal=(self.world.to_3x3()@Vector((0,-1,0))).normalized()
  chest=self.world@Vector((0,-.08,1.32))
  pad=box('DY chest pad',chest+normal*.072-Vector((0,0,.04)),(.29,.095,.36),self.pad,.025)
  pad.rotation_euler.x=math.radians(params['benchAngle']-90)
  beam('DY chest mast',(0,-.85,.13),(0,-.69,.85),.08,.10,self.frame)
  beam('DY chest bracket',(0,-.69,.85),pad.location+normal*.04,.065,.07,self.frame)
  for y in [-1.05,.25]:beam('DY base crossmember',(-.66,y,.09),(.66,y,.09),.10,.10,self.frame)
  self.row_levers={}
  for side,sign in [('l',1),('r',-1)]:
   x=sign*.66
   beam('DY base rail '+side,(x,-1.05,.09),(x,.25,.09),.10,.10,self.frame)
   for y in [-1.05,.25]:box('DY rubber foot',(x,y,.045),(.15,.22,.07),self.rubber)
   pivot=Vector(params['leverPivot']);pivot.x*=sign
   beam('DY rear upright '+side,(x,-1.05,.10),(x,-.73,1.16),.10,.10,self.frame)
   beam('DY top upright '+side,(x,-.73,1.16),pivot,.10,.10,self.frame)
   beam('DY diagonal brace '+side,(x,.25,.10),(x,-.73,1.16),.08,.08,self.frame)
   beam('DY overhead tie '+side,pivot,(x,-1.03,1.84),.09,.09,self.frame)
   for z in [.52,.91,1.35]:
    y=-1.02+(z/1.84)*.33
    cylinder('DY storage horn',.025,.29,self.steel,(x+sign*.16,y,z),(1,0,0))
   cylinder('DY pivot bearing '+side,.082,.18,self.frame,pivot,(1,0,0))
   cylinder('DY pivot cap '+side,.042,.195,self.steel,pivot,(1,0,0))
   grip=Vector(params['handleStart']);grip.x*=sign
   offset=grip-pivot;axis=Vector((1,0,0))
   group=bpy.data.objects.new('Rigid row lever '+side,None);self.scene.collection.objects.link(group)
   group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   def attach(obj):obj.parent=group;return obj
   corner=Vector((0,offset.y+.13,offset.z+.38))
   lower=Vector((0,offset.y,offset.z))
   attach(beam('DY upper moving arm '+side,(0,0,0),corner,.075,.095,self.frame))
   attach(beam('DY lower moving arm '+side,corner,lower,.065,.085,self.frame))
   attach(beam('DY handle bracket '+side,lower,offset,.045,.05,self.frame))
   attach(cylinder('DY underhand grip '+side,.019,.20,self.rubber,offset,(1,0,0)))
   # Counter-arm must raise the working plates during the concentric pull.
   loading=Vector((0,.24,-.36))
   attach(beam('DY weight carrier '+side,(0,0,0),loading,.075,.09,self.frame))
   attach(cylinder('DY working horn '+side,.025,.36,self.steel,loading+Vector((sign*.20,0,0)),(1,0,0)))
   for d in [.10,.16]:attach(cylinder('DY working plate '+side,.215,.05,self.rubber,loading+Vector((sign*d,0,0)),(1,0,0)))
   self.row_levers[side]=(pivot,offset,axis,group)
  beam('DY upper crossmember',(-.66,-1.03,1.84),(.66,-1.03,1.84),.09,.09,self.frame)
 def setup_high_row_machine(self):
  params=self.spec['parameters']
  for obj in list(self.scene.objects):
   if obj.name.startswith(('Backrest','Seat','Bench ')):bpy.data.objects.remove(obj,do_unlink=True)
  box('High row seat',(0,-.33,.445),(.34,.36,.09),self.pad,.025)
  beam('High row seat pedestal',(0,-.33,.10),(0,-.33,.39),.09,.09,self.frame)
  beam('High row seat adjustment',(0,-.33,.26),(0,-.33,.395),.06,.06,self.steel)
  cylinder('High row seat pin',.022,.06,self.rubber,(.07,-.33,.31),(1,0,0))
  for z in [.19,.225,.26]:cylinder('High row seat adjustment hole',.006,.091,self.rubber,(0,-.33,z),(1,0,0))
  normal=(self.world.to_3x3()@Vector((0,-1,0))).normalized();chest=self.world@Vector((0,-.08,1.32))
  pad=box('High row chest pad',chest+normal*.07-Vector((0,0,.035)),(.29,.09,.34),self.pad,.025)
  pad.rotation_euler.x=math.radians(params['benchAngle']-90)
  beam('High row front mast',(0,-.90,.10),(0,-.78,.94),.08,.10,self.frame)
  beam('High row chest bracket',(0,-.78,.88),pad.location+normal*.04,.06,.07,self.frame)
  for sign in [-1,1]:
   cylinder('High row thigh roller',.065,.23,self.pad,(sign*.19,-.59,.60),(1,0,0))
   beam('High row thigh arm',(0,-.82,.54),(sign*.19,-.59,.535),.055,.055,self.frame)
   rod('High row support handle',(sign*.36,-.77,.60),(sign*.36,-.77,.82),.019,self.rubber)
  for y in [-1.02,.42]:beam('High row crossmember',(-.64,y,.08),(.64,y,.08),.10,.10,self.frame)
  self.row_levers={}
  for side,sign in [('l',1),('r',-1)]:
   x=sign*.64;pivot=Vector(params['leverPivot']);pivot.x*=sign
   beam('High row base rail',(x,-1.02,.08),(x,.42,.08),.10,.10,self.frame)
   beam('High row sloping column',(x,-1.02,.08),pivot,.10,.12,self.frame)
   beam('High row rear brace',(x,.42,.08),pivot,.075,.09,self.frame)
   for y in [-1.02,.42]:box('High row floor cap',(x,y,.04),(.16,.20,.08),self.rubber)
   for z in [.36,.69,1.02]:
    y=-1.02+(pivot.y+1.02)*(z/pivot.z)
    cylinder('High row storage horn',.025,.30,self.steel,(x+sign*.17,y,z),(1,0,0))
   cylinder('High row pivot bearing',.075,.17,self.frame,pivot,(1,0,0))
   cylinder('High row pivot cap',.04,.185,self.steel,pivot,(1,0,0))
   grip=Vector(params['handleStart']);grip.x*=sign;offset=grip-pivot;axis=Vector((1,0,0))
   group=bpy.data.objects.new('Rigid high row lever '+side,None);self.scene.collection.objects.link(group);group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   def attach(obj):obj.parent=group;return obj
   top=Vector((0,offset.y,.06))
   attach(beam('High row overhead arm',(0,0,0),top,.075,.10,self.frame))
   grip_axis=Vector((-sign*math.cos(math.radians(8)),0,math.sin(math.radians(8))))
   outer=offset-grip_axis*.15;inner=offset+grip_axis*.15
   attach(bent_tube('High row continuous curved handle',[top,outer+Vector((sign*.04,0,.09)),outer,inner,inner+Vector((-sign*.025,0,.09)),Vector((inner.x,offset.y,.06))],.018,self.steel))
   attach(cylinder('High row overhand grip',.020,.20,self.rubber,offset,grip_axis))
   attach(beam('High row upper grip bridge',top,Vector((inner.x,offset.y,.06)),.045,.05,self.frame))
   loading=Vector((0,.32,-.12))
   attach(beam('High row plate carrier',(0,0,0),loading,.075,.10,self.frame))
   attach(cylinder('High row working horn',.025,.35,self.steel,loading+Vector((sign*.18,0,0)),(1,0,0)))
   for d in [.09,.15]:attach(cylinder('High row working plate',.215,.05,self.rubber,loading+Vector((sign*d,0,0)),(1,0,0)))
   self.row_levers[side]=(pivot,offset,axis,group)
  beam('High row pivot crossmember',(-.64,params['leverPivot'][1],params['leverPivot'][2]-.03),(.64,params['leverPivot'][1],params['leverPivot'][2]-.03),.09,.09,self.frame)
 def setup_low_row_machine(self):
  # IL-LR reference: chest-supported low overhand pull, independent overhead
  # pivots and upward-loaded counter-arms. Original procedural frame geometry.
  params=self.spec['parameters']
  for obj in list(self.scene.objects):
   if obj.name.startswith(('Backrest','Seat','Bench ')):bpy.data.objects.remove(obj,do_unlink=True)
  box('Low row seat',(0,-.33,.445),(.34,.35,.09),self.pad,.025)
  beam('Low row seat pedestal',(0,-.33,.09),(0,-.33,.39),.085,.085,self.frame)
  beam('Low row telescoping seat',(0,-.33,.28),(0,-.33,.40),.055,.055,self.steel)
  cylinder('Low row seat pin',.024,.06,self.rubber,(.065,-.33,.31),(1,0,0))
  normal=(self.world.to_3x3()@Vector((0,-1,0))).normalized();chest=self.world@Vector((0,-.08,1.32))
  pad=box('Low row chest pad',chest+normal*.07-Vector((0,0,.045)),(.28,.095,.38),self.pad,.025)
  pad.rotation_euler.x=math.radians(params['benchAngle']-90)
  beam('Low row chest mast',(0,-.87,.09),(0,-.70,.87),.075,.095,self.frame)
  beam('Low row chest bracket',(0,-.70,.84),pad.location+normal*.045,.06,.075,self.frame)
  rod('Low row single arm stabilizer',(0,-.69,.78),(0,-.53,.78),.02,self.rubber)
  for y in [-1.0,.28]:beam('Low row base crossmember',(-.58,y,.08),(.58,y,.08),.10,.10,self.frame)
  self.row_levers={}
  for side,sign in [('l',1),('r',-1)]:
   x=sign*.58;pivot=Vector(params['leverPivot']);pivot.x*=sign
   beam('Low row base rail',(x,-1.0,.08),(x,.28,.08),.10,.10,self.frame)
   beam('Low row lower upright',(x,-1.0,.08),(x,-.84,.86),.09,.10,self.frame)
   beam('Low row upper upright',(x,-.84,.86),pivot,.09,.10,self.frame)
   beam('Low row diagonal brace',(x,.28,.08),(x,-.84,.86),.075,.085,self.frame)
   for y in [-1.0,.28]:box('Low row floor cap',(x,y,.04),(.15,.20,.08),self.rubber)
   for z in [.34,.68,1.02]:
    y=-1.0+(pivot.y+1.0)*z/pivot.z
    cylinder('Low row storage horn',.025,.27,self.steel,(x+sign*.15,y,z),(1,0,0))
   cylinder('Low row pivot bearing',.075,.17,self.frame,pivot,(1,0,0))
   cylinder('Low row pivot cap',.037,.185,self.steel,pivot,(1,0,0))
   grip=Vector(params['handleStart']);grip.x*=sign;offset=grip-pivot;axis=Vector((1,0,0))
   group=bpy.data.objects.new('Rigid low row lever '+side,None);self.scene.collection.objects.link(group)
   group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   def attach(obj):obj.parent=group;return obj
   corner=Vector((0,offset.y,offset.z+.12))
   attach(beam('Low row descending arm',(0,0,0),corner,.07,.09,self.frame))
   grip_axis=Vector((-sign*math.cos(math.radians(25)),0,-math.sin(math.radians(25))))
   outer=offset-grip_axis*.13;inner=offset+grip_axis*.13
   attach(bent_tube('Low row angled grip carrier',[corner,outer+Vector((0,0,.075)),outer,inner],.019,self.steel))
   attach(cylinder('Low row overhand grip',.020,.20,self.rubber,offset,grip_axis))
   loading=Vector((0,.31,.10))
   attach(beam('Low row upper weight carrier',(0,0,0),loading,.075,.10,self.frame))
   attach(cylinder('Low row working horn',.025,.34,self.steel,loading+Vector((sign*.18,0,0)),(1,0,0)))
   for d in [.09,.15]:attach(cylinder('Low row working plate',.20,.05,self.rubber,loading+Vector((sign*d,0,0)),(1,0,0)))
   self.row_levers[side]=(pivot,offset,axis,group)
  for z in [.55,1.30]:
   y=-1.0+(params['leverPivot'][1]+1.0)*z/params['leverPivot'][2]
   beam('Low row frame crossmember',(-.58,y,z),(.58,y,z),.075,.085,self.frame)
 def animate_lever_row(self,pulled):
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   pivot,offset,axis,group=self.row_levers[side]
   q=Quaternion(axis,math.radians(self.spec['parameters']['leverTravelDegrees'])*pulled)
   group.rotation_quaternion=q
   pole=Vector(self.spec['parameters'].get('elbowPole',(.3,1,-.2)));pole.x*=sign
   across=None
   if self.spec['parameters'].get('matchedForearmRoll'):
    across=q@Vector((sign*(1 if self.spec['gripType']=='supinated' else -1),0,0))
    if self.spec['parameters'].get('rebuildHighRowMachine'):
     across=q@Vector((-sign*math.cos(math.radians(8)),0,math.sin(math.radians(8))))
   forward=Vector(self.spec['parameters'].get('handForward',(0,-1,0)))
   if 'handForwardEnd' in self.spec['parameters']:
    # Round grips permit the hand to roll without forcing wrist flexion as
    # the elbow closes; keep the grip axis fixed on the rigid lever.
    forward=forward.lerp(Vector(self.spec['parameters']['handForwardEnd']),pulled).normalized()
   forward=q@forward
   if self.spec['parameters'].get('rebuildLowRowMachine'):
    across=q@Vector((-sign*math.cos(math.radians(25)),0,-math.sin(math.radians(25))))
    forward=(forward-across*forward.dot(across)).normalized()
   errors.append(self.hand(side,pivot+q@offset,pole,forward=forward,across=across))
  return max(errors)
 def setup_chin_up(self):
  self.width=self.spec['parameters']['gripWidth'];self.grip_z=2.0
  self.tower_y=-.72
  for x in [-.73,.73]:
   box('Pullup foot',(x,-.25,.04),(.15,1.35,.08),self.frame)
   rod('Pullup column',(x,self.tower_y,.08),(x,self.tower_y,2.12),.04,self.frame)
  rod('Pullup crossbar',(-.73,self.tower_y,2.12),(.73,self.tower_y,2.12),.04,self.frame)
  for x in [-.55,.55]:rod('Overhead bar support',(x,self.tower_y,2.12),(x,-.22,2.0),.025,self.frame)
  if self.equipment=='assisted_pullup':
   for sign in [-1,1]:
    # Separate multi-position grip assemblies leave the centre/head path open.
    beam('Assist overhead arm',(sign*.55,self.tower_y,2.12),(sign*.55,-.22,2.0),.06,.06,self.frame)
    rod('Assist grip carrier',(sign*.55,-.22,2),(sign*.26,-.22,2),.018,self.steel)
    cylinder('Assist pronated grip',.019,.20,self.rubber,(sign*self.width/2,-.22,2),(1,0,0))
    rod('Assist wide angled grip',(sign*.55,-.22,2),(sign*.71,-.22,1.94),.019,self.rubber)
    rod('Assist neutral grip',(sign*.26,-.22,2),(sign*.26,-.43,2),.019,self.rubber)
    beam('Dip handle support',(sign*.48,self.tower_y,1.05),(sign*.48,.05,1.05),.05,.05,self.frame)
    rod('Dip handle',(sign*.48,.05,1.05),(sign*.48,.25,1.05),.02,self.rubber)
  else:
   cylinder('Pullup grip bar',.015,1.15,self.steel,(0,-.22,self.grip_z),(1,0,0))
  if self.spec['parameters'].get('rebuildAssistedChin'):
   for obj in list(self.scene.objects):
    if obj.name.startswith(('Pullup foot','Pullup column','Pullup crossbar','Overhead bar support','Assist overhead arm','Assist grip carrier')):
     bpy.data.objects.remove(obj,do_unlink=True)
   for sign in [-1,1]:
    x=sign*.52
    beam('Assist connected base rail',(x,-.84,.07),(x,.37,.07),.10,.12,self.frame)
    for y in [-.84,.37]:box('Assist rubber base cap',(x,y,.04),(.15,.20,.08),self.rubber)
    beam('Assist main lower column',(x,self.tower_y,.07),(x,self.tower_y,1.35),.085,.10,self.frame)
    beam('Assist bent middle column',(x,self.tower_y,1.35),(x,-.61,1.76),.085,.10,self.frame)
    beam('Assist angled upper column',(x,-.61,1.76),(x,-.43,2.11),.085,.10,self.frame)
    beam('Assist grip support spar',(x,-.43,2.11),(sign*.55,-.22,2.0),.065,.08,self.frame)
    bent_tube('Assist multi position carrier',[(sign*.71,-.22,1.94),(sign*.55,-.22,2.0),(sign*.26,-.22,2.0)],.019,self.steel)
    # Neutral grips are independent from the wide/pronated handles.
    beam('Assist lower rail tie',(x,self.tower_y,.13),(x,.15,.13),.08,.09,self.frame)
   beam('Assist connected rear crossmember',(-.52,self.tower_y,.13),(.99,self.tower_y,.13),.09,.10,self.frame)
   beam('Assist overhead rear crossmember',(-.52,-.43,2.11),(.52,-.43,2.11),.075,.085,self.frame)
  shoulder=self.rest('upperarm_l');dx=self.width/2-shoulder.x;dy=-.22+.012-shoulder.y
  bones=self.rig.data.bones;reach=bones['upperarm_l'].length+bones['lowerarm_l'].length-.035
  self.root_bottom=self.grip_z-.054-shoulder.z-math.sqrt(reach**2-dx*dx-dy*dy)
  if self.spec['parameters'].get('rebuildAssistedChin'):
   # Use the same palm anchor as hand(): the old constant shortened the hang.
   across=Vector((-1,0,0));forward=Vector((0,0,1));basis,offset=self.handBasis['l']
   rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
   contact=rotation@offset-across.cross(forward)*.012
   dx=self.width/2-contact.x-shoulder.x;dy=-.22-contact.y-shoulder.y
   reach=(bones['upperarm_l'].length+bones['lowerarm_l'].length)*.99
   self.root_bottom=self.grip_z-contact.z-shoulder.z-math.sqrt(reach**2-dx*dx-dy*dy)

  self.assist=None;self.assist_links=[];self.assist_radius=.65
  if self.equipment=='assisted_pullup':
   self.animate_chin_up(0)
   knees=[self.world@self.rig.pose.bones['calf_'+side].head for side in ['l','r']]
   self.pad_origin=sum(knees,Vector())/2-Vector((0,0,.05))
   self.assist=box('Assisted knee platform',self.pad_origin,(.47,.30,.09),self.pad);self.moving.append(self.assist)
   self.assist_guides=[]
   guide_top=1.30 if self.spec['parameters'].get('rebuildAssistedChin') else 1.5
   for sign in [-1,1]:
    x=sign*.21
    rod('Assist vertical guide',(x,self.tower_y,.20),(x,self.tower_y,guide_top),.020,self.steel)
    bearing=cylinder('Assist slider bearing',.037,.22,self.frame,(x,self.tower_y,self.pad_origin.z-.06));self.moving.append(bearing)
    carrier=beam('Knee platform carrier',(x,self.tower_y,self.pad_origin.z-.06),(x,self.pad_origin.y,self.pad_origin.z-.06),.06,.07,self.frame);self.moving.append(carrier)
    self.assist_guides.append((bearing,carrier))
    for height,y in [(.28,.20),(.51,-.07)]:
     box('Access step',(sign*.52,y,height),(.25,.27,.055),self.rubber)
     beam('Step support',(sign*.52,self.tower_y,height),(sign*.52,y,height),.06,.06,self.frame)
   self.assist_stack_x=.99
   box('Assist stack base',(.99,self.tower_y,.06),(.56,.48,.12),self.frame)
   box('Assist stack rear cover',(.99,self.tower_y-.18,.91),(.54,.05,1.7),self.frame)
   box('Assist stack top',(.99,self.tower_y,1.80),(.56,.44,.12),self.frame)
   for x in [.79,1.19]:rod('Counterweight guide',(x,self.tower_y,.09),(x,self.tower_y,1.72),.014,self.steel)
   for i in range(8):box('Unselected assist plate',(.99,self.tower_y,.13+i*.038),(.39,.24,.03),self.rubber,.004)
   self.assist_stack_rest=1.03 if self.spec['parameters'].get('rebuildAssistedChin') else .92
   self.counterweight=box('Assistance counterweight',(.99,self.tower_y,self.assist_stack_rest),(.39,.24,.24),self.rubber);self.moving.append(self.counterweight)
   # One fixed-length cable: knee carriage rises as its counterweight descends.
   pulley_height=1.36 if self.spec['parameters'].get('rebuildAssistedChin') else 1.66
   self.assist_pulley=Vector((0,self.tower_y,pulley_height));self.assist_stack_pulley=Vector((.99,self.tower_y,pulley_height))
   for pivot in [self.assist_pulley,self.assist_stack_pulley]:cylinder('Assistance pulley',.065,.055,self.rubber,pivot,(0,1,0))
   beam('Assist pulley support',self.assist_pulley-Vector((.3,0,0)),self.assist_stack_pulley,.06,.06,self.frame)
   rod('Assist cross cable',self.assist_pulley+Vector((0,0,.065)),self.assist_stack_pulley+Vector((0,0,.065)),.004,self.rubber)
   self.assist_cables=[rod('Assist platform cable',self.assist_pulley,(0,self.tower_y,self.pad_origin.z-.06),.004,self.rubber),rod('Assist counterweight cable',self.assist_stack_pulley,(.99,self.tower_y,1.04),.004,self.rubber)]
   self.moving.extend(self.assist_cables)
 def animate_chin_up(self,up):
  rise=self.spec['parameters'].get('assistedPullTravel',.34)*up
  shift_y=0  # Knee carriage travels vertically on fixed guide rails.
  root=self.root_bottom+rise;self.set_world(Matrix.Translation((0,shift_y,root)))
  knees=[];b=self.rig.data.bones
  for side,sign in [('l',1),('r',-1)]:
   hip=self.rest('thigh_'+side);ankle=Vector((sign*.13,.28+shift_y,.56+root));knee=two_bone(hip,ankle,b['thigh_'+side].length,b['calf_'+side].length,Vector((0,-1,0)))
   knees.append(knee);self.place('thigh_'+side,hip,knee);self.place('calf_'+side,knee,ankle)
   foot=Matrix.Rotation(math.radians(65),4,'X')@b['foot_'+side].matrix_local;foot.translation=ankle
   self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
  if self.assist:
   pad=sum(knees,Vector())/2-Vector((0,0,.05));self.assist.location=pad
   travel=pad.z-self.pad_origin.z
   for bearing,carrier in self.assist_guides:
    bearing.location.z=self.pad_origin.z-.06+travel
    carrier.location.z=self.pad_origin.z-.06+travel
   self.counterweight.location.z=self.assist_stack_rest-travel
   set_rod(self.assist_cables[0],self.assist_pulley,Vector((0,self.tower_y,pad.z-.06)))
   set_rod(self.assist_cables[1],self.assist_stack_pulley,self.counterweight.location+Vector((0,0,.12)))
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
 def setup_cable_row(self):
  # Dedicated long-row bench, not a press bench with its backrest removed.
  p=self.spec['parameters'];b=self.rig.data.bones
  hip=(b['thigh_l'].head_local+b['thigh_r'].head_local)/2
  self.set_world(Matrix.Translation((0,0,p['seatHipHeight']))@Matrix.Translation(-hip))
  box('Row bench cushion',(0,.04,p['seatHipHeight']-.105),(.38,.82,.09),self.pad)
  beam('Row bench spine',(0,.42,.12),(0,-1.20,.12),.09,.09,self.frame)
  for y in [.37,-.28]:
   beam('Row bench leg',(0,y,.07),(0,y,p['seatHipHeight']-.15),.08,.08,self.frame)
   box('Row bench foot',(0,y,.045),(.70,.14,.09),self.frame)
  pitch=math.radians(p['footplateAngle']);rotation=Matrix.Rotation(pitch,4,'X')
  for side,sign in [('l',1),('r',-1)]:
   ankle=Vector((sign*.18,p['ankleY'],p['ankleZ']));h=self.rest('thigh_'+side)
   knee=two_bone(h,ankle,b['thigh_'+side].length,b['calf_'+side].length,Vector((0,0,1)))
   self.place('thigh_'+side,h,knee);self.place('calf_'+side,knee,ankle)
   foot=rotation@b['foot_'+side].matrix_local;foot.translation=ankle
   self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
   # Sole plane and footplate share the same rotation and normal.
   sole=ankle+rotation.to_3x3()@Vector((0,-.075,-b['foot_'+side].head_local.z))
   normal=rotation.to_3x3()@Vector((0,0,1))
   plate=box('Row angled footplate '+side,sole-normal*.025,(.24,.34,.05),self.rubber);plate.rotation_euler.x=pitch
   beam('Row footplate cross tie '+side,(0,-.9,.12),(sign*.18,-.9,.12),.07,.07,self.frame)
   beam('Row footplate brace '+side,(sign*.18,-.9,.12),sole-normal*.045,.07,.07,self.frame)
  # GR616 reference: lateral selectorized tower; the user faces the low pulley.
  # Original geometry, with protected internal cable routing rather than an
  # invented exposed overhead pulldown boom.
  self.row_stack_center=Vector((.73,-.53,.64));self.row_stack_top=Vector((.73,-.53,1.72))
  box('Row tower base',(.73,-.53,.065),(.44,.85,.13),self.frame)
  box('Row tower upper cover',(.73,-.53,1.78),(.36,.77,.12),self.frame,.04)
  box('Row tower protective back',(.90,-.53,.93),(.045,.71,1.61),self.frame,.02)
  for y in [-.87,-.19]:
   rod('Row tower upright',(.73,y,.10),(.73,y,1.75),.042,self.steel)
   box('Row tower rubber foot',(.73,y,.04),(.20,.22,.08),self.rubber)
  for y in [-.68,-.38]:rod('Row stack guide',(.73,y,.13),(.73,y,1.72),.014,self.steel)
  for i in range(10):box('Row resting weight',(.73,-.53,.14+i*.032),(.23,.45,.025),self.rubber,.004)
  beam('Row tower lower connection',(0,-.75,.12),(.73,-.75,.12),.09,.10,self.frame)
  bent_tube('Row protected cable bridge',[(0,-1.12,p['pulleyHeight']),(.34,-1.12,p['pulleyHeight']),(.73,-.93,p['pulleyHeight']),(.73,-.87,p['pulleyHeight'])],.046,self.frame)
  self.row_start=Vector(p['gripStart']);self.row_end=Vector(p['gripEnd']);self.row_width=p['gripWidth']
  # Solve the nearly extended wrist, including the neutral-grip palm offset.
  shoulder=self.rest('upperarm_l');across=Vector((0,0,1));forward=Vector((0,-1,0));basis,offset=self.handBasis['l']
  rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed();contact=rotation@offset-across.cross(forward)*.012
  reach=(b['upperarm_l'].length+b['lowerarm_l'].length)*.985
  dx=self.row_width/2-contact.x-shoulder.x;dz=self.row_start.z-contact.z-shoulder.z
  self.row_start.y=shoulder.y+contact.y-math.sqrt(reach**2-dx**2-dz**2)
  self.row_group=bpy.data.objects.new('Cable row neutral handle',None);self.scene.collection.objects.link(self.row_group);self.moving.append(self.row_group)
  for sign in [-1,1]:
   o=rod('Handle yoke',(0,-.08,0),(sign*self.row_width/2,0,0),.016,self.steel);o.parent=self.row_group
   o=cylinder('Neutral row grip',.015,.14,self.rubber,(sign*self.row_width/2,0,0),(0,0,1));o.parent=self.row_group
  self.row_pulley=Vector((0,-1.12,p['pulleyHeight']))
  cylinder('Low cable pulley',.07,.05,self.rubber,self.row_pulley,(1,0,0))
  beam('Low pulley bracket',(0,-1.12,.06),self.row_pulley,.07,.07,self.frame)
  self.row_cable=rod('Row working cable',self.row_pulley,self.row_start,.004,self.rubber)
  self.row_stack=box('Row selected stack',self.row_stack_center,(.23,.45,.20),self.rubber,.006)
  self.row_return=rod('Row stack cable',self.row_stack_top,self.row_stack_center+Vector((0,0,.10)),.004,self.rubber)
  # The return path is inside the protected tower and cross tube.
  self.row_cable_length=(self.row_start+Vector((0,-.08,0))-self.row_pulley).length
  self.moving.extend([self.row_cable,self.row_stack,self.row_return])
 def animate_cable_row(self,pulled):
  center=self.row_start.lerp(self.row_end,pulled);self.row_group.location=center
  end=center+Vector((0,-.08,0));set_rod(self.row_cable,self.row_pulley,end)
  self.row_stack.location.z=self.row_stack_center.z+(end-self.row_pulley).length-self.row_cable_length
  set_rod(self.row_return,self.row_stack_top,self.row_stack.location+Vector((0,0,.10)))
  return max(self.hand(side,center+Vector((sign*self.row_width/2,0,0)),Vector((sign*.15,1,-.25)),forward=Vector((0,-1,0)),across=Vector((0,0,1))) for side,sign in [('l',1),('r',-1)])
 def setup_vertical_press(self):
  # Standing/seated variants share the vertical path and palm reach solution.
  if self.spec['parameters'].get('seated',False):self.bench(self.spec['parameters']['benchAngle'])
  else:self.set_world(Matrix.Identity(4))
  if self.equipment=='dumbbell':self.press_weights={side:self.free_weight('Overhead dumbbell '+side,True) for side in ('l','r')}
  else:self.bar=self.free_weight('Standing press barbell')
  p=self.spec['parameters'];self.press_width=p['gripWidth']
  shoulder=self.rest('upperarm_l');self.press_bottom=Vector((0,shoulder.y-p['barForward'],shoulder.z+p['bottomAboveShoulder']))
  reach=sum(self.rig.data.bones[n+'_l'].length for n in ('upperarm','lowerarm'))*p['reachRatio']
  # Solve wrist reach, then add the palm-to-grip offset used by hand().
  across=Vector((-1,0,0));forward=Vector((0,0,1));basis,offset=self.handBasis['l']
  rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed();contact=rotation@offset-across.cross(forward)*.012
  if p.get('verticalForearmPress'):
   # At the lower endpoint keep the wrist above the elbow. Solve height
   # from the actual humerus/forearm lengths and selected dumbbell spacing.
   dx=p.get('bottomGripWidth',self.press_width)/2-contact.x-shoulder.x
   dy=-p['barForward']-contact.y
   upper=self.rig.data.bones['upperarm_l'].length;lower=self.rig.data.bones['lowerarm_l'].length
   self.press_bottom.z=shoulder.z-math.sqrt(upper*upper-dx*dx-dy*dy)+lower+contact.z
  dx=self.press_width/2-contact.x-shoulder.x;dy=-p['topForward']-contact.y
  remaining=reach*reach-dx*dx-dy*dy
  if remaining<=0:raise ValueError('Standing press grip is too wide for the athlete')
  self.press_top=Vector((0,shoulder.y-p['topForward'],shoulder.z+math.sqrt(remaining)+contact.z))
 def animate_vertical_press(self,up):
  center=self.press_bottom.lerp(self.press_top,up)
  # Keep the shaft forward of the face until it has cleared the head.
  center.y=self.press_bottom.y+(self.press_top.y-self.press_bottom.y)*ease(max(0,(up-.55)/.45))
  width=self.spec['parameters'].get('bottomGripWidth',self.press_width)*(1-up)+self.press_width*up
  if hasattr(self,'press_weights'):
   for side,sign in [('l',1),('r',-1)]:self.press_weights[side].location=center+Vector((sign*width/2,0,0))
  else:self.bar.location=center
  errors=[]
  for side,sign in [('l',1),('r',-1)]:
   grip=center+Vector((sign*width/2,0,0));pole=Vector((sign*.5,-.35,-1))
   if self.spec['parameters'].get('verticalForearmPress'):
    across=Vector((-sign,0,0));forward=Vector((0,0,1));basis,offset=self.handBasis[side]
    rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
    wrist=grip-rotation@offset+across.cross(forward)*sign*.012
    desired_elbow=wrist-Vector((0,0,self.rig.data.bones['lowerarm_'+side].length))
    pole=desired_elbow-(self.rest('upperarm_'+side)+wrist)/2
   errors.append(self.hand(side,grip,pole))
  return max(errors)
 def setup_reverse_fly(self):
  p=self.spec['parameters'];self.bench(p['benchAngle'])
  if p.get('rebuildRearDeltMachine'):
   self.setup_rear_delt_machine();return
  bpy.data.objects.remove(bpy.data.objects['Backrest'],do_unlink=True)
  chest=self.world@Vector((0,-.08,1.32))
  pad=box('Reverse fly chest pad',chest+Vector((0,-.10,-.05)),(.28,.09,.30),self.pad)
  rod('Chest support post',(0,pad.location.y,.06),pad.location,.032,self.frame)
  self.reverse_parts={}
  for side,sign in [('l',1),('r',-1)]:
   shoulder=self.rest('upperarm_'+side)
   pivot=shoulder+Vector((0,0,p['pivotAboveShoulder']))
   offset=Vector((0,-p['armRadius'],-p['pivotAboveShoulder']+p['handleHeight']))
   box('Reverse fly base',(sign*.72,-.3,.05),(.12,1.25,.10),self.frame)
   # Towers outside the arm sweep; crossmember remains above the athlete.
   rod('Reverse fly upright',(sign*.72,-.05,.06),(sign*.72,-.05,pivot.z),.032,self.frame)
   rod('Reverse fly top beam',(sign*.72,-.05,pivot.z),pivot,.032,self.frame)
   cylinder('Reverse fly bearing',.055,.12,self.steel,pivot)
   group=bpy.data.objects.new('Reverse fly rigid lever '+side,None);self.scene.collection.objects.link(group);group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   corner=Vector((0,-p['armRadius'],0))
   for o in [rod('Reverse fly upper arm',(0,0,0),corner,.025,self.frame),rod('Reverse fly grip drop',corner,offset,.02,self.steel),cylinder('Reverse fly grip',.015,.16,self.rubber,offset)]:o.parent=group
   self.reverse_parts[side]=(pivot,offset,group)
 def setup_rear_delt_machine(self):
  # SS-FLY owner manual: face the long pad, horizontal inside handles,
  # shoulder-height arms. Original geometry, not a vendor CAD reproduction.
  p=self.spec['parameters']
  for obj in list(self.scene.objects):
   if obj.name.startswith(('Backrest','Seat','Bench ')):bpy.data.objects.remove(obj,do_unlink=True)
  box('Rear delt adjustable seat',(0,-.33,.437),(.34,.36,.09),self.pad,.025)
  beam('Rear delt seat outer column',(0,-.35,.10),(0,-.35,.31),.09,.10,self.frame)
  beam('Rear delt telescopic seat post',(0,-.35,.23),(0,-.35,.39),.06,.065,self.steel)
  cylinder('Rear delt seat adjust pin',.024,.065,self.rubber,(.07,-.35,.27),(1,0,0))
  for z in [.19,.225,.26]:cylinder('Rear delt seat hole',.006,.091,self.rubber,(0,-.35,z),(1,0,0))
  chest=self.world@Vector((0,-.08,1.32))
  pad=box('Rear delt long torso pad',(0,chest.y-.082,.72),(.28,.095,.48),self.pad,.028)
  beam('Rear delt pad mast',(0,pad.location.y-.065,.12),(0,pad.location.y-.065,.93),.065,.075,self.frame)
  beam('Rear delt seat spine',(0,-1.23,.095),(0,-.08,.095),.10,.11,self.frame)
  for y,width in [(-1.23,.40),(-.08,.30)]:
   beam('Rear delt stabilizer',(-width,y,.07),(width,y,.07),.11,.09,self.frame)
   for x in [-width,width]:box('Rear delt rubber foot',(x,y,.038),(.13,.19,.076),self.rubber,.009)
  # Closed weight tower with guide rods and a selected plate pack.
  box('Rear delt tower rear cover',(0,-1.33,.82),(.64,.07,1.46),self.frame,.04)
  for x in [-.29,.29]:beam('Rear delt tower side',(x,-1.18,.12),(x,-1.18,1.52),.08,.22,self.frame)
  box('Rear delt tower crown',(0,-1.18,1.52),(.65,.36,.12),self.frame,.035)
  for x in [-.18,.18]:rod('Rear delt stack guide',(x,-1.12,.17),(x,-1.12,1.47),.014,self.steel)
  for z in [.16+i*.027 for i in range(10)]:box('Rear delt resting plate',(0,-1.12,z),(.44,.22,.023),self.rubber,.004)
  self.reverse_stack=box('Rear delt moving stack',(0,-1.12,.50),(.44,.22,.13),self.rubber,.005);self.moving.append(self.reverse_stack)
  cylinder('Rear delt selector pin',.015,.05,self.frame,(0,-.98,.48),(0,1,0))
  self.reverse_parts={}
  for side,sign in [('l',1),('r',-1)]:
   shoulder=self.rest('upperarm_'+side);pivot=shoulder+Vector((0,0,p['pivotAboveShoulder']))
   # Continuous overhead supports join the tower to the two shoulder-axis pivots.
   beam('Rear delt overhead stem',(sign*.23,-1.18,1.52),(sign*.23,-.90,pivot.z+.08),.075,.085,self.frame)
   beam('Rear delt overhead arm',(sign*.23,-.90,pivot.z+.08),pivot+Vector((0,0,.08)),.075,.085,self.frame)
   cylinder('Rear delt pivot housing',.085,.085,self.frame,pivot)
   cylinder('Rear delt range adjust disc',.115,.018,self.steel,pivot-Vector((0,0,.055)))
   for degrees in [-25,0,25,50,75]:
    a=math.radians(degrees);cylinder('Rear delt range hole',.006,.022,self.rubber,pivot+Vector((.09*math.cos(a),.09*math.sin(a),-.055)))
   group=bpy.data.objects.new('Rear delt rigid arm '+side,None);self.scene.collection.objects.link(group);group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   offset=Vector((0,-p['armRadius'],-p['pivotAboveShoulder']+p['handleHeight']))
   def attach(obj):obj.parent=group;return obj
   corner=Vector((sign*.13,offset.y,.0));lower=Vector((sign*.13,offset.y,offset.z))
   attach(beam('Rear delt moving top arm',(0,0,-.075),corner,.05,.06,self.frame))
   attach(beam('Rear delt vertical drop',corner,lower,.038,.045,self.frame))
   attach(cylinder('Rear delt horizontal inside grip',.018,.23,self.rubber,offset,(1,0,0)))
   attach(rod('Rear delt grip mount',lower,offset,.017,self.steel))
   attach(bent_tube('Rear delt alternate vertical handle',[lower,lower+Vector((sign*.09,0,-.04)),lower+Vector((sign*.10,0,-.15))],.017,self.rubber))
   self.reverse_parts[side]=(pivot,offset,group)
  # The tower cover conceals internal routing; do not fabricate exposed ropes.
  # Symmetric exercise winds the two cam inputs and raises the shared stack.
 def animate_reverse_fly(self,opened):
  p=self.spec['parameters'];errors=[]
  for side,sign in [('l',1),('r',-1)]:
   pivot,offset,group=self.reverse_parts[side]
   q=Quaternion(Vector((0,0,1)),sign*math.radians(p['startAngle']+p['sweepDegrees']*opened))
   group.rotation_quaternion=q;grip=pivot+q@offset
   if p.get('rebuildRearDeltMachine'):
    errors.append(self.hand(side,grip,q@Vector((sign,0,0)),forward=q@Vector((0,-1,0)),across=q@Vector((-sign,0,0))))
   else:errors.append(self.hand(side,grip,Vector((sign*.5,0,-1)),across=q@Vector((0,1,0))))
  if p.get('rebuildRearDeltMachine'):
   self.reverse_stack.location.z=.50+math.radians(p['sweepDegrees'])*.075*opened
  return max(errors)
 def setup_curl(self):
  if self.spec['parameters'].get('seated',False):self.bench(self.spec['parameters']['benchAngle'])
  else:self.set_world(Matrix.Identity(4))
  self.curl_weights={}
  if self.equipment=='barbell':self.curl_bar=self.free_weight('Curl barbell')
  else:
   for side in ('l','r'):self.curl_weights[side]=self.free_weight('Curl dumbbell '+side,True)
 def animate_curl(self,up):
  theta=math.radians(12+113*up);forward=Vector((0,-math.sin(theta),-math.cos(theta)))
  grips=[];errors=[]
  for side,sign in [('l',1),('r',-1)]:
   shoulder=self.rest('upperarm_'+side);bones=self.rig.data.bones
   # Upper arms remain fixed beside the torso; no shoulder swing.
   upper=Vector((sign*self.spec['parameters'].get('upperArmOutward',.13),-.10,-1)).normalized()
   elbow=shoulder+upper*bones['upperarm_'+side].length
   wrist=elbow+forward*bones['lowerarm_'+side].length
   if self.spec['parameters'].get('supinating',False):
    twist=(1-up)*math.pi/2
    across=Vector((math.cos(twist),math.sin(twist)*math.cos(theta),-math.sin(twist)*math.sin(theta)))*sign
   elif self.spec['gripType']=='neutral':across=Vector((0,math.cos(theta),-math.sin(theta)))*sign
   else:across=Vector((sign*(1 if self.spec['gripType']=='supinated' else -1),0,0))
   basis,offset=self.handBasis[side];rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed()
   contact=rotation@offset-across.cross(forward)*sign*.012;grip=wrist+contact;grips.append(grip)
   if side in self.curl_weights:
    weight=self.curl_weights[side];weight.location=grip;weight.rotation_mode='QUATERNION';weight.rotation_quaternion=Vector((1,0,0)).rotation_difference(across)
   errors.append(self.hand(side,grip,elbow-(shoulder+wrist)/2,forward=forward,across=across))
  if hasattr(self,'curl_bar'):self.curl_bar.location=(grips[0]+grips[1])/2
  return max(errors)
 def setup_lower_body(self):
  # Shared planted-foot kinematics for squat and hip-hinge recipes.
  b=self.rig.data.bones
  self.lower_hip=(b['thigh_l'].head_local+b['thigh_r'].head_local)/2
  self.lower_weight=self.free_weight('Lower body load',self.equipment=='dumbbell')
 def setup_pressdown(self):
  self.machine_tower();self.pressdown_parts={};self.pressdown_initial_length=None
  p=self.spec['parameters'];self.pressdown_pulley=Vector((0,-.53,2.12))
  self.pressdown_cable=rod('Pressdown working cable',self.pressdown_pulley,(0,-.3,1.3),.004,self.rubber)
  self.pressdown_stack=box('Pressdown selected stack',(0,-1.45,.77),(.42,.25,.24),self.rubber,.006)
  self.pressdown_return=rod('Pressdown stack cable',(0,-1.45,2.12),(0,-1.45,.89),.004,self.rubber)
  self.moving.extend([self.pressdown_cable,self.pressdown_stack,self.pressdown_return])
  if p['attachment']=='bar':
   self.pressdown_bar=cylinder('Pressdown straight bar',.014,.62,self.steel,axis=(1,0,0));self.moving.append(self.pressdown_bar)
  else:
   for side in ('l',) if p.get('singleArm') else ('l','r'):
    rope=rod('Pressdown rope '+side,(0,0,0),(0,0,.4),.013,self.rubber)
    handle=rod('Pressdown rope grip '+side,(0,0,0),(0,0,.11),.013,self.rubber)
    stop=cylinder('Pressdown rope stop '+side,.028,.04,self.rubber)
    self.pressdown_parts[side]=(rope,handle,stop);self.moving.extend([rope,handle,stop])
 def animate_pressdown(self,down):
  p=self.spec['parameters'];b=self.rig.data.bones;grips={};grip_axes={};errors=[]
  theta=math.radians(90-78*down)
  forward=Vector((0,-math.sin(theta),-math.cos(theta)))
  for side,sign in [('l',1),('r',-1)]:
   shoulder=self.rest('upperarm_'+side)
   active=not p.get('singleArm') or side=='l'
   direction=forward if active else Vector((0,-.15,-1)).normalized()
   upper=Vector((sign*.05,-.30,-1)).normalized()
   elbow=shoulder+upper*b['upperarm_'+side].length;wrist=elbow+direction*b['lowerarm_'+side].length
   if self.spec['gripType']=='neutral':across=Vector((0,math.cos(theta),-math.sin(theta)))*sign if active else Vector((0,1,-.15)).normalized()*sign
   else:across=Vector((sign*(1 if self.spec['gripType']=='supinated' else -1),0,0))
   basis,offset=self.handBasis[side];rotation=Matrix((across,direction,across.cross(direction))).transposed()@basis.transposed()
   grip=wrist+rotation@offset-across.cross(direction)*sign*.012
   errors.append(self.hand(side,grip,elbow-(shoulder+wrist)/2,forward=direction,across=across))
   if active:
    grips[side]=grip;grip_axes[side]=across if across.y>=0 else -across
  center=sum(grips.values(),Vector())/len(grips)
  if p['attachment']=='bar':
   self.pressdown_bar.location=center;end=center
  else:
   # Fixed-length rope branches preserve tension instead of stretching.
   bends={side:grip-grip_axes[side]*.06 for side,grip in grips.items()}
   center=sum(bends.values(),Vector())/len(bends)
   half_span=abs(bends['l'].x-center.x)
   rise=math.sqrt(.38**2-half_span**2)
   end=center+Vector((0,0,rise))
   for side,grip in grips.items():
    rope,handle,stop=self.pressdown_parts[side];tip=grip+grip_axes[side]*.05
    set_rod(rope,end,bends[side]);set_rod(handle,bends[side],tip)
    stop.location=tip;stop.rotation_euler=grip_axes[side].to_track_quat('Z','Y').to_euler()
  length=(end-self.pressdown_pulley).length
  if self.pressdown_initial_length is None:self.pressdown_initial_length=length
  set_rod(self.pressdown_cable,self.pressdown_pulley,end)
  self.pressdown_stack.location.z=.77+length-self.pressdown_initial_length
  set_rod(self.pressdown_return,(0,-1.45,2.12),(0,-1.45,self.pressdown_stack.location.z+.12))
  return max(errors)
 def animate_lower_body(self,down):
  p=self.spec['parameters'];b=self.rig.data.bones
  shin=math.radians(p['shinDegrees']*down+2)
  thigh=math.radians(p['thighDegrees']*down+3)
  lean=math.radians(p['torsoLean']*down)
  stance=p['stanceWidth']/2
  ankle_z=b['foot_l'].head_local.z
  knee_y=-b['calf_l'].length*math.sin(shin)
  knee_z=ankle_z+b['calf_l'].length*math.cos(shin)
  lateral=stance-abs(b['thigh_l'].head_local.x)
  sagittal=math.sqrt(b['thigh_l'].length**2-lateral**2)
  hip=Vector((0,knee_y+sagittal*math.sin(thigh),knee_z+sagittal*math.cos(thigh)))
  self.set_world(Matrix.Translation(hip)@Matrix.Rotation(lean,4,'X')@Matrix.Translation(-self.lower_hip))
  for side,sign in [('l',1),('r',-1)]:
   ankle=Vector((sign*stance,0,ankle_z));knee=Vector((sign*stance,knee_y,knee_z));h=self.rest('thigh_'+side)
   self.place('thigh_'+side,h,knee);self.place('calf_'+side,knee,ankle)
   foot=Matrix.Rotation(sign*math.radians(p.get('toeOut',10)),4,'Z')@b['foot_'+side].matrix_local
   foot.translation=ankle;self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
  bpy.context.view_layer.update();errors=[]
  load=p['loadPosition']
  if load=='hanging':
   shoulder=self.rest('upperarm_l');reach=(b['upperarm_l'].length+b['lowerarm_l'].length)*.995
   center=Vector((0,p.get('barY',-.18),shoulder.z-math.sqrt(reach**2-(shoulder.y-p.get('barY',-.18))**2)))
   if p.get('hangingWristReach',False):
    across=Vector((-1,0,0));forward=Vector((0,0,-1));basis,offset=self.handBasis['l']
    rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed();contact=rotation@offset-across.cross(forward)*.012
    dx=p['gripWidth']/2-contact.x-shoulder.x;dy=center.y-contact.y-shoulder.y
    center.z=shoulder.z-math.sqrt(reach**2-dx*dx-dy*dy)+contact.z
  else:center=self.world@Vector((0,{'back':.065,'front':-.13,'goblet':-.26}[load],1.43 if load!='goblet' else 1.22))
  self.lower_weight.location=center
  if load=='goblet':
   self.lower_weight.rotation_euler.y=math.pi/2
  for side,sign in [('l',1),('r',-1)]:
   grip=center+Vector((sign*p['gripWidth']/2,0,0))
   pole=Vector((sign*.1,-1,.5)) if load=='front' else Vector((sign*.3,0,-1)) if load=='goblet' else Vector((sign*.5,.5,-1))
   forward=Vector((0,0,1)) if load=='front' else Vector((0,1,0)) if load=='goblet' else Vector((0,-1,0)) if load=='back' else Vector((0,0,-1))
   if load=='goblet':grip.z+=.075
   errors.append(self.hand(side,grip,pole,forward=forward))
  return max(errors)
 def setup_knee_machine(self):
  # One knee-centred mechanism, with the roller on the loaded side of the shin.
  self.bench(90);b=self.rig.data.bones
  self.knee_joints={};self.knee_parts={}
  curl=self.spec['parameters']['kneeAction']=='flexion'
  for side,sign in [('l',1),('r',-1)]:
   hip=self.rest('thigh_'+side);knee=hip+Vector((0,-b['thigh_'+side].length,0));self.knee_joints[side]=(hip,knee)
   pivot=knee+Vector((sign*.25,0,0))
   rod('Knee machine upright '+side,(pivot.x,pivot.y,.05),pivot,.035,self.frame)
   box('Knee machine foot '+side,(pivot.x,-.45,.04),(.14,1.25,.08),self.frame)
   cylinder('Knee aligned bearing '+side,.06,.10,self.steel,pivot,(1,0,0))
   group=bpy.data.objects.new('Knee load lever '+side,None);self.scene.collection.objects.link(group);group.location=pivot;group.rotation_mode='QUATERNION';self.moving.append(group)
   radius=b['calf_'+side].length-.055
   off=Vector((-sign*.25,.075 if curl else -.075,-radius))
   for o in [rod('Shin lever '+side,(0,0,0),(0,off.y,off.z),.026,self.frame),rod('Shin roller axle '+side,(0,off.y,off.z),off,.02,self.steel),cylinder('Ankle roller '+side,.06,.22,self.pad,off,(1,0,0))]:o.parent=group
   load=Vector((sign*.09,-off.y,-off.z)) if curl else Vector((sign*.09,off.y,off.z))
   for o in [rod('Knee resistance lever '+side,(sign*.09,0,0),load,.024,self.frame),cylinder('Knee load plate '+side,.15,.06,self.rubber,load,(1,0,0))]:o.parent=group
   self.knee_parts[side]=group
   if curl:
    cylinder('Thigh restraint '+side,.065,.25,self.pad,knee+Vector((0,.14,.105)),(1,0,0))
    rod('Thigh restraint support '+side,pivot,knee+Vector((sign*.25,.14,.105)),.022,self.frame)
   grip=hip+Vector((sign*.25,-.12,.02));cylinder('Seat grip '+side,.015,.18,self.rubber,grip,(0,1,0))
   rod('Seat grip support '+side,hip+Vector((sign*.15,0,-.15)),grip+Vector((0,.09,0)),.02,self.frame)
  self.animate_knee_machine(0)
 def animate_knee_machine(self,amount):
  p=self.spec['parameters'];b=self.rig.data.bones;errors=[]
  angle=math.radians(p['kneeStart']+(p['kneeEnd']-p['kneeStart'])*amount)
  q=Quaternion(Vector((1,0,0)),-angle);direction=q@Vector((0,0,-1))
  for side,sign in [('l',1),('r',-1)]:
   hip,knee=self.knee_joints[side];ankle=knee+direction*b['calf_'+side].length
   self.place('thigh_'+side,hip,knee);self.place('calf_'+side,knee,ankle)
   foot=q.to_matrix().to_4x4()@b['foot_'+side].matrix_local;foot.translation=ankle;self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
   self.knee_parts[side].rotation_quaternion=q
   grip=hip+Vector((sign*.25,-.12,.02));errors.append(self.hand(side,grip,Vector((sign*.4,0,-1)),forward=Vector((0,0,-1)),across=Vector((0,sign,0))))
  return max(errors)
 def setup_raise(self):
  self.raise_weights={side:self.free_weight('Raise dumbbell '+side,True) for side in ('l','r')}
 def animate_raise(self,up):
  p=self.spec['parameters'];b=self.rig.data.bones;errors=[]
  self.set_world(Matrix.Identity(4))
  theta=math.radians(p['startAngle']+(p['endAngle']-p['startAngle'])*up)
  for side,sign in [('l',1),('r',-1)]:
   shoulder=self.rest('upperarm_'+side)
   # A fixed small elbow bend follows shoulder elevation, without a curl.
   plane=math.radians(p['raisePlane'])
   radial=Vector((sign*math.cos(plane),-math.sin(plane),0))
   upper=radial*math.sin(theta)+Vector((0,0,-math.cos(theta)))
   lower=radial*math.sin(theta+math.radians(p['elbowBend']))+Vector((0,0,-math.cos(theta+math.radians(p['elbowBend']))))
   elbow=shoulder+upper*b['upperarm_'+side].length
   wrist=elbow+lower*b['lowerarm_'+side].length
   across=Vector((-sign*math.sin(plane),-math.cos(plane),0))
   basis,offset=self.handBasis[side];rotation=Matrix((across,lower,across.cross(lower))).transposed()@basis.transposed()
   grip=wrist+rotation@offset-across.cross(lower)*sign*.012
   weight=self.raise_weights[side];weight.location=grip;weight.rotation_mode='QUATERNION';weight.rotation_quaternion=Vector((1,0,0)).rotation_difference(across)
   errors.append(self.hand(side,grip,elbow-(shoulder+wrist)/2,forward=lower,across=across))
  return max(errors)
 def setup_rollout(self):
  p=self.spec['parameters'];self.rollout_hip=(self.rig.data.bones['thigh_l'].head_local+self.rig.data.bones['thigh_r'].head_local)/2
  box('Rollout knee mat',(0,.20,.02),(.75,.70,.04),self.pad)
  self.wheel=bpy.data.objects.new('Ab wheel assembly',None);self.scene.collection.objects.link(self.wheel);self.moving.append(self.wheel)
  for o in [cylinder('Ab wheel tread',p['wheelRadius'],.08,self.rubber,axis=(1,0,0)),cylinder('Ab wheel hub',p['wheelRadius']*.65,.09,self.steel,axis=(1,0,0)),cylinder('Ab wheel axle',.014,p['gripWidth']+.16,self.steel,axis=(1,0,0))]:o.parent=self.wheel
  for sign in [-1,1]:
   o=cylinder('Ab wheel rubber grip',.018,.14,self.rubber,(sign*p['gripWidth']/2,0,0),(1,0,0));o.parent=self.wheel
  self.wheel_origin_y=None
 def animate_rollout(self,out):
  p=self.spec['parameters'];b=self.rig.data.bones
  thigh=math.radians(p['thighStart']+p['thighTravel']*out);torso=math.radians(p['torsoStart']+p['torsoTravel']*out)
  hip=Vector((0,-b['thigh_l'].length*math.sin(thigh),p['kneeHeight']+b['thigh_l'].length*math.cos(thigh)))
  self.set_world(Matrix.Translation(hip)@Matrix.Rotation(torso,4,'X')@Matrix.Translation(-self.rollout_hip))
  for side,sign in [('l',1),('r',-1)]:
   h=self.rest('thigh_'+side);knee=Vector((h.x,0,p['kneeHeight']));ankle=knee+Vector((0,b['calf_'+side].length,0))
   self.place('thigh_'+side,h,knee);self.place('calf_'+side,knee,ankle)
   foot=Matrix.Rotation(math.radians(p['footPitch']),4,'X')@b['foot_'+side].matrix_local;foot.translation=ankle
   self.rig.pose.bones['foot_'+side].matrix=self.inv@foot
  bpy.context.view_layer.update()
  shoulder=self.rest('upperarm_l');forward=Vector((0,0,1));across=Vector((-1,0,0));basis,offset=self.handBasis['l']
  rotation=Matrix((across,forward,across.cross(forward))).transposed()@basis.transposed();contact=rotation@offset-across.cross(forward)*.012
  reach=(b['upperarm_l'].length+b['lowerarm_l'].length)*p['reachRatio']
  dx=p['gripWidth']/2-contact.x-shoulder.x;dz=p['wheelRadius']-contact.z-shoulder.z
  remaining=reach*reach-dx*dx-dz*dz
  if remaining<=0:raise ValueError('Rollout wheel is unreachable; adjust the kneeling recipe')
  center=Vector((0,shoulder.y+contact.y-math.sqrt(remaining),p['wheelRadius']))
  if self.wheel_origin_y is None:self.wheel_origin_y=center.y
  self.wheel.location=center;self.wheel.rotation_euler.x=-(center.y-self.wheel_origin_y)/p['wheelRadius']
  return max(self.hand(side,center+Vector((sign*p['gripWidth']/2,0,0)),Vector((sign*.2,.2,-1))) for side,sign in [('l',1),('r',-1)])
 def run(self):
  if self.family=='hinged_press':
   self.setup_hinged_press();animate=self.animate_hinged_press
  elif self.equipment in ('lower_chest_fly_machine','incline_fly_machine'):
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
  elif self.family=='row' and self.equipment=='cable_row':
   self.setup_cable_row();animate=self.animate_cable_row
  elif self.family=='overhead_press' and self.equipment in ('barbell','dumbbell'):
   self.setup_vertical_press();animate=self.animate_vertical_press
  elif self.family=='reverse_fly':
   self.setup_reverse_fly();animate=self.animate_reverse_fly
  elif self.family=='curl' and self.equipment in ('barbell','dumbbell'):
   self.setup_curl();animate=self.animate_curl
  elif self.family in ('squat', 'hinge') and self.spec['parameters'].get('plantedFeet',False):
   self.setup_lower_body();animate=self.animate_lower_body
  elif self.family=='knee_machine':
   self.setup_knee_machine();animate=self.animate_knee_machine
  elif self.family=='pressdown':
   self.setup_pressdown();animate=self.animate_pressdown
  elif self.family=='raise' and self.equipment=='dumbbell' and 'raisePlane' in self.spec['parameters']:
   self.setup_raise();animate=self.animate_raise
  elif self.family=='rollout':
   self.setup_rollout();animate=self.animate_rollout
  else:raise NotImplementedError(f'Authoring family not ready: {self.id}')
  row_checks=self.spec.get('parameters',{}).get('rebuildDyMachine') or self.spec.get('parameters',{}).get('rebuildHighRowMachine') or self.spec.get('parameters',{}).get('rebuildLowRowMachine')
  working_plates=sorted((o for o in self.scene.objects if o.name.startswith(('DY working plate','High row working plate','Low row working plate'))),key=lambda o:o.name) if row_checks else []
  if self.family=='pulldown':working_plates=[self.stack];row_checks=True
  elif self.family=='row' and self.equipment=='cable_row':working_plates=[self.row_stack];row_checks=True
  for frame in range(FRAMES+1):
   pull=phase(frame/FRAMES)*self.spec['rangeOfMotion']
   self.scene.frame_set(frame+1);error=animate(pull)
   for pb in self.rig.pose.bones:key(pb)
   key(self.rig)
   for o in self.moving:key(o)
   metric={'frame':frame,'palmAnchorErrorM':error}
   if row_checks:
    bpy.context.view_layer.update()
    metric.update(pull=pull,workingPlateZ=[o.matrix_world.translation.z for o in working_plates])
    bends={}
    for side in ['l','r']:
     b=self.rig.pose.bones;el=self.world@b['lowerarm_'+side].head;wr=self.world@b['hand_'+side].head;kn=self.world@b['middle_01_'+side].head
     bends[side]=math.degrees((wr-el).angle(kn-wr))
    metric['wristBendDegrees']=bends
   self.metrics.append(metric)
  if row_checks:validate_resisted_pull(self.metrics)
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
if getattr(opt,'continue_on_error',False):
 prepare_output(opt)
 results=run_selected([s for s in catalog if s['exerciseId'] in opt.ids.split(',')],lambda spec:Author(spec).run(),opt.output/'batch-results.json',unreviewed_draft=getattr(opt,'unreviewed_draft',False))
 raise SystemExit(1 if any(r['result']!='generated' for r in results) else 0)
for spec in catalog:
 if spec['exerciseId'] in opt.ids.split(','):
  if not getattr(opt,'unreviewed_draft',False) and (not spec.get('references') or not spec.get('review',{}).get('equipmentReference')):
   raise ValueError(f'Review actual equipment and usage before authoring {spec["exerciseId"]}')
prepare_output(opt)
for spec in catalog:
 if spec['exerciseId'] in opt.ids.split(','):
  Author(spec).run()
