# Exercise form authoring

`catalog.json` is the source of truth. The production Flutter viewer consumes the generated catalog; it does not select motion through exercise-specific screen branches. Existing bench press and incline dumbbell press retain their original GLBs and legacy camera behavior.

## Reference before production

1. Inspect a manufacturer product page and actual demonstration for the specific equipment. Record URLs and observations in `docs/qa/forms_expansion_2026-09-16/reference_review.md`. Distinguish observed facts, artist-selected dimensions, and unresolved details.
2. Confirm user orientation, seat/pad contact, grip, joint path, pivot/rail position and moving equipment. Do not infer the entire machine from its name or copy another exercise's pose.
3. Set `review.equipmentReference` only after that review. The author rejects entries without a reference review.
4. Select a shared motion family and equipment recipe. Supply differences through `parameters`. New fundamentally different mechanics require a new authoring family, not a special case in the Flutter screen.
5. Generate source GLB, source Blender scene, endpoint previews and metrics into a working directory outside app assets. Check static geometry before reviewing motion. The numeric palm-anchor metric is not a visual contact or anatomical certification.
6. Copy the generated camera metadata into the catalog. Camera fitting measures evaluated geometry across a complete loop, keeping one fixed view.
7. Pack assets, generate the Dart catalog, run tests and inspect the real native renderers. Verify the production detail route as well as isolated playback.
8. Keep status `authored` until reference, static pose, motion, Android, iOS and production-route review are all complete. `verified` is a technical review state, not user appearance approval.

## Commands

Run from the repository root. Use the installed official Blender executable and an external working directory:

```
Blender --background --factory-startup --python-exit-code 1 --python tool/exercise_forms/author_forms.py -- --ids exercise_id --output /tmp/form-work --preview
python3 tool/exercise_forms/pack_assets.py /tmp/form-work --prune
python3 tool/exercise_forms/generate_catalog.py
flutter analyze
flutter test
```

For a focused native integration run, pass `--dart-define=FORM_QA_IDS=id1,id2,id1` to the exercise form expansion driver. Include reopening and inspect its screenshots; a passing nonblank-pixel assertion alone is not an appearance review.

## Assets and rights

The athlete and skeleton are reused from the project's existing `art/bench_press/bench_press.blend`; retain that source's existing license/provenance documentation. Equipment is original procedural geometry informed by product demonstrations. Manufacturer photographs, logos, videos and CAD files are not packaged in the application.

App assets contain `.form.json` scene recipes and immutable SHA-256-addressed binary chunks. Identical geometry, skin, materials and animation data share chunks where their bytes match. Packing validates chunk hashes and reports referenced capacity. `--prune` removes only generated hash-named chunks no recipe references; it does not delete source art or training data. Source `.blend`, previews and duplicate raw GLBs stay outside the app bundle.

Recipes retain logical model/animation/equipment identifiers so future asset delivery can be introduced without replacing the screen API. Download delivery is not implemented. A data entry alone cannot create an unavailable motion family: obtain and review that motion first.

## Candidate route verification

Once reference, static-pose, motion and both native-platform checks pass, use
`python3 tool/exercise_forms/generate_catalog.py --review-candidates low_row,dy_row`
to enable only those candidates in a temporary generated QA catalog. Run
`integration_test/exercise_form_route_test.dart` with matching `FORM_QA_IDS` through
the normal category picker and detail screen. Always restore the normal generated
catalog afterwards (use an EXIT trap around the test command). This does not
change the source review state. Set `productionRoute` and `verified` in the source
only after the real route succeeds. Never ship a generated file marked
`TEMPORARY QA CANDIDATES`.
