# Category card refresh - 2026-09-14

Implemented as the user's high-priority category-selection replacement. Six offline transparent renders use the same MPFB base and matte appearance as exercise 3D forms. Chest, shoulders, arms, legs and abs face straight forward; back faces straight backward. Target regions alone are red. Cardio uses a heart-monitor Material icon, not a human.

White cards have 22px corners, consistent minimum heights, aligned labels/counts and chevrons, no persistent red border. Image width adapts to available space. Font scaling can grow the card rather than clip text. The category heading wraps on narrow layouts. Changing category resets the exercise list to its top. Counts and selection continue to use the existing exercise data. Accessible cards expose button labels/actions.

## Final verification

- flutter analyze: No issues found (see analyze.log).
- flutter test: all 73 tests passed (test.log). Added 320x568 card tests at 1x/2x text scale and a full picker test at 2x. Updated an existing test to scroll/pump before selecting the now-larger leg card.
- flutter build ios --simulator --debug: success, 11.8s Xcode build.
- flutter build apk --debug --target-platform android-arm64: success, 9.5s Gradle build.
- iPhone 17 / iOS 26.5 Simulator: final build installed. Top and bottom cards visually inspected; all six anatomical categories and cardio checked. Keyboard traversal revealed lower cards; leg button opened the correct list with squat first, then returned to the category top. Button accessibility roles confirmed.
- Small-screen behavior tested at 320px in Flutter; not claimed as a separate 320px physical-device test.
- Android build verified, Android actual display not tested.
- All six PNGs in the built iOS app match source SHA-256 hashes.

Evidence: categories_top.png, categories_bottom.png. The lower capture includes the temporary keyboard focus highlight on cardio; it is not a permanent card border/background.

Source, license, camera directions and reproduction: art/category_muscles/README.md and tool/render_category_muscles.py. Existing workout records, history and settings were not modified by this feature. No GitHub push, paid materials or new server.
