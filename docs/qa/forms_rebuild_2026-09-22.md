# 全作成済みフォームの再制作

> 本書は46種再制作の途中経過・停止時点を記録した履歴です。以下の停止時点の公開数、カタログ件数、Python件数は現行集計ではありません。最新の確定進捗（通常公開18種、保留19種、両OS確認12/46、Python54・Flutter20）は [現行確定仕様](../current_spec.md) を優先します。

ユーザー指示：ベンチプレス・インクラインダンベルプレスの2種目のみ維持。他の作成済みフォームは全て再制作。従前の数値チェック・OS表示結果を品質承認として引き継がない。追加量産は停止。

## 公開取り下げ

対象 46 種目の公開・試用と全レビュー判定を解除。旧アセットは削除せず比較用に保持。種目やトレーニング記録は削除しない。再制作完了・実機資料との照合・全動作/接触/両OS/通常導線確認までは再公開しない。以下の一覧は作業開始時点の退避状態。最新の判定は「現在地点」を参照。

| ID | 種目 | 旧状態 | family | 再制作状況 |
|---|---|---|---|---|
| incline_barbell_press | インクラインベンチプレス | authored | press | 未完了・公開停止 |
| flat_dumbbell_press | ダンベルベンチプレス | authored | press | 未完了・公開停止 |
| incline_press_machine | インクラインベンチプレスマシン | authored | hinged_press | 未完了・公開停止 |
| decline_fly_machine | デクラインペックフライマシン | authored | fly | 未完了・公開停止 |
| decline_press_machine | デクラインベンチプレスマシン | authored | hinged_press | 未完了・公開停止 |
| lat_pulldown | ラットプルダウン | authored | pulldown | 未完了・公開停止 |
| mag_narrow | ラットプルダウン MAGグリップ ナロー | authored | pulldown | 未完了・公開停止 |
| mag_medium | ラットプルダウン MAGグリップ ミディアム | authored | pulldown | 未完了・公開停止 |
| mag_wide | ラットプルダウン MAGグリップ ワイド | authored | pulldown | 未完了・公開停止 |
| chin_up | チンニング | authored | chin_up | 未完了・公開停止 |
| assisted_chin_up | アシストチンニング | authored | chin_up | 未完了・公開停止 |
| deadlift | デッドリフト | authored | hinge | 未完了・公開停止 |
| dy_row | DYロー | verified | lever_row | 未完了・公開停止 |
| low_row | ローロー | verified | lever_row | 未完了・公開停止 |
| linear_row | ライナーロウ | authored | linear_rail_row | 未完了・公開停止 |
| high_row | ハイロー | verified | lever_row | 未完了・公開停止 |
| cable_row | ケーブルロー | authored | row | 未完了・公開停止 |
| back_extension | バックエクステンション | verified | back_extension | 未完了・公開停止 |
| weighted_back_extension | バックエクステンション（荷重） | authored | back_extension | 未完了・公開停止 |
| dumbbell_shoulder_press | ダンベルショルダープレス | authored | overhead_press | 未完了・公開停止 |
| military_press | ミリタリープレス | authored | overhead_press | 未完了・公開停止 |
| lateral_raise | サイドレイズ | authored | raise | 未完了・公開停止 |
| front_raise | フロントレイズ | authored | raise | 未完了・公開停止 |
| rear_delt | リアデルト | authored | reverse_fly | 未完了・公開停止 |
| barbell_curl | バーベルカール | verified | curl | 未完了・公開停止 |
| dumbbell_curl | ダンベルカール | verified | curl | 未完了・公開停止 |
| hammer_curl | ハンマーカール | verified | curl | 未完了・公開停止 |
| triceps_pushdown | トライセプスプッシュダウン | verified | pressdown | 未完了・公開停止 |
| barbell_squat | バーベルスクワット | verified | squat | 未完了・公開停止 |
| leg_extension | レッグエクステンション | authored | knee_machine | 未完了・公開停止 |
| romanian_deadlift | ルーマニアンデッドリフト | authored | hinge | 未完了・公開停止 |
| ab_wheel | アブローラー | authored | rollout | 未完了・公開停止 |
| incline_fly_machine | インクラインフライマシン | authored | fly | 未完了・公開停止 |
| dumbbell_fly | ダンベルフライ | authored | fly | 未完了・公開停止 |
| decline_barbell_press | デクラインベンチプレス | verified | press | 未完了・公開停止 |
| decline_dumbbell_press | デクラインダンベルプレス | verified | press | 未完了・公開停止 |
| incline_dumbbell_fly | インクラインダンベルフライ | authored | fly | 未完了・公開停止 |
| incline_dumbbell_curl | インクラインダンベルカール | verified | curl | 未完了・公開停止 |
| reverse_curl | リバースカール | verified | curl | 未完了・公開停止 |
| single_arm_pushdown | ワンハンドプッシュダウン | authored | pressdown | 未完了・公開停止 |
| reverse_grip_pushdown | リバースグリッププッシュダウン | authored | pressdown | 未完了・公開停止 |
| straight_bar_pushdown | ストレートバープッシュダウン | verified | pressdown | 未完了・公開停止 |
| rope_pushdown | ローププッシュダウン | verified | pressdown | 未完了・公開停止 |
| sumo_deadlift | スモウデッドリフト | authored | hinge | 未完了・公開停止 |
| seated_leg_curl | シーテッドレッグカール | authored | knee_machine | 未完了・公開停止 |
| good_morning | グッドモーニング | verified | hinge | 未完了・公開停止 |

優先：ケーブルロー、ライナーロウ、アシストチンニング、DYロー、ハイロー、リアデルト、インクライン系ベンチ。

## 現在地点（2026-09-22、作業継続中）

（停止時点の記録）全46種目の再制作は未完了。公開再開は12種目（下表の確認完了分。配布・pushなし）。元の2種目と合わせ通常公開14種目、未完了34種目はauthoredのまま非公開。15種目の修正アセットをパック済みだが、未確認の3種目は公開しない。インクラインバーベルは押し上げ終点の問題で一度完了判定を撤回した後、新軌道で再生成し両OS・通常導線を再確認済み。旧レシピは `build/exercise_forms/rebuild_20260922/previous-recipes` に保持。元の2種目は変更しない。現行集計は本書冒頭のリンク先を参照する。

| 修正候補 | 主な修正 | ネイティブQA | 残り |
|---|---|---|---|
| dy_row | 専用フレーム、座面・胸パッド、逆手の前腕ロール、負荷プレート上昇 | iOS / Android full成功 | 完了・表示再開 |
| high_row | 上部独立アーム、胸へ引く軌道、曲管ハンドル、順手・8度グリップ | iOS / Android full成功 | 完了・表示再開 |
| rear_delt | 専用座面・長い胸パッド、内側水平グリップ、水平に近い肘の軌道 | iOS / Android full成功 | 内部機構の照合、品質判定・通常導線 |
| incline_barbell_press | 背板支持・ベース、肩の上まで伸ばす終点、固定握り幅 | 最新iOS / Android full成功 | 完了・表示再開 |
| cable_row | 横置き塔、低滑車、座面・足裏・足台、縦グリップの手首、反対側カメラ | iOS / Android full成功 | 完了・表示再開 |
| linear_row | 足裏平面、レール下端支持、腕の到達範囲、引く位置・肘・手首 | iOS / Android full成功 | 完了・表示再開 |
| assisted_chin_up | 複数持ち手、接続フレーム、膝昇降。追加で上昇量を0.34mから0.44mへ修正 | 最新候補iOS / Android full成功 | 完了・表示再開 |

| low_row | 独立アーム・座面・胸パッド・手首ロール | iOS / Android full成功 | 完了・表示再開 |
| flat_dumbbell_press | 再建ベンチ、腕長に合った上端、下端の握り幅 | iOS / Android full成功 | 完了・表示再開 |
| dumbbell_shoulder_press | 再建ベンチ、下端で前腕を立てる握り幅 | iOS / Android full成功 | 完了・表示再開 |
| barbell_curl / dumbbell_curl / hammer_curl | 前腕ロールと握り、全ループ再生成 | iOS / Android full成功 | 完了・表示再開 |

### 接触・負荷・動作の確認

- 7候補の開始・中間・終点と往復13時点、前面・側面画像を保存。単にアンカー誤差が小さいだけでは関節の向きが正しいとは限らないため、前腕と手の方向も別途測定。
- DYの旧カウンターアームは引く側でプレートが下降していた。修正後は97時点で各プレート上昇（約47mm）を確認。各プレートを個別に確認する自動チェックを追加。途中だけ下降するケース、片側不良、無移動を単体テストで拒否。
- ケーブルローの旧ドラフトは手首の方向差が最大99.7度。縦グリップ軸と指列・前腕方向を合わせた最新候補は27.1度。ライナーロウは46.8度から38.5度、アシストチンニング21.5度、DY約27度、ハイロー約24度。これらは観察指標であり医学的／解剖学的な合格基準ではない。
- ハイローは公式実演の12秒と19秒付近を照合。DYは逆手、ハイローは順手。両者を一律に逆手にしない。
- リアデルトは公式取扱説明書9481201 BEの28ページで胸をパッドへ向け、内側の水平ハンドルを使うことを確認。未確認の内部ケーブル経路は露出させずカバー内とした。伝達比の完全照合は未完了。
- ライナーロウは当初、開始到達距離532mmが腕長518mmを超えて生成失敗。手の接触オフセット込みで開始位置を計算する方式へ修正して97フレーム生成成功。メーカー実演画像に合わせたレール・支持材・握りは引き続き最終品質確認が必要。

### 次の再制作

lat_pulldown / mag_narrow / mag_medium / mag_wide の機器部分を改修中。HS-PD公式画像とMJLPマニュアルを参照し、構造フレーム、調整式腿ローラー、接続された座面、重量塔・カバーを実装。ケーブルの伸び縮みを避けるため実ケーブル長差でスタックを動かす。まだ新アセットをパックしていない。MAGグリップはメーカーのCN001実際の握り写真とWG007形状写真を確認。専用プレビューによる接触確認は未完了。

### 検証結果・失敗の扱い

- Python制作補助テスト62件成功（`python-route-recheck.log`）。Flutter analyze指摘なし。
- iOS第1組: `ios-native-final.log`。178 Flutterテスト、iOSビルド、4種目fullネイティブQA成功。
- Android: `android-native-retry.log`。178 Flutterテスト、APKビルド、7種目fullネイティブQA成功。専用AVD `MUSCLEMORY_Batch_QA` のみ使用。
- iOS第2組: `ios-secondary-native-idle.log`。178 Flutterテスト、ビルド、ケーブルロー・ライナーロウ・旧アシスト候補のfull成功。専用 `MUSCLEMORY QA` のみ使用。
- 失敗履歴: 固定194件期待のidentityテストをsource件数との一致・一意性へ修正。制作中catalogと生成データを同時変更した実行は不一致で失敗し、同期後に再実行。タイマー34秒／60秒の厳密表示期待が重い同時処理中に失敗した実行がある。対象テスト単独成功、制作と分けたAndroid全178件成功。タイマー実装・そのテストは変更していない。
- nativeの成功は読込・表示・再生・一時停止・再開・破棄の成功であり、見た目やユーザー承認の代わりではない。5種目の通常カテゴリ→詳細ルートはiOSで成功（`ios-route.log`）、Androidも成功（`android-route.log`）。レビューを迂回して公開しない。
- git diff --check成功。新しいGLB・編集可能なBlender・プレビューはbuild配下。元のBlender GUI、ユーザー端末、ユーザーデータには触れていない。

## 照合資料（画像・CAD・ロゴはアプリに同梱しない）

- DY: https://www.lifefitness.com/ja-jp/catalog/strength-training/plate-loaded/plate-loaded-iso-lateral-d-y-row
- DY実演: https://player.vimeo.com/video/1050766924
- High: https://www.lifefitness.com/ja-jp/catalog/strength-training/plate-loaded/plate-loaded-iso-lateral-high-row
- High実演: https://player.vimeo.com/video/1064752886
- Rear: https://www.lifefitness.com/en-us/catalog/strength-training/selectorized/insignia-series-pectoral-fly-rear-deltoid
- Assist: https://www.lifefitness.com/en-gb/catalog/strength-training/selectorized/insignia-series-assist-dip-chin
- Insignia取扱説明書: https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf
- Linear: https://www.deltafitness.shop/product/907
- Linear実演写真: https://act-energy.co.jp/20260406-2/
- Cable row: https://www.bodykore.com/product/isolation-series-selectorized-low-pull-gr616
- Lat: https://www.lifefitness.com/en-eu/catalog/strength-training/selectorized/hammer-strength-select-lat-pulldown
- Cable Motion説明書: https://www.lifefitness.com.au/wp-content/uploads/2015/02/Cable_Motion_Manual_11_08a_1_56.pdf
- MAG CN001: https://www.maxagrip.com/close-grip-neutral-cn001/

- MAG WG007形状: https://www.maxagrip.com/wide-grip-wg007/

### 再開時点の追加確認

- アシスト最上点を側面で確認したところ顎がグリップ高さに届かなかったため、`assistedPullTravel: 0.44`へ修正。終点側面・往復13時点を再描画し、顎・膝パッド接触を確認。重量スタック初期高さも1.03mへ上げ、下降時の積層部との干渉を回避。最新出力は`assist-range-review` / `assist-range-export`。旧0.34m候補のOS結果を新アセットの承認へ流用しない。
- ラットプル4候補は`pulldown-review`、`pulldown-path-review`、`pulldown-elbow-review`に保存。下端を胸まで下げると手首方向差が約64〜68度へ悪化、肘方向修正でも改善せず（代表約72度）。同じ不具合の2回修正で解決できないため、このシーンの試行を止めて未公開を維持。次は手首とグリップの回転拘束を解析し、姿勢の数値だけを場当たり的に調整しない。これらの新プレビューはパックしていない。
- 通常導線QAは通常catalogで解析・unit testを完了してから、対象IDだけ一時候補を生成しビルドする方式へ整理。終了時は成功・失敗とも通常catalogに復元。生成器の前段5レビュー必須条件は維持。wrapper成功・失敗・不正IDの8テストを追加/更新。
- iOS通常導線の5キャプチャを目視確認。画像は`ios-route-screens`に保存。
- Low rowはIL-LRメーカー製品資料と実演動画（26秒付近の握りと低い引き位置）を追加確認。順手、独立アーム、胸支持。後続のLow row制作メモへ結果を追記。
- インクラインベンチ支持構造資料: https://shop.lifefitness.com/products/hammer-strength-home-multi-adjustable-bench
- Low row資料: https://www.lifefitness.com/en-us/catalog/strength-training/plate-loaded/plate-loaded-iso-lateral-low-row
- Low row実演: https://player.vimeo.com/video/1089148269

### Low row制作メモ（未承認）

公式IL-LRの写真・実演26秒付近で確認した点：低い握り位置、胸支持の座位、左右独立の上部支点、下降アーム、斜めの順手ハンドル、上部ロードホーン、片手動作用の固定ハンドル、収納ホーン6本。公開寸法127×122×168cmは全体比率の参考とする。CADを使わず、リグへ合わせた寸法・ヒンジ角・荷重板をオリジナル形状で作る。内部伝達の未確認事項を数値検査だけで承認しない。

- Android通常導線の5種目も成功。画面画像を目視し、5種目の`productionRoute`を完了、`verified`へ更新。通常生成へ戻したことを確認済み。Android描画はiOSより反射が弱いが、支持位置・全体収まり・読み込みは維持。ユーザー承認を得たという意味ではない。
- Low row専用フレーム・座面・胸パッド・斜めグリップ・独立レバーを追加、preview生成中。既存DY/highのパラメータや出力は変更しない。制作補助Python62件は成功。

### Low row最新候補と次の資料

Low rowの初稿では終点の手首方向差が55.7度。丸いハンドルの軸方向を保持し、握りのロールを動作中に変える候補で最大29.9度、終点9.8度になった。13時点・前面/側面の始終点を目視。各負荷プレートは約91mm上昇、掌アンカー誤差最大0.00000038m。最新は`low-row-grip-review`、`low-row-export`。GLB 4,260,324 bytesをパック、まだauthored。アシスト最新版と合わせた`ios-low-assist.log`はanalyze、178 Flutterテスト、iOSビルド、2種目fullネイティブ確認が成功。キャプチャを確認済み。Androidと通常導線は未完了。

次のベンチ2種目の資料：
- https://www.acefitness.org/resources/everyone/exercise-library/19/chest-press/
- https://www.acefitness.org/resources/everyone/exercise-library/45/seated-overhead-press/

両者ともベンチと頭・体幹・臀部の支持、足裏の接地、順手の握りと手首の自然な向きを照合。ダンベルプレスは胸へ下ろして上へ押す。ショルダープレスは背もたれを使った座位で肘を体の真横より少し前に置く。資料の写真を確認した段階で、次のモデルの承認はまだ行っていない。

### ダンベルプレス再開時の確認

フラットプレスの上端は肘屈曲約62度から約16度へ改善。ただし`flat-press-neutral-review`と`bench-presses-reach-review`の側面確認で両種目の下端屈曲約138度を検出し、承認せず保持。前腕を垂直に合わせるだけではグリップ幅が狭すぎたため、下端幅を0.86mへ調整した`bench-presses-width-review`を生成中。手首数値が改善しても姿勢全体の品質保証とはしない。元の2種目は変更しない。

ダンベル2種目の最新候補：下端幅0.86mに調整し、フラットの下端肘屈曲約110度、ショルダー約103度、手首方向差最大17.4度/12.6度。13時点の往復・側面始終点を目視確認。`bench-presses-width-review`が最新。元の2種目とは別のrecipe opt-in。`bench-presses-export`の2GLB合計8,234,668bytesをパックしcameraを反映。両OS/通常導線はこれから確認。Python62件成功（`python-press-width.log`）。

次のカール3種目の照合：Mayo Clinicのダンベルカール説明で肘を体側に保ち、上腕を振らず手首を固定する点を確認。Muscle & Fitnessのbarbell curl始終点写真とCatalyst Athleticsのhammer curl実演で、逆手とニュートラルの違い・ダンベル姿勢を確認。`curl-rebuild-review`で前腕の回旋を手の握りに合わせた候補をプレビュー中。資料は参照のみ、アプリへの転載なし。

Android最新版4種目（low_row / assisted_chin_up / flat_dumbbell_press / dumbbell_shoulder_press）は`android-next-full.log`でanalyze・178 Flutter tests・APK build・full native成功。`android-next-screens`を目視。Blender並行時にEmulator描画待ちが出たため途中で当該previewプロセスを一時停止し、QA終了後に再開。アプリ側の描画コードは変更していない。フラットは既存`legacy_press`カメラで収まりを確認（書き出しcamera metadataは保存するがruntimeは従来presetを使用）。

### 再開後の確認

- flat_dumbbell_press / dumbbell_shoulder_pressの最新iOS fullも成功（`ios-press-full.log`）。low_row / assisted_chin_upとともに両OS通常導線待ち。
- incline_barbell_pressは握り幅を固定し、上端を肩の上へ修正。以前のAndroid/通常導線結果は流用しない。
- barbell_curl / dumbbell_curl / hammer_curlは前腕ロールを握りに合わせ再生成し、往復13時点と正面・側面を確認。
- 上記カール3種目と新インクラインのiOS full成功（`ios-curl-incline-full.log`）。4種目のキャプチャ確認済み。Androidと両OS通常導線はこれから実施。

### 次のカール・立位プレス資料確認（制作前）

- リバースカール: https://www.muscleandfitness.com/exercise/workouts/arm-exercises/reverse-grip-barbell-biceps-curl/ の実演動画・開始終了写真を確認。順手、上腕は体側で固定、反動を使わない。
- インクラインカール: https://www.muscleandfitness.com/exercise/workouts/arm-exercises/incline-dumbbell-biceps-curl/ の実演・写真は45度背もたれ、両足接地、背中を支え、上腕を下へ保ち掌を前へ向ける。新候補はこの角度と順手でない通常の回外グリップを使用し、下端での過度な外転・ベンチとの干渉を確認する。旧60度/回外移行パラメータはまだ本番変更しない。
- 立位プレス: https://www.catalystathletics.com/exercise/90/Press/ の実演を確認中。肩から頭上へ押し、頭を避けた後はバーを首の付け根上へ。大きな後傾や脚の反動を使わない。

- 新インクライン/カール3種目のAndroid fullも成功（`android-curl-incline-full.log`、178 Flutterテスト、APKビルド、4種目full）。最新Android画像でインクライン上端の肘伸展とカール下端も確認。8候補の両OS通常導線を開始。
- Catalystの立位プレス実演では上端で肘が伸び、バーが肩の真上付近へ戻ることも目視確認した。参考画像や動画をアプリへ同梱しない。

- 2026-09-23: iOS通常導線8種目成功（`ios-next-eight-route.log`、各種目キャプチャあり）。通常catalogの復元を確認。Android通常導線を専用MUSCLEMORY_Batch_QAで開始。旧caffeinateプロセスが終了していたため再開時に`caffeinate -i -d`を新規起動、PID85014を記録。恒久設定変更なし。

- 2026-09-23: Android通常導線8種目も成功（`android-next-eight-route.log`）。両OSの各種目の詳細キャプチャを目視し、対象8種目のproductionRoute/verifiedを反映。合計12/46種目が再制作の確認完了、34種目未完了。ユーザーによる外観承認を意味しない。原本2GLBのSHA-256も再照合して一致。
- Android確認と2スレッドのBlender描画を並行してもfence待ちが出たため、自分のBlender PID86114のみ一時停止し、Android終了後に再開した。今後ネイティブ描画とBlenderレンダーは並行させない。


## 2026-09-23 ユーザー指示による一時停止・再開地点

追加制作を停止。完成12種目のみ既存のverifiedを維持し、残り34種目を昇格・削除しない。カタログ195件はverified14 / authored34 / planned147。全previewEnabledはfalse、一時QA候補なし。生成Dartとsourceは一致。

未完了のasset/recipe/chunk/parameter/motion family/Blender/QAログは現在のworkspaceに保持。`build/exercise_forms/rebuild_20260922/` は再開に必要な未追跡・ignore対象の作業ディレクトリであり、削除しない。ZIPやsnapshotは作成しない。

- reverse_curl / incline_dumbbell_curl: `review_curl_variants.py`、`curl-variants-review/`、`export_curl_variants.py`、`curl-variants-export/` を保持。新出力をpack済みだがcatalogのパラメータ・レビュー更新および両OS確認は未完了。両方matchedForearmRoll=true、inclineのみrebuildAdjustableBench=true / benchAngle=45 / supinating=falseの候補。再開時のcamera反映元はexport側を使用（レビューのfront/side撮影後のcameraは採用しない）。今回ここから先は進めない。
- military_press: `review_military_round_grip.py` と `military-round-grip-review/` のBlender候補出力まで終了。roundBarGripの候補実装はscratch内のみ、production authorへ未反映。画像・顔とバーの干渉・手首監査が未完了なので未承認。前候補verticalForearmPressは顔干渉あり。新候補を未確認のまま公開しない。
- rear_deltの機構確認、lat/MAGの手首問題は引き続き保留。以前の失敗と次の検討点を維持。
- 生成・QA実行プロセスは終了済み。新規生成、ビルド、端末QAは追加しない。
- 最終read-only整合性確認: 195 ID一意、全参照asset存在、5160チャンクのSHA-256/長さ一致、source/generated一致、公開レビューゲート成立、原本2GLBのSHA-256一致。
- Flutter analyze: No issues found。Python QA: 64 tests成功（final-pause-python.log）。Flutter関連テストはfinal-pause-flutter-test.logに保存。

- 最終Flutter関連3ファイル: 20 tests成功。git diff --check成功。git差分はtracked23ファイル（+3616/-1194）、untracked5149ファイルを保持。commit/pushなし。
- 一時停止に伴い自分が起動したcaffeinate PID85014を終了し、自動スリープ防止を解除。
