"""Reuse the approved body-tab anatomical outlines on the SAME skinned surface."""
import json
from pathlib import Path
contours=json.loads((Path(__file__).resolve().parents[2]/'art/body_tab/mask_contours.json').read_text())
contours['erectorSpinae']=[[(.022,1.25),(.055,1.22),(.072,1.12),(.065,1.03),(.032,1.01),(.022,1.1)]]
contours['lateralDeltoid']=[[(.227,1.412),(.27,1.397),(.299,1.355),(.275,1.297),(.25,1.32),(.223,1.38)]]
def spline(points):
 out=[];n=len(points)
 for i in range(n):
  a,b,c,d=[points[j%n] for j in (i-1,i,i+1,i+2)]
  for k in range(8):
   t=k/8
   out.append(tuple(.5*((2*b[q])+(-a[q]+c[q])*t+(2*a[q]-5*b[q]+4*c[q]-d[q])*t*t+(-a[q]+3*b[q]-3*c[q]+d[q])*t*t*t) for q in (0,1)))
 return out
shapes={name:[spline(points) for points in polygons] for name,polygons in contours.items()}
def inside(x,z,poly):
 if not min(p[0] for p in poly)<=x<=max(p[0] for p in poly) or not min(p[1] for p in poly)<=z<=max(p[1] for p in poly):return False
 hit=False;a=poly[-1]
 for b in poly:
  if (a[1]>z)!=(b[1]>z) and x<(b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:hit=not hit
  a=b
 return hit
front={'pectoralisMajor','anteriorDeltoid','biceps','rectusAbdominis','obliques','quadriceps','adductors'}
back={'posteriorDeltoid','triceps','trapezius','latissimusDorsi','gluteus','hamstrings','calves','erectorSpinae'}
def contains(name,v):
 x,y,z=abs(v.x),v.y,v.z
 if name=='forearms' and (x>.456 or z<1.033):return False
 if name=='lateralDeltoid' and abs(y)>.032:return False
 if name in front and y>(-.018 if z>1 and x<.21 else .015):return False
 if name in back and y<(.022 if x<.23 else .002):return False
 return any(inside(x,z,poly) for poly in shapes[name])
def coverage(name,v):
 if not contains(name,v):return 0.
 x,z=abs(v.x),v.z
 distances=[]
 for poly in shapes[name]:
  if not inside(x,z,poly):continue
  a=poly[-1]
  nearest=float('inf')
  for b in poly:
   dx,dz=b[0]-a[0],b[1]-a[1]
   t=max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)))
   nearest=min(nearest,((x-a[0]-t*dx)**2+(z-a[1]-t*dz)**2)**.5)
   a=b
  distances.append(nearest)
 t=min(1,max(distances,default=0)/.008)
 return t*t*(3-2*t)

def paint(human,spec):
 # Preserve the original press surfaces. Other families use smooth surface
 # weights, including the same approved pectoral/deltoid/triceps masks.
 if spec['category']=='胸' and spec['animationId']=='press':return
 mesh=human.data;layer=mesh.color_attributes['MuscleColor']
 primary=spec['primaryMuscles'];secondary=spec['secondaryMuscles']
 original={'pectoralisMajor':'muscle_pectoral','anteriorDeltoid':'muscle_deltoid_anterior','triceps':'muscle_triceps'}
 for v in mesh.vertices:
  rgb=[.30,.33,.35];remaining=1.
  for name in [*primary,*secondary]:
   attr=mesh.attributes.get(original.get(name,''))
   weight=(attr.data[v.index].value if attr else coverage(name,v.co))*remaining
   target=(.22,.004,.011) if name in primary else (.58,.18,.17)
   for k,base in enumerate((.30,.33,.35)):rgb[k]+=weight*(target[k]-base)
   remaining-=weight
  layer.data[v.index].color=(*rgb,1)
