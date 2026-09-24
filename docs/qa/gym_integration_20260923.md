# 全国ジム店舗・設備連携（2026-09-23）

## 取り込み

指定された `FIT PLACE24 全国店舗設備マスター.xlsx` を読み取り専用で使用。
244店舗、219設備、1,582店舗設備関連をリンク先Supabaseへ投入し、同じ入力で再投入後も同数を確認。
60設備・106件の設備→種目対応、未マッピング159設備。店舗ID・設備ID・関連に重複なし。
原本SHA-256: `096e338f7f29a129d152ddaa21d0aeec4ed3564dd74dd2b861f1507b3965492a`。
原本は変更していない。

設備情報があるのは35店舗。原本上、206店舗は未取得、3店舗は非公開。
店舗名・都道府県・市区町村・住所は全件あり。駅名は全244店舗で欠損、
メーカー・型番は全219設備で欠損。台数は368関連のみ明記され、残り1,214はNULLを保持。
原本の設備カテゴリを維持し、不明な部位や器具を推測して分類しない。

## 実装

共通テーブル7件、検索RPC、索引、RLS、報告の連続送信制限を追加。
マイページ「利用ジム」から複数登録・解除・設備確認。
トレーニング場所から店舗検索→設備→対応種目→追加。
通常の種目追加を維持し、「全種目／この店舗でできる」を切替可能。
店舗IDは名称と別に記録・ドラフトへ保存し、旧データの店舗名はそのまま読む。
登録店舗と報告は本人限定。未ログインの登録店舗は端末内のみ。
報告はログイン必須、5分類と任意コメント、新規設備名に対応。
送信はpending保存のみでマスターを変更せず、ユーザー自身では承認できない。

## 検証

- Python importer: 5テスト（Excel読込・不変性、重複、不正値、NULL、正規化、ID保持、マッピング検証）。
- DB: `supabase/tests/gym_equipment.sql` の検索・RLS・報告・権限制約・連続送信のアサーション。
  QA用ユーザー・店舗はトランザクションをROLLBACKし残していない。
- Flutter: `gym_integration_test.dart`, `fitplace_catalog_test.dart`, `workout_gym_test.dart`,
  `workout_completion_test.dart`, `workout_draft_store_test.dart`,
  `home_rest_cloud_revision_test.dart`, `widget_test.dart`。
- 既存の有酸素期待値を現行カタログへ、画面外候補への操作をスクロール後の描画待ちへ最小更新。
- Android Emulator / iOS Simulator: `integration_test/gym_store_flow_test.dart`。
  実Supabaseの「札幌北32条」を検索→設備選択→対応種目追加→店舗ID付きドラフト保存が成功。
  スクリーンショットは `build/qa/gym_android/` と `build/qa/gym_ios/`（Git対象外）。
- 小画面320×568、長い店舗名、設備報告、通信失敗と再試行をWidget Testで確認。
- `flutter analyze --no-pub`、`git diff --check`。

物理端末での確認と、ユーザーの端末へのインストールは行っていない。
実ユーザーでの登録・報告送信は行わず、UI fakeとDB内の一時ユーザーで検証。
未取得設備・未マッピングの補完は今後のデータ整備。駅名検索の仕組みは実装・テスト済みだが、
今回の原本には駅名がないため、実店舗の駅名検索結果にはデータ追加が必要。
既存Premiumクラウド同期は従来のロック状態を維持し、今回の店舗機能とは独立。

## 変更ファイル

- lib/main.dart
- lib/gym/gym_repository.dart
- lib/gym/gym_pages.dart
- supabase/migrations/202609230001_gym_equipment.sql
- supabase/tests/gym_equipment.sql
- tool/gym_import/import_master.py
- tool/gym_import/fitplace_mappings.json
- tool/gym_import/test_import_master.py
- tool/gym_import/README.md
- tool/gym_import/.gitignore
- test/gym_integration_test.dart
- test/workout_gym_test.dart
- test/widget_test.dart
- integration_test/gym_store_flow_test.dart
- docs/qa/gym_integration_20260923.md


## 2026-09-24 追補

- FIT PLACE24設備→種目の直接対応を193設備・335件まで拡張。
- ラック＋ベンチ、ダンベル＋角度別ベンチ等を扱う複数設備ルールを追加（163ルール・326項目）。
- `gym_store_exercise_ids` RPCで、直接対応と成立した複数設備ルールを統合して「この店舗でできる」を判定。
- 店舗フィルター選択時の部位別種目数も、実際の店舗対応種目数で表示するよう更新。
- 汎用ベンチは単体でベンチプレス可能と判定せず、必要設備が揃った場合のみ対応扱い。
- スパインベンチはメーカー製品情報でラック一体型ベンチプレス設備と確認できたため直接対応へ追加。
- 曖昧な設備、`needs_review` 設備、既存種目IDでは器具差を正しく表せない設備は推測で紐付けない。


### 曖昧設備の再調査（2026-09-24）

- 直接対応を205設備・349件まで拡張。
- バックエクステンションベンチは `back_extension` / `weighted_back_extension`、バックエクステンションマシンは `back_extension_machine` に対応。
- ISOライナー/リニアローは設備IDを統合せず、動作のみ `linear_row` に対応。
- ハイロー（プレートロード）、バイセプスカール、ヒップスラスト、フィクスドプルダウン、ペックフライ/リアデルト、ラットプルダウンを個別レビュー後に対応。
- 汎用レッグカールは、公式一覧でライイング/プローン系と別に掲載される構成を確認し `seated_leg_curl` に対応。
- 元データの `needs_review` は監査用に保持し、手動レビュー済みの対応だけ `reviewed_source_override: true` で明示的に許可する。
- 残る14設備は、複数設備ルール側で扱う汎用ベンチ/カールラック、専用種目不足のフルボディトレーナー、仕様特定待ちのデルツ/マルチステーション。
