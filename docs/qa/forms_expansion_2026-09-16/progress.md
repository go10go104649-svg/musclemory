# 3D種目拡張 — 作業記録

- 対象: 既存2種目を保持、新規65種目。
- 基準: `bench_press.glb` / `incline_dumbbell_press.glb`、同じMPFB人体・骨格・UI・スタジオ照明。
- 設計: 共通種目カタログ、制作時の動作ファミリー＋差分パラメータ、同一バイナリ領域の共有パック。描画時は選択種目だけを組み立てる。既存2種目の素材は変更しない。
- 未完了: カタログ・共有パック・追加動作制作・全種目表示検証・データ互換性・Android/iOSビルド。
- 既存保存データは名前を識別子として使用。懸垂は保存上の名前を変えず表示名だけチンニングにする。
- caffeinate PID: `/tmp/musclemory_3d_expansion_caffeinate.pid`。完了・中止時に解除する。

## 品質再確認（ユーザー指摘）
- 新規8種目は制作途中。正式採用・アプリ動作確認済みではない。展開より先に少数種目の品質を修正する。
- ラットプルダウンの塔が人体の背後に配置され、座位の向きが器具と合っていなかった。人体の正面側（制作座標-Y）へ塔・ケーブル経路・ウェイトを修正する。
- ベンチプレスの手の方向を流用したためMAGグリップと不一致。グリップ軸に沿った手の向き・指の接触を実際の表示で再確認する。
- palmAnchorErrorMは設定した手首とオフセットの一致のみ。指と器具の接触品質の証明には使用しない。
- ライナーロウ指定資料: https://www.deltafitness.shop/product/907 （DFシリーズ LINEAR ROW DF001A）。商品画像を確認して機構を特定する。

## 現在の確認結果
- 静的解析: flutter analyze 成功（No issues found）。
- 関連単体/Widgetテスト: 7件成功（既存2GLB、共有バイナリ再構成、旧懸垂データ、バックエクステンション追加重量、再生操作と破棄）。
- Android: API36の専用AVDで既存2種目+修正MAGナローの読み込み/再生/停止/速度/再表示をテスト。画像内の実描画判定も成功。-gpu hostで再確認済み。最初の灰色画像だけで成功・失敗を決めず、その後の実描画を検査した。
- iOS: 専用iOS26.5シミュレーター、同じ3種目のビルドと実画面テスト成功。通常再生専用エントリーポイントでもMAGナローを10秒録画。録画から1秒/3秒の姿勢を確認。
- 画像・動画: android_host/、ios/。通常再生動画 ios/mag_narrow_loop.mp4。これは制作確認用画面で、製品の種目一覧からの導線確認はまだ。
- 新規全65種目の完了・ユーザーの見た目承認を意味しない。MAGナロー以外の7試作は、資料と照合し直すまで未確認。残り57種目は制作未完了。
- 自動承認レビューのモデル混雑で起動操作が一度拒否されたが、確認用コードの非破壊性を確認して再試行し成功。現在この理由によるブロックはない。

## 追加の資料照合と品質修正（継続中）
- MAG3種の修正、標準プルダウンの制作、指定DF001Aライナーロウの制作、インクラインプレス/デクラインフライの作り直しを進めている。新規種目はすべて下書きで、正式有効化していない。
- iOSで後方画角だけ傾いていた。SceneKitのlook(at:)が前のup方向を保持していたため、カスタム画角にはworld up=(0,1,0)を明示。ios_quality_revisionの実画面で傾き解消を確認。
- 硬い色境界を表面に沿った補間へ修正。胸・三角筋前部・上腕三頭筋には既存人体のマスクを再使用。元の2GLBは変更なし。
- ケーブル先端の隙間、レールの接地、バーと腕の干渉を静止画像で発見し修正。フライとプレスは器具の長さが変化しない剛体レバーへ変更。
- 新規カタログとの同名カスタム種目を、保存・復元時に失わないよう修正中。カスタム定義の記録方式を優先する。
- 全テスト初回: 96成功/1失敗。種目増加により作成直後のカスタム種目が画面外へ隠れる問題。修正後、当該テスト単体は成功。全テスト最終再実行は未完了。
- 最新素材は/tmp/musclemory-form-revision内。制作中の変更をすべてアプリへ反映したわけではない。過去のテスト画像を最新素材の確認済み証拠として扱わない。

- 互換性修正後: flutter analyze No issues found、flutter test 全98件成功。3D新作全種目の確認完了を意味しない。

### Reference revision device batch
- Android (`android_reference_revision`) and iOS (`ios_reference_revision`) integration runs both passed: original bench press/incline dumbbell press plus incline press machine, standard lat pulldown, MAG narrow/medium/wide, linear row, decline fly, and MAG reopen.
- Native load, play/pause/speed/dispose/reopen verified; anatomy and machine mechanics remain separate visual checks. New entries remain authored.
- Android images inspected for MAG medium, incline machine, linear row, decline fly; iOS MAG medium confirms upright camera orientation. Additional visual checks remain.
- Decline press now uses the manufacturer front/upper pivot reference, upright seat and downward press arc. Camera/pose review ongoing; not included in this device batch.
- Current catalog: 2 existing verified, 10 new authored drafts, 55 planned. Full requested expansion is unfinished.

### Further manufacturer-based fixes
- Incline/decline press: uprights now meet their own pivot positions rather than crossing the hand path. Decline press uses an upright seat, front upper pivots, a rigid converging/downward arc and a camera that exposes both arms. Android/iOS `*_press_revision` passed for incline, decline and linear row, including decline reopen.
- Assisted chin-up: front-facing tower, access steps, supported knee platform, constant-length parallel linkage, counterweight and continuous cable tied to the same platform travel. Explicit foot orientation and fixed-bar hand targets. Blender endpoint previews reviewed; Android `android_assist_revision` and iOS `ios_chin_revision` passed. This is original simplified machinery informed by demonstration, not a manufacturer CAD replica.
- Unassisted chin-up: same controlled fixed-bar body motion without assistance, front tower placement, bent-leg foot orientation. ACE pronated pull-up instructions reviewed; internal identity retained. iOS passed; Android check in progress at this entry.
- Current generated shared bundle: 11,726,645 bytes across 10 recipes / 1,256 chunks. Raw exports for those 10 revised scenes total 41,528,440 bytes. Existing two legacy GLBs are additional, intentionally unchanged.
- All 10 new scenes remain `authored`; 55 further requested scenes are still `planned`. Production-route QA, remaining appearance review, final all-target verification and release builds remain. This is not completion of the requested 65-exercise expansion.
- Follow-up complete: `android_chin_revision` passed for unassisted chin-up and reopen. Both chin-up variants now have Android/iOS debug integration passes. OS review flags reflect these tests; static/motion/production-route gates remain pending rather than being inferred from a passing test.
- iOS chin-up / assisted chin-up screenshots inspected. Android shows small bright edge artifacts along some red surface boundaries; this is not seen in the same iOS images and remains an appearance issue to investigate before production approval.
- Final static analysis: no issues. Python authoring files compile successfully with a temporary cache directory. Final full Flutter test run pending at this entry.
- Final full Flutter suite completed: 98 tests passed; static analysis no issues. Debug native builds and integration tests passed on both dedicated QA environments. Release APK/IPA and all-exercise production-route review have not been completed.
- Manufacturer-review workflow is documented in `tool/exercise_forms/README.md`. No Git commit/push performed during this revision.

## Continuation: Android surface edge diagnosis
- COLOR_0 values were finite/in-range, so the white edge dots were not authored white colors.
- RGB→RGBA experiment did not remove the dots; recipe restored (not adopted). `android_color_rgba` is the unchanged baseline because the first write was denied before permissions were granted; `android_color_rgba_actual` is the actual RGBA experiment.
- Disabling MSAA alone removed the bright dots (`android_color_no_msaa`). Replacing MSAA with FXAA also removed them while smoothing silhouettes (`android_color_fxaa`). Same model/color/lighting; actual dedicated API36 OpenGL emulator images inspected.
- Adopt FXAA only for new custom-camera form scenes. Restore the legacy 4x MSAA/no-FXAA settings for legacy forms, preserving the original two. This diagnosis is verified on the available emulator; no physical Android GPU claim.

### Low-row / DY continuation
- Low row authored with manufacturer-reviewed chest pad and upper rigid levers. Measured sole minZ 0.000579m; no floor-height scale workaround. Android and iOS native debug builds/playback/reopen passed. Android baseline bench/incline regression and MAG also passed; inspected visible stage3 captures (early stage0 captures were blank during warmup).
- Fixed QA capture sequencing to wait for actual visible native geometry before taking the four motion frames. Android low-row/MAG rerun passed with all four low-row images visibly populated.
- DY row uses the same lever family with underhand orientation, different pivot/path, lower elbow pole and rear oblique camera. First unreachable wrist rejected; arm lengths preserved. Latest native Android run passed, iOS pending at this entry.
- 12 new draft recipes share 1470 chunks, 13,210,362 bytes versus raw source49,780,580 bytes. DY incremental packed cost113,557 bytes. All new forms remain authored pending full review and production route checks; not released or user-approved.
- Latest flutter analyze: no issues. Full flutter test:98 passed. No release build/push performed.

### Three lever rows connected to normal detail UI
Low row, DY row and high row passed native playback/reopen on Android API36 and iOS26.5, plus actual category picker → 3D detail → return route tests. They are now technically `verified` and enabled in the normal catalog; this is not user appearance approval. Initial route-test failure was an assertion before route transition completed; the test now waits for that transition and passed. Temporary QA catalog generation is restored by EXIT trap; checked normal generated output afterwards. Native source/asset appearance remains platform-dependent, with iOS darker metal and Android flatter lighting visible in evidence.

## User-requested checkpoint (2026-09-16)
- Stop new authoring at this checkpoint to conserve usage. `next_session.md` records the remaining 10 authored drafts and 51 planned scenes.
- Back extension: Android/iOS playback, pause, half-speed, reopen and normal category → detail → return all passed. Fixed detail muscle chips to consume verified form catalog targets: erector spinae primary, gluteus/hamstrings secondary. Repeated both native route tests after this correction and inspected iOS result. It is now technically verified, not user appearance-approved.
- Added a production catalog test rejecting temporary QA output and any exposed scene without all review gates. Existing data compatibility/GLB reconstruction tests retained.
- Current normal availability: 2 preserved legacy scenes + 4 new verified scenes (low_row, dy_row, high_row, back_extension). Remaining 10 authored scenes are not enabled in normal form UI. Full 65-scene expansion is not complete.
- Shared draft/verified bundle: 14 recipes, 1704 chunks, 16,514,751 bytes. Raw exports total 57,953,020 bytes. The bundle still contains draft assets for continued review; no claim of final optimized distribution.
- Final release/analysis/test results are recorded below when completed. No GitHub push in this checkpoint.

### Final checkpoint results
- flutter analyze: No issues found. Full flutter test: 99 passed.
- Android release APK build: successful, 102.3MB reported, versionName1.0.0/versionCode5, apksigner verification successful. Saved to `/Users/macintosh/Documents/Codex/2026-09-11/r/beta/1.0.0-5/MUSCLEMORY-beta5-1.0.0-5.apk` with SHA256.txt.
- Installed release APK and inspected normal home on dedicated Android API36 emulator. The earlier uninstall returned DELETE_FAILED_INTERNAL_ERROR because no package path remained after integration cleanup; install succeeded. User physical device untouched.
- iOS debug simulator build: successful. Installed/launched normal Runner.app on dedicated iOS26.5 simulator and inspected home. No signed iPhone IPA/TestFlight distribution produced.
- All four new enabled forms have normal-route + playback checks on both QA environments. Actual physical-device performance and user appearance approval remain unverified.
- Build logs retain dependency-update notices; no new analyzer warnings remain. No dependency upgrades performed.
- No Git commit or push. User requested stopping at this checkpoint; remaining work is deferred to the next session.
