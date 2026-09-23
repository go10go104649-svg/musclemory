# 種目マスター整理（2026-09-23）

## 互換性方針

- 全195 IDを保持。新規選択は191件。旧重複2件・汎用2件は選択候補だけ非表示。
- `canonicalExerciseId` は確定した2組だけ。履歴・PRは正規identityで集計し、セットは削除しない。
- 記録修正・draft復元では元のIDごとに入力カードを復元。保存名・記録値・日時の一括移行なし。
- 表示名は既知IDから解決。IDなし・未知ID・カスタムIDは保存名を保持。検索aliasを旧記録へのID割当には使わない。
- `resolve` / `byId` は元IDの3D参照を維持。公開状態と選択候補の可否は独立。

## 名称変更

| ID | 旧名 | 正式名 |
|---|---|---|
| chest_press | チェストプレス | チェストプレスマシン |
| pec_fly | ペックフライ | ペックフライマシン |
| lat_pulldown | ラットプルダウン | ケーブルラットプルダウン |
| seated_row | シーテッドロー | シーテッドローマシン |
| cable_row | ケーブルロー | シーテッドケーブルロー |
| shoulder_press | ショルダープレス | ショルダープレスマシン |
| lateral_raise | サイドレイズ | ダンベルサイドレイズ |
| front_raise | フロントレイズ | ダンベルフロントレイズ |
| rear_raise | リアレイズ | ダンベルリアレイズ |
| rear_delt | リアデルト | リアデルトマシン |
| hammer_curl | ハンマーカール | ダンベルハンマーカール |
| preacher_curl | プリーチャーカール | プリーチャーカール（フリーウェイト） |
| french_press | フレンチプレス | ダンベルフレンチプレス |
| overhead_triceps_extension | オーバーヘッドトライセプスエクステンション | ケーブルオーバーヘッドトライセプスエクステンション |
| hip_thrust | ヒップスラスト | バーベルヒップスラスト |
| abdominal_crunch | アブドミナルクランチ | アブドミナルクランチマシン |
| plate_loaded_chest_press | チェストプレス | プレートロードチェストプレス |
| selectorized_incline_chest_press | インクラインチェストプレス | インクラインチェストプレスマシン |
| plate_loaded_incline_chest_press | インクラインチェストプレス | プレートロードインクラインチェストプレス |
| plate_loaded_lat_pulldown | ラットプルダウン | プレートロードラットプルダウン |
| plate_loaded_seated_row | シーテッドロー | プレートロードシーテッドロー |
| plate_loaded_shoulder_press | ショルダープレス | プレートロードショルダープレス |
| machine_preacher_curl | プリーチャーカール | プリーチャーカールマシン |
| machine_hip_thrust | ヒップスラスト | ヒップスラストマシン |
| glute_kickback_machine | グルートキックバック | グルートキックバックマシン |

英語名も器具区分に対応。旧和名・英語名は検索aliasに保持。

## 器具表示区分の根拠

| 対象 | 表示 | 既存定義内の根拠 |
|---|---|---|
| lat_pulldown | ケーブル | 既存formのPulldown cable / Overhead cable / Stack plate構成 |
| dy_row / low_row / high_row | プレートロード | catalog内のHammer Strength plate-loaded参照、lever / loading設定 |
| linear_row | プレートロード | 既存formのRow weight horn / Row plate構成 |
| incline_press_machine / decline_press_machine | プレートロード | catalog内のHammer Strength plate-loaded参照、lever設定 |
| decline_fly_machine | プレートロード | 既存Panatta Free Weight参照、formのFly weight horn / Fly loading plate構成 |

equipmentId・parameters・assetPath・status・review・previewEnabledは変更していない。外部Web再調査や3D品質QAは今回行っていない。

## 統合

- cable_pullover → straight_arm_pulldown：指定方針に従う。旧和英名を正規候補aliasへ追加。
- triceps_pushdown → rope_pushdown：双方pressdown、neutral、attachment=rope、singleArm=false、weightReps、externalで一致。
- leg_curl / calf_raise：非表示のみ。旧IDは正規化せず、具体種目の履歴・PRに混ぜない。

## 現状維持・要確認

全195件の名称・器具・記録方式を一覧照合。以下は名称・対象筋の類似だけでは統合を確定できない。

- incline_press_machine と plate_loaded_incline_chest_press：前者は参照・具体動作あり、後者はplanned・parameters空。後者の具体器具/軌道を特定できないため別IDを保持。selectorized版は負荷方式が別。
- incline_fly_machine：参照が空。プレートロード／ウェイトスタックは特定せず「マシン」を維持。
- cable_lateral_raise と single_arm_cable_lateral_raise：通常版の片手/両手を確認できず維持。
- machine_arm_curl と machine_preacher_curl：通常版の支持台・軌道が未特定のため維持。
- rowing_machine と hyrox_rowing：カテゴリと距離単位が異なるため維持。
- preacher_curl：preacher_bench とフリーウェイトまでは確認できるがEZバー／ダンベルは特定しない。
- 他の「マシン」表記：具体負荷方式の根拠がないものを一括でウェイトスタックやプレートロードへ変更しない。

## 検証

- 正規generator実行後、生成Dartをformatterで整形。sourceとgenerated dataの一致テスト成功。
- Python差分検証：全195 ID・順序を保持。変更許可フィールド（和英名・alias・表示器具・互換ID・選択可否）以外は全件一致。全assetPathの実ファイル存在確認。
- `flutter test --no-pub --concurrency=1 test/exercise_catalog_cleanup_test.dart test/widget_test.dart`：93件成功（新規8件、既存85件）。
- `test/exercise_identity_test.dart` / `test/exercise_identity_flow_test.dart` / `test/bulk_exercise_test.dart` / `test/workout_detail_ui_test.dart`：全成功。最初の旧名称期待値不一致はテストを正式名称/ID指定に変更して解消。
- `flutter test --no-pub --concurrency=1 test/exercise_form_catalog_test.dart --name 'catalog|trial|back extension|built-ins'`：5件成功。大量3D asset QAは対象外のため未実行。
- `flutter analyze`：No issues found。
- `integration_test/exercise_identity_test.dart`：Android Emulator → iOS Simulatorの順にbuild/drive成功。器具違い同時選択、draft保存/再構築、完了・履歴・記録編集、既存HYROX入力を確認。
- 両OSのpicker/editスクリーンショットを目視確認。保存先は `build/qa/catalog_cleanup/android/` と `build/qa/catalog_cleanup/ios/`。
- 狭幅320px、長名の履歴・共有・修正画面はWidget testで例外なし。両OSの実機/ユーザー端末へのインストールは未実施。
- `git diff --check`：成功。commit/pushなし。

## 変更ファイル

- `tool/exercise_forms/catalog.json`
- `tool/exercise_forms/generate_catalog.py`
- `lib/exercise_form_catalog.dart`
- `lib/exercise_form_catalog.g.dart`（正規生成）
- `lib/main.dart`
- `test/exercise_catalog_cleanup_test.dart`（追加）
- `test/exercise_form_catalog_test.dart`
- `test/exercise_identity_test.dart`
- `test/support/bulk_exercise_flow.dart`
- `test/widget_test.dart`
- 本記録

