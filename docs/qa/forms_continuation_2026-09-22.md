# 第1バッチ後の継続制作 — 2026-09-22

> 本書は第1バッチ後の制作途中を記録した履歴です。17種の試用状態、追加11種の非公開、当時のカタログ件数は現行集計ではありません。最新の確定進捗は [現行確定仕様](../current_spec.md) を優先します。

## 開始地点と状態

main上の第1バッチ未コミット差分を保持して継続した。第1バッチの17種目は
既存verified 3 + 試用authored 14。全17の正式公開QAが完了したという意味ではない。
本継続分は11種目を新しくパッケージ化。いずれもauthored、previewEnabledなし、
review承認なし。公開追加数は0。既存verifiedのアセットは再生成していない。

| 系統 | 新規パッケージ化したexerciseId |
| --- | --- |
| press_fly（再利用） | incline_barbell_press, flat_dumbbell_press, decline_barbell_press, decline_dumbbell_press, dumbbell_fly, incline_dumbbell_fly |
| vertical_press（再利用・着座分岐追加） | dumbbell_shoulder_press |
| curl（新規共通系統） | barbell_curl, dumbbell_curl, hammer_curl, reverse_curl |

第2バッチはプレス/フライ/頭上プレス7種。第3バッチはカール5種を試行し、
4種を生成、incline_dumbbell_curlはpreviewのみで保留した。失敗種目を件数合わせで
authoredやavailableにしない。人体、リグ、指、二関節IK、材質、照明、ベンチ、
ダンベル/バーベル部品、共有チャンクを再利用。

## 修正と保留

- ダンベルショルダープレスは従来の水平プレス系からvertical_pressへ変更。
  standing military_pressの既存レシピ/アセットは維持。
- 新しい2フライだけconstantElbowFlyを有効化。手首半径一定の軌道とニュートラル
  グリップに変更し、曲げ伸ばし主体のプレスのように見える問題を修正。
- カールは上腕を固定し、肘を中心とする前腕回転。逆手/ニュートラル/順手を分離。
- incline_dumbbell_curlはベンチ60度。途中でプレートが太ももに干渉。
  upperArmOutward=.4、.6の2回修正後にも干渉が残り、追加exportせずplannedを維持。
  最終失敗preview: build/exercise_forms/batch-v9dnwktl/curl/preview-0us1ayvc。
- chest_press / pec_fly / shoulder_pressは初回previewのIKで到達可能距離を超過。
  汎用マシン機構を安易に公開せずplannedのまま。
- decline_barbell_press / decline_dumbbell_pressはアセット生成済みだが、
  デクライン用の足/足首支持の表現を別途確認・改善するまでstaticPose未承認。
- ゾットマンカールは動作資料を調べたが、前腕回旋を現行カールへ単純適用せず未着手。

## 参照資料と限界

寸法は作者選定でありメーカー寸法の検証ではない。以下の資料を動作の照合に使用。
全種目の実演/接触検証を完了したとはしない。equipmentReferenceはfalseを維持。

- [ACE ダンベルチェストプレス](https://www.acefitness.org/resources/everyone/exercise-library/19/chest-press/)
- [ACE 着座ダンベル頭上プレス](https://www.acefitness.org/resources/everyone/exercise-library/45/seated-overhead-press/)
- [Mayo Clinic ダンベルカール](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/biceps-curl/vid-20084675)
- [Muscle & Strength ゾットマンカール](https://www.muscleandstrength.com/exercises/zottman-curl.html)

ACEのmachine seated shoulder pressページはダンベル種目の直接の器具資料ではないため、
カタログ参照を上記のダンベル用ページへ訂正した。
外部モデル/画像は取り込んでいない。既存MPFB Athleteのライセンス記録は
art/bench_press/README.mdを継承。

## 検証

- 全11パッケージの共有チャンクからGLBを再構築してBlenderへ再import。
- 全11×97フレームの床位置、カメラ内収まり、動きの存在、フレーム間変位、
  ループ終端一致の数値チェック成功。
- 最大フレーム変位0.048 m未満、ループ接続差0.000009 m未満。
- 修正後のフライも最終パッケージから再評価済み。
- 開始/中間/終了画像を作成し、フライ、頭上プレス、カールなどの代表姿勢を目視。
  全11の全フレーム接触、解剖学的正確さ、全ループの視覚的品質を承認したものではない。
- 最終復元結果: build/exercise_forms/continuation-roundtrip/report.json
- 生成ログ: build/exercise_forms/continuation-*.log
- Python unittest: 53件成功。
- Flutter catalog/QA planテストとanalyzeの最終結果は下記追記。
- 実機/Simulator/AVDは起動していない。両OS、通常画面の公開経路QAは未実施。

## 容量と次の対象

継続開始時: forms + form_chunks = 22,144,882 bytes（20 recipes）。
継続後: 28,721,034 bytes（31 recipes）、増加6,576,152 bytes（約6.58 MB）。
現行recipe参照分のみでは28,691,642 bytes / 3,317 unique chunks。
再生成で未参照になった小さな旧チャンクは大量削除せず保持した。

カタログ195種: verified 6 / authored 27 / planned 162。
試用14は第1バッチの既存設定のみ。追加11種目は非公開。
次に優先するのは公開QA、保留4種の到達性/接触、デクライン支持の修正。
続く未対応基本種目はスクワット、ヒンジ/デッドリフト、レイズ、トライセプス、
カールのケーブル系。必要な新機構は個別の資料・preview検証を経て追加する。
公開ゲート未通過のまま量産完了や正式公開とは扱わない。

最終検証: `flutter test --no-pub test/exercise_form_catalog_test.dart test/form_qa_plan_test.dart`
は16件成功。`flutter analyze --no-pub` は指摘なし。`git diff --check` 成功。
commit/pushなし。公開QAの許可範囲について確認待ちのため、新規公開は行わない。
