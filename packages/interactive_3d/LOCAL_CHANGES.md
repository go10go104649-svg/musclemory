# Local changes to interactive_3d 2.2.0

Upstream: https://pub.dev/packages/interactive_3d/versions/2.2.0
License: MIT, retained in LICENSE.

Opt-in formAnimation adds fixed-camera local GLB animation controls on iOS (SceneKit) and Android (Filament). Other views retain upstream behavior.

- App lifecycle controls play/pause and speed without reloading the model.
- SceneKit receives an in-memory GLB drawing copy without unsupported custom muscle semantics; authored attributes, skinning and binary data remain in the asset.
- Native playback clocks stop on pause/dispose. Android form playback bypasses the default idle freeze.
- EventChannel subscriptions are canceled when a texture is disposed.
- No global Flutter package-cache files were edited.

## Body tab material masks (2026-09-14)

The body asset now exports a single continuous mesh with 16 named material primitives. iOS restores material names from GLB metadata because the bundled GLTFSceneKit importer drops them; body material updates tint every matching primitive without replacing exercise entity materials. Android updates matching body material instances in place. Existing entity override behavior remains available for other models. The body model has no animation and retains the current fixed cameras.

Verified on iPhone 17 / iOS 26.5 Simulator with zero, period updates, all three cameras and an annual 600-set fixture. Android Kotlin compilation passed; Android visual verification remains outstanding.
