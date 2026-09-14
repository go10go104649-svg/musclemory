# Incline dumbbell press expansion - 2026-09-14

The user approved the bench-press mannequin and asked to proceed. Added one independently authored exercise: incline dumbbell press. Reused the approved human, target masks and native playback; added a 45-degree backrest/seat, two independent dumbbells and a dedicated 4-second bone animation. The existing bench-press GLB was not modified.

Shared Flutter view selects only explicitly registered assets and uses each exercise name in the header. Unsupported exercises retain their existing display. Record types, saved history, timer settings and data storage were not changed in this update.

## Verification

- flutter analyze: No issues found (3.4s).
- flutter test: All 65 tests passed. Both assets checked for skins, nonempty muscle masks, synchronized 4-second clips, closed joint endpoints and moving expected equipment. Both dumbbells must move for the incline test to pass.
- flutter build ios --simulator --debug: successful (Xcode 17.0s).
- flutter build apk --debug --target-platform android-arm64: successful (Gradle 11.2s).
- iPhone 17 / iOS 26.5 Simulator: inclined body/bench, hands and dumbbells, loop, pause, 1.5 speed selection, resume, close/reopen and transition back to bench press verified.
- Actual 6-second app recording: incline_loop.mp4. Recording frames phase_0.5.png / phase_2.5.png inspected for distinct top/bottom motion, attached hands, surface colors and fixed framing. Static diagnostic renders were inspected before app integration.
- Android actual display and physical-device performance remain unverified. No measured FPS or memory claim.

Added app asset: 4,736,576 bytes (4.52 MiB). Editable source: art/bench_press/incline_dumbbell_press.blend; source/license and NASM form reference are recorded in art/bench_press/README.md. No paid assets, servers or GitHub push.

The bench appearance is user-approved. The new incline implementation is runtime-verified but has not separately received visual feedback. Additional exercise motions remain future work; they are not represented as implemented.
