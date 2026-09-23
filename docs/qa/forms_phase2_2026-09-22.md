# 3Dフォーム公開QA・第2フェーズ 作業結果 — 2026-09-22

main上で既存の3D差分を保持して作業。commit / pushは実施していない。
「公開」はワークスペースの通常カタログでavailableになることを指し、ストア配信ではない。
既存カタログ195件は維持。開始時の実データはverified 6 / authored 27 / planned 162であり、依頼文の既存公開3件とは差があった。既存verified 6件の定義は変更していない。

## 結果

- 新規3Dアセット11種目（脚3・腕6・肩2）。既存アセットの再生成はこの11件に数えない。
- 今回通常公開12種目：既存審査25件から6件、新規アセットから6件。
- 最終状態：verified 18 / authored 26 / planned 151。
- authoredの試用公開は解除。審査未完了のモデルは通常一覧へ公開しない。
- 数値チェック合格と解剖学的な正しさは別。全97フレームを数値検査し、13フレームの時系列画像による一周の見た目確認を行った。全97枚を目視したという意味ではない。
- 全未対応種目の量産完了ではない。今回処理したバッチまでを保存し、未対応・保留を以下に明示する。

## 第1バッチ14種：個別判定

| 種目 / ID | 最終判定 |
|---|---|
| インクラインベンチプレスマシン / `incline_press_machine` | authored — Hold: reconcile converging trajectory, handle and support with reference. |
| デクラインペックフライマシン / `decline_fly_machine` | authored — Hold: reconcile pivot, chest/seat support and ROM with reference. |
| デクラインベンチプレスマシン / `decline_press_machine` | authored — Hold: front-biased camera obscures forward/downward travel; side review needed. |
| ラットプルダウン MAGグリップ ナロー / `mag_narrow` | authored — Hold: inspect grip and thigh-pad contact in detail; rear overview alone is insufficient. |
| ラットプルダウン MAGグリップ ミディアム / `mag_medium` | authored — Hold: inspect grip and thigh-pad contact in detail; rear overview alone is insufficient. |
| ラットプルダウン MAGグリップ ワイド / `mag_wide` | authored — Hold: inspect grip and thigh-pad contact in detail; rear overview alone is insufficient. |
| アシストチンニング / `assisted_chin_up` | authored — Linked assistance pad/stack exists; front elbow symmetry and knee-support review pending. |
| ライナーロウ / `linear_row` | authored — Hold: rear view obscures chest-pad and wrist contact; reconcile actual machine. |
| ケーブルロー / `cable_row` | authored — Hold: elbows already bent at extension, insufficient apparent rowing ROM; improve foot support. |
| バックエクステンション（荷重） / `weighted_back_extension` | authored — Hip hinge and foot supports present; chest-side plate grip review needed. |
| ミリタリープレス / `military_press` | authored — Hold: side review of face clearance and overhead lockout needed. |
| リアデルト / `rear_delt` | authored — Hold: horizontal shoulder abduction present, but resistance/load transmission is incomplete. |
| アブローラー / `ab_wheel` | authored — Knee support and wheel contact present; inspect shoulder/lumbar coordination and extension limit. |
| インクラインフライマシン / `incline_fly_machine` | authored — Hold: reconcile pivot and handle orientation with actual inclined fly mechanism. |

## 追加済み11種：個別判定

| 種目 / ID | 最終判定 |
|---|---|
| インクラインベンチプレス / `incline_barbell_press` | authored — Hold: inspect upper-chest bar contact and forearm alignment from side. |
| ダンベルベンチプレス / `flat_dumbbell_press` | authored — 保留：手首・肘の詳細確認と通常導線QAが未完了。 |
| ダンベルショルダープレス / `dumbbell_shoulder_press` | authored — Hold: bottom handles appear forward of chest rather than beside shoulders; inspect forearms. |
| バーベルカール / `barbell_curl` | verified — 公開：上腕固定・握り・支持姿勢・一周の動作を確認。両OS通常導線確認済み。 |
| ダンベルカール / `dumbbell_curl` | verified — 公開：上腕固定・握り・支持姿勢・一周の動作を確認。両OS通常導線確認済み。 |
| ハンマーカール / `hammer_curl` | verified — 公開：上腕固定・握り・支持姿勢・一周の動作を確認。両OS通常導線確認済み。 |
| ダンベルフライ / `dumbbell_fly` | authored — Constant slightly flexed elbow arc present; inspect dumbbell clearance at closure. |
| デクラインベンチプレス / `decline_barbell_press` | verified — 公開：足台・足首ローラー追加後、再生成・再審査・両OS通常導線確認済み。 |
| デクラインダンベルプレス / `decline_dumbbell_press` | verified — 公開：足台・足首ローラー追加後、再生成・再審査・両OS通常導線確認済み。 |
| インクラインダンベルフライ / `incline_dumbbell_fly` | authored — 保留：閉じた際のダンベル間隔と背もたれ支持を要確認。 |
| リバースカール / `reverse_curl` | verified — 公開：上腕固定・握り・支持姿勢・一周の動作を確認。両OS通常導線確認済み。 |

元の25種以外から存在したラットプルダウン・チンニングはauthoredを維持。今回新たに公開したとは扱わない。

## 今回新規生成した11種

| 種目 / ID | family | 判定・残作業 |
|---|---|---|
| サイドレイズ / `lateral_raise` | raise | authored：既存対象筋metadataと側方挙上の対応確認が未完了。通常導線未実施。 |
| フロントレイズ / `front_raise` | raise | authored：フォーム参照と詳細見た目承認が未完了。通常導線未実施。 |
| トライセプスプッシュダウン / `triceps_pushdown` | pressdown | verified：両OS再生・通常一覧からの遷移まで確認。 |
| バーベルスクワット / `barbell_squat` | lower_body (squat/hinge) | verified：両OS再生・通常一覧からの遷移まで確認。 |
| ルーマニアンデッドリフト / `romanian_deadlift` | lower_body (squat/hinge) | authored：腕の到達補正を2回見直したが、肘の曲がりが残る。再設計が必要。 |
| インクラインダンベルカール / `incline_dumbbell_curl` | curl | verified：両OS再生・通常一覧からの遷移まで確認。 |
| ワンハンドプッシュダウン / `single_arm_pushdown` | pressdown | authored：片手の握りとケーブルの関係の参照・見た目承認が未完了。 |
| リバースグリッププッシュダウン / `reverse_grip_pushdown` | pressdown | authored：逆手での手首・握りの詳細参照と見た目承認が未完了。 |
| ストレートバープッシュダウン / `straight_bar_pushdown` | pressdown | verified：両OS再生・通常一覧からの遷移まで確認。 |
| ローププッシュダウン / `rope_pushdown` | pressdown | verified：両OS再生・通常一覧からの遷移まで確認。 |
| グッドモーニング / `good_morning` | lower_body (squat/hinge) | verified：両OS再生・通常一覧からの遷移まで確認。 |

## 品質修正

- 第1バッチ14種は一律昇格せず全件保留。数値・両OS表示が通っても機構や接触の問題を解消したとは扱わない。
- マシン3種：chest_press / pec_flyはレバー長・前方距離をパラメータで短縮し、到達不能エラーを解消したpreviewを作成。ただし負荷伝達・機構の品質不足でplanned / assetPath nullを維持。shoulder_pressも水平プレス転用を避けplannedのまま。
- インクラインカール：座位の脚幅を狭め、上腕位置とダンベルの腿への近接を調整。開始時ニュートラルから回外する握りと、背もたれに接続した支持柱を追加。両OS再確認後公開。
- デクライン2種：足台と足首ローラーを既存人体に合わせ追加。脚の支持を確認後公開。
- ローププッシュダウン：手のひらに沿っていたロープを、分岐点からの長いロープ＋握りを横断する短いグリップ部へ修正。左右のストッパーと固定長の分岐を維持。
- レイズ：左右のダンベル軸・握りを修正。前方挙上の面をわずかに外へ開き、ダンベル同士の接近を減らした。まだ公開しない。
- RDL、フロントスクワット、ゴブレットスクワットは修正preview後も支持・握りの問題が残り保留。後2種はplannedで未出力。

## 共通化と次の対象

新規familyはlower_body（足を接地させたsquat/hinge）、pressdown（bar/rope・握り・片手パラメータ）、raise（挙上面・肘角度）。curlをインクラインへ横展開し、既存pressをデクライン修正で再利用。既存人体・rig・材質・照明・器具部品とチャンク共有を継続した。

次の主要対象：保留RDLとフロント/ゴブレットスクワット、レッグプレス、レッグエクステンション、レッグカール、カーフ、頭上三頭筋伸展、ケーブルレイズ。既存familyで成立しない軌道を無理に流用しない。

## QA・実行結果

- Blender：元25種、新規11種、修正版のpacked GLBを再構築し97フレーム検査。床下侵入、画角外、動作跳躍、ループ接続を確認。見た目未承認は上表のまま。
- Python：`python3 -m unittest discover -s tool/exercise_forms/tests` — 54件成功。
- Flutter：`flutter test --no-pub test/bench_press_form_test.dart test/exercise_form_catalog_test.dart test/form_qa_plan_test.dart` — 20件成功。最後の公開フラグ更新後もcatalogテスト6件成功。
- `flutter analyze --no-pub` — No issues found。
- iOS専用QA Simulator / Android MUSCLEMORY_Batch_QA：元25種と新規11種の読み込み・再生・一時停止・再開・解放を確認。今回公開12種すべて、両OSの通常Picker→詳細の遷移も確認。
- 既存verifiedの代表dy_rowも両OSで確認。既存6件の定義一致を別途検査。
- AndroidでPixelCopyキャプチャtimeoutが一度発生。キャプチャ限定で最大3回の再試行を入れ、再試験成功。読み込み・描画失敗を握り潰す変更ではない。
- iOS通常導線で画面外の脚カテゴリをタップして失敗。テスト操作のensureVisibleを修正し再試験成功。
- Androidレイズ最初の起動は古いAPKであると検出し中止。`phase2-android-raises-drive2.log`だけを有効な結果として使用。
- Native debugビルド両OS成功。SDK XML版の既存警告、環境描画warningは残る。releaseビルドや物理端末の性能試験を実施したとは扱わない。
- 物理iPhone/Galaxyで残る確認：実GPUの描画品質、持続再生の発熱・フレームレート、メモリ、タッチ体験。

証跡はignored `build/exercise_forms/phase2-*`。元25種は `phase2-roundtrip/report.json`、修正版はrevised/contact/rdl-final/raises-roundtrip。OSログはios/androidのdrive、公開導線はroute/support/arms-route。開始・途中・停止・再開のスクリーンショットを保存。これは配布アセットではない。

## 容量

- forms＋共有chunks：28,721,034 → 34,970,467 bytes、増加6,249,433 bytes（約6.25 MB）。
- 新規11種で割った平均：約0.57 MB/種目。既存モデル修正分も含むため、各モデルの独立ファイルサイズではない。
- 全assets/models：約49.66 MB。生成途中GLB・previewはアプリへ重複同梱しない。
- 最大recipeは既存cable_rowの105,627 bytes。新規最大はtriceps_pushdownの101,809 bytes。バイナリは共通chunksを参照するのでrecipeサイズだけでモデル総容量とはしない。
- 現在参照されない旧revision chunkは約0.10 MB。今回大量削除はしていない。

## Reference observations

- [Mayo Clinic dumbbell curl](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/biceps-curl/vid-20084675): fixed upper arm and wrist, controlled elbow motion.
- [Catalyst hammer curl](https://www.catalystathletics.com/exercise/841/Hammer-Curl/): inward-facing palms throughout.
- [M&F barbell curl](https://www.muscleandfitness.com/exercise/workouts/arm-exercises/barbell-biceps-curl/) and [reverse curl](https://www.muscleandfitness.com/exercise/workouts/arm-exercises/reverse-grip-barbell-biceps-curl/): supinated/pronated grip, stationary upper arms.
- [Life Fitness decline bench](https://www.lifefitness.com/en-gb/catalog/strength-training/benches/life-fitness-adjustable-decline-bench): leg-support reference. Procedural support is an original simplified construction, not a replica of the product. Manufacturer PDF text was accessible; PDF image capture failed.
- [Catalyst front squat](https://www.catalystathletics.com/exercise/78/Front-Squat/) and [NASM goblet squat](https://www.nasm.org/resource-center/exercise-library/goblet-squat): load support, planted feet, coordinated knees/hips.
- [ACE RDL](https://www.acefitness.org/continuing-education/certified/may-2025/8865/the-ace-do-it-better-series-the-romanian-deadlift/): posterior-chain hip hinge reference. The first paper PDF was inaccessible; a separate NASM good-morning description was subsequently read.

No external 3D assets, images or new packages added. Reuses the existing Athlete,
rig/materials and original procedural equipment.

追加で読んだ参照：

- [ACE back squat](https://www.acefitness.org/resources/everyone/exercise-library/11/back-squat/) — 上背部のバーベル支持、足の接地。
- [NASM good morning](https://www.nasm.org/resource-center/exercise-library/good-mornings) — 膝の軽い屈曲と中立体幹のhip hinge。
- [M&F pressdown](https://www.muscleandfitness.com/exercise/workouts/arm-exercises/triceps-pressdown/) — 高いプーリー、上腕固定から肘伸展。
- [Life Fitness attachments](https://shop.lifefitness.com/products/cable-attachments) — ケーブル付属グリップ形状。
- [M&F incline curl](https://www.muscleandfitness.com/exercise/workouts/arm-exercises/incline-dumbbell-biceps-curl/) — 傾斜座位、上腕を保つカール。
- [Catalyst lateral raise](https://www.catalystathletics.com/exercise/825/Dumbbell-Lateral-Raise/) — 側方挙上の腕の軌道。
- [ACE shoulder PDF](https://contentcdn.eacefitness.com/certifiednews/images/article/pdfs/ShoulderExercises.pdf) — テキスト参照のみ。画像取得できず、フロントレイズ参照承認には利用していない。

外部3D素材・画像・新規パッケージ追加なし。既存MPFB Athleteと既存ライセンス資料を維持。参照画像そのもののアプリ組み込みなし。

## Git結果

`git status --short` 全文：`build/exercise_forms/phase2-final-git-status.txt`。
`git diff --stat` 全文：`build/exercise_forms/phase2-final-git-stat.txt`。
多数の共有chunk追加は未追跡のため通常diff --statには含まれない。開始時からの3D差分を含む。
`git diff --check` 成功（終了コード0、出力なし）。追跡済み14ファイル変更、未追跡2,917件（共有chunk・recipe・QAコード等、開始前の差分を含む）。diff --statは14 files changed, 2191 insertions(+), 738 deletions(-)。commit / pushなし。
