# Category muscle illustrations

Produced from the same MPFB human base used by the bench-press and incline form animations. No generated reference image or third-party screenshot is incorporated. Source, commit and full CC0 asset license are recorded in ../bench_press/README.md and ../bench_press/LICENSE.MPFB-ASSETS.md.

Rebuild with Blender 4.5.3: run tool/bench_press/make_base.py first, then tool/render_category_muscles.py. MUSCLEMORY_ART_WORK selects the scratch folder containing base.blend. MUSCLEMORY_CATEGORIES optionally selects comma-separated render names. Output is assets/category_muscles/*.png.

The source human retains its proportions and matte surface. Arms are lowered using the existing skeleton. Painting uses continuous mesh vertex attributes; render-only simple subdivision improves boundary resolution. A small continuous abdominal surface relief makes belly separations visible without adding detached geometry. These adjustments do not modify any GLB used by the exercise screens.

| File | Orthographic direction | Red region |
|---|---|---|
| chest.png | Front | Pectoralis major |
| back.png | Back | Trapezius / latissimus region |
| shoulders.png | Front | Deltoids |
| arms.png | Front | Upper arms / forearms |
| legs.png | Front | Thigh and lower-leg muscle regions |
| abs.png | Front | Rectus abdominis |

Cameras have zero lateral offset, horizontal view direction, no perspective or oblique angle. Other surfaces are light neutral gray. PNGs have transparent backgrounds and are rendered offline, so category selection does not initialize six native 3D renderers. Cardio uses the Material heart-monitor icon.
