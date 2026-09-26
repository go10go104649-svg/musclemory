# MUSCLEMORY 17種目量産 — 最終記録（2026-09-22）

> 本書は第1バッチの生成・一時試用状態を記録した履歴です。17種を一時的に通常画面から選択可能にした状態は現行の正式公開数ではありません。最新の公開数・保留数・両OS確認数は [現行確定仕様](../current_spec.md) を優先します。

## 結果と公開状態

**対象17/17にアセット・カタログ定義・開始/中間/終了previewが揃った。**
不足していた6種目を新規生成し、既存11種目は再利用した。
最終共有データからGLBを復元してBlenderへ再importし、全17種目の画像を確認。
17×97 = 1,649フレームの床位置・画面内収まり・ループ接続チェックも全件成功。

**追記：ユーザーの「一旦反映させてみよう」により、17/17を通常画面から一時的に選択可能にした。これは当時の試用状態であり、正式公開数には算入しない。**
既存verified 3種目は保持。authored 14種目に明示的な `previewEnabled` を設定し、
フォーム見出しに「試用」（英語localeではPreview）を表示する。
未実施のレビュー項目・statusは変更せず、他のauthored種目は引き続き非表示。
アプリ起動・実機確認は未実施であり、反映は次回ビルドから。

| 種目 | アセット | 3姿勢・復元QA | 通常画面 |
| --- | --- | --- | --- |
| インクラインベンチプレスマシン | 既存を保持 | 確認済み | 試用（authored） |
| デクラインペックフライマシン | 既存を保持 | 確認済み | 試用（authored） |
| デクラインベンチプレスマシン | 既存を保持 | 確認済み | 試用（authored） |
| MAG ナロー | 既存を保持 | 確認済み | 試用（authored） |
| MAG ミディアム | 既存を保持 | 確認済み | 試用（authored） |
| MAG ワイド | 既存を保持 | 確認済み | 試用（authored） |
| DYロー | 既存を保持 | 確認済み | 既存verified |
| ローロー | 既存を保持 | 確認済み | 既存verified |
| ライナーロウ | 既存を保持 | 確認済み | 試用（authored） |
| ハイロー | 既存を保持 | 確認済み | 既存verified |
| ケーブルロー | 新規生成 | 確認済み | 試用（authored） |
| アシストチンニング | 既存を保持 | 確認済み | 試用（authored） |
| バックエクステンション（荷重） | 新規生成 | 確認済み | 試用（authored） |
| リアデルト | 新規生成 | 確認済み | 試用（authored） |
| ミリタリープレス | 新規生成 | 確認済み | 試用（authored） |
| アブローラー | 新規生成 | 確認済み | 試用（authored） |
| インクラインフライマシン | 新規生成 | 確認済み | 試用（authored） |

## 許可範囲と環境

開始/再開時のブランチはmain。元の `lib/main.dart` と
`test/home_rest_cloud_revision_test.dart` は内容ハッシュを保持。
途中の変更はこのタスクの既知の差分として継続。

当初BlenderはPATH上になかったが、ユーザーがインストール済みBlenderの利用を許可。
`/Applications/Blender.app/Contents/MacOS/Blender`（4.5.3 LTS）を使用した。
workspace外の利用はこの既存Blenderとそのruntimeに限定。
`TMPDIR`、`BLENDER_USER_CONFIG`、`BLENDER_USER_EXTENSIONS` をworkspace内へ指定。
ネットワーク、追加インストール、ブラウザ、実機、シミュレータ、commit、pushは不使用。
承認待ち・承認要求・自動承認拒否はなし。

## 共通化と修正

再利用した7系統:
`hinged_press`、既存の固定軸フライ、`pulldown`、`lever_row`、
`linear_rail_row`、`chin_up`、`back_extension`。
新規4系統: cable row、standing vertical press、reverse fly、kneeling rollout。

MPFB人体、リグ、指/手/2ボーンIK、材質、カメラ、ライト、97フレームの共通ループを再利用。
シート/ベンチ/パッド、box/cylinder/rod、ケーブル塔、スタック、バーベル/プレートも再利用。
新しい器具構成は既存プリミティブで作った下側プーリー/ハンドル、リアデルトレバー、
アブホイール/膝マット。外部画像・購入物・CADは使っていない。

インクラインフライは固定軸フライの `arcDeclination=-15` 差分。
荷重バックエクステンションは既存 `additionalWeight` 機構を使用し、
無荷重アセットと記録IDを保持するため `weighted_back_extension` を追加。
表示用10 kgはトレーニング負荷の推奨ではない。

修正した問題:

- ケーブルローの開始位置が腕長を超えていたため `gripStart.y=-0.78` に修正。
- アブローラーの開始姿勢を修正してローラーへの到達性を確保。
- 足先が床下へ入るアブローラーの足首角を `footPitch=150` に修正。
- ミリタリープレスの上端で手首→握り位置offsetを考慮し、伸展量を修正。
- 実画像で上がりすぎていたミリタリープレスの開始肘方向を下向きへ修正。
- リアデルトの曲がりすぎていた腕を、共通レバー半径0.48 mで修正。

5種目（ケーブルロー、リアデルト、ミリタリープレス、アブローラー、
インクラインフライ）の寸法は作者選定の簡略機構。メーカー寸法/実演確認済みとはしない。
`--unreviewed-draft` は明示指定時のみ器具資料未確認の下書きを生成できる。
通常の資料ゲートと公開ゲートは保持し、equipmentReferenceはfalseのまま。
荷重バックエクステンションは既存ローカル参照記録の胸前プレート機構を再利用。

## 実行したQA・テスト

- Python既存/追加テスト: **49件成功**。実行コマンド:
  `TMPDIR="$PWD/build/exercise_forms/tmp" PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tool/exercise_forms/tests -p 'test_*.py'`
- Blender authorer: 全17種目について97フレームを評価してpreview生成。
  新規6種目も実Blenderで手先アンカーの許容差チェックを通過。
  最大誤差は約0.00051 mm。これは手の表面と器具の衝突証明ではない。
- source preview: 全17種目、開始1/中間24/終了47の51画像を確認。
- 新規6種目: 修正後のGLB/.blendを書き出し、各97フレームを評価。
  ループ内13時点の画像を確認。荷重バックエクステンションとアブローラーは
  反対側からの3姿勢も追加確認。
- 最終packagedアセット: 全17種目の`.form.json`+共有chunkからGLBを復元し、
  Blenderへ再import。再度51画像を確認し、1,649フレームを評価。
  人体最下点は全件0 m以上（全体最小0.000569 m）、画面半幅/半高に対する
  最大extentは0.893678、ループ接続誤差は最大0.000007502 m。
  Blender importerが作る非表示の骨表示用Icosphereは画面内判定から除外。
  初期の見かけ上のcamera判定失敗は、この補助オブジェクトを誤って数えたためで、
  アセットやカメラを変更せず検査対象を修正した。
- 20レシピ/2,343共有chunk: SHA-256、長さ、accessor範囲、mesh/skin/animationを検査。
- カタログ195定義を生成元から再生成。pubspecの既存forms/chunksディレクトリ宣言で追加アセットを包含。
- 既存モデル全ファイル、元の作業中2ファイル、既存verified定義は内容不変。
- `git diff --check`: 成功、出力なし。

大きな破綻・画面外・手の大幅なずれは確認した画像では認められなかった。
メッシュ全体の連続衝突証明や、連続動画の実機再生合格までは主張しない。
`staticPose` は実画像を確認した17件でtrue。未完の `motion` / native / route は保持。

## 生成・梱包コマンド

Blender呼び出し時は上記workspace内runtime用環境変数を指定。

```sh
python3 -B tool/exercise_forms/batch_forms.py --mode preview --blender /Applications/Blender.app/Contents/MacOS/Blender
python3 -B tool/exercise_forms/batch_forms.py --mode preview --unreviewed-draft --ids cable_row,military_press,rear_delt,ab_wheel,incline_fly_machine --blender /Applications/Blender.app/Contents/MacOS/Blender
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 --python tool/exercise_forms/author_forms.py -- --ids cable_row,military_press,rear_delt,ab_wheel,incline_fly_machine,weighted_back_extension --output build/exercise_forms/production-ur7t69x3 --preview --unreviewed-draft --continue-on-error
python3 -B tool/exercise_forms/pack_assets.py build/exercise_forms/production-ur7t69x3 --ids cable_row,military_press,rear_delt,ab_wheel,incline_fly_machine,weighted_back_extension
python3 -B tool/exercise_forms/generate_catalog.py
```

最初のpreviewバッチは資料未確認5件を正しくスキップして終了1。
その5件は明示的なoffline draftモードで続行、全件生成成功。
修正後のmilitary_press/rear_deltは対象を絞ってpreviewを再生成した。

## 未完了とスキップ

承認が必要でスキップした処理はなし。以下は残る明示的禁止条件による未実行。

- `flutter analyze --no-pub`
- `flutter test --no-pub test/exercise_form_catalog_test.dart test/form_qa_plan_test.dart`
  — Flutter SDK/依存はworkspace外。今回の外部runtime許可はBlenderに限定。
- `./tool/verify_workout_lifecycle.sh ios <QA_DEVICE_ID>`
- `./tool/verify_workout_lifecycle.sh android <QA_DEVICE_ID>`
  — 実機/シミュレータ禁止。新規6種目のnative確認と、authored14種目の製品導線確認は未実施。
- 上記5種目のメーカー/実演参照確認 — ネットワーク/ブラウザ禁止。

verifiedへの昇格は行っていない。今回の14種目だけ、ユーザー指定に基づく試用枠で利用可能にした。

## 変更ファイル・容量

変更: `tool/exercise_forms/author_forms.py`、`author_options.py`、`catalog.json`、
`README.md`、生成元から再生成した `lib/exercise_form_catalog.g.dart`。
新規: `batch_forms.py`、`batch_support.py`、`tests/test_batch_forms.py`、本記録。
新規アセット: `assets/models/forms/` 内の対象6レシピと、
`assets/models/form_chunks/` の639個のハッシュ名chunk。

- 既存共有bundle: 16,514,751 bytes。
- 最終共有bundle: **22,144,882 bytes**。
- 実増分: **5,630,131 bytes（約5.63 MB）**。
- 新規6種目の元GLB合計: 24,392,624 bytes。
- 重複GLB・blend・画像・補助スクリプト・ログ・JSON結果は全てignored build内。
- raw `git status --short` と `git diff --stat` は作業用 `build/exercise_forms/` に保存。
- Git stage/commit/pushは実行していない。

## 試用反映の追加変更

- `lib/exercise_form_catalog.dart`: 明示的な試用指定・姿勢確認・アセットを満たすauthoredを利用可能にする。
- `lib/bench_press_form.dart`: 試用の見出し表示。
- `tool/exercise_forms/generate_catalog.py`: 試用指定の型・status・ファイル・姿勢QAを検証。
- 再生成時には試用指定を解除し、未確認の差し替えを自動公開しない。
- `test/exercise_form_catalog_test.dart`: verifiedの全レビュー要件と試用の条件・対象外の非表示を確認する回帰テストを追加（Flutter実行は上記制約で未実施）。
- Pythonテスト50件成功。共有bundleの整合性確認成功。`git diff --check`成功。
