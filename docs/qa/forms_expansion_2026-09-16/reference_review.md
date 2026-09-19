# 制作前の器具・動作確認

「資料確認」「形状制作」「静止確認」「動作確認」「アプリ確認」を区別する。手首の座標一致だけで合格にしない。

## ラットプルダウン / MAG
- Life Fitness Optima manual (OSLR), 印刷ページ14: https://www.lifefitness.com.au/wp-content/uploads/2015/02/Optima_user_manual_for_all_strength_2_585_1371787541.pdf
- 索引の説明文を確認。PDF画像は取得失敗、使用動画未確認。資料確認は未完了。
- 説明: 太ももをパッドの下に置く、わずかに後傾、胸の前へ引き、制御して戻す。
- CN001: https://www.maxagrip.com/close-grip-neutral-cn001/ 中指間5インチ=0.127m。商品写真確認済み。向き合う掌支持部と中央接続部。仮の0.30m幅と円柱のみの形状は不適切。
- MN004: https://www.maxagrip.com/medium-grip-neutral-mn004/ 中指間22インチ=0.5588m。
- WG007: https://www.maxagrip.com/wide-grip-wg007/ 中指間38インチ=0.9652m。
- MN004/WG007もメーカー商品写真を確認済み。中指間距離と掌支持部を共通形状の差分へ反映。
- 使用者はケーブル塔側に向かって座る。塔を背後に置いていた試作は不合格。

## ライナーロウ
- 指定資料: https://www.deltafitness.shop/product/907 DFシリーズ LINEAR ROW DF001A。
- 商品写真確認済み。傾斜したパッド・足台・左右の傾斜ガイド・プレート装着部を確認。写真だけで胸当てと判断してはいけない。座位ケーブルローの流用はしない。
- 使用動画または取扱資料で姿勢・可動範囲を確認してから制作する。

商品画像は観察用であり、アプリ素材として複製していない。

## ライナーロウ 使用方法の追加確認
- 設置・指導ジムの実演: https://act-energy.co.jp/20260406-2/ （DELTA製リニアロウ）
- 開始と引き切りの実演写真をブラウザーで確認。指定商品のフレーム・足台・ガイド配置と一致。
- パッドには胸ではなくお尻を当てる。足を前方の足台に置き、膝は軽く曲げ、体幹を保ってグリップを胸方向へ引く。
- 左右キャリッジは傾斜ガイド上を直線移動する。通常の座位ローや胸支持Tバーローとは別の器具・姿勢として制作する。
- 未確認: 連続動画、ストローク長の製品公表値。実演の開始・終了写真から姿勢範囲を設定し、製品寸法からの推定値は推定として扱う。

## デクラインフライ / デクラインプレスの再調査
- Panatta 1FW044: https://www.panattasport.com/en/free-weight-special/super-lower-chest-flight-machine/
- メーカー実演: https://www.youtube.com/watch?v=0UDQ8CzNxbQ
- 5秒: 本体・独立レバー、15秒: 調整と座部、25秒: 開始補助レバー、30秒: 開いた状態、35秒: 胸の下側へ寄せたニュートラルグリップを確認。全動画を通しての確認は未完了。
- 傾斜した背もたれに座り、左右の独立レバーで下胸部へ収束。下向きベンチの仮実装を置き換える。機構寸法・角度は実演からの推定で、製品CADの複製ではない。
- 参考比較: Impulse ECP207 https://www.impulsehealthtech.com/ecp207-horizontal-decline-pec-fly-product/ 商品画像確認。水平/デクライン切替と回転ハンドル。ただし今回は複数機種の機構を混ぜない。
- Hammer Strength IL-DCP: https://shop.lifefitness.com/products/hammer-strength-plate-loaded-iso-lateral-decline-chest-press
- メーカー説明は上体を起こした座位・ベルト・下向き押し出し。既存の負角度ベンチ試作とは異なる。器具と使用姿勢の視覚確認後に作り直す。

## 制作・公開の条件
- 制作前に各種目の参照URLと器具確認をカタログへ記録する。未確認の種目は生成処理が停止する。
- 新規種目の正式有効化には資料、静止形状、動作、Android、iOS、製品導線の各確認が必要。下書き生成やファイルの存在のみで対応済みにしない。
- 写真や動画は観察用。アプリへ複製しない。人体は既存のMPFBアセット（既存ライセンス文書参照）、器具は独自制作。

## ケーブル式ラットプルダウンの実演追認
- Life Fitness Pro2公式: https://www.youtube.com/watch?v=nZip-pdLlQM
- 0:29〜0:56の設定説明、1:00〜1:29の動作説明を字幕で確認。1:15の下降姿勢と1:20の戻し姿勢を映像でも確認。
- 大腿をパッドの下へ入れる、上体と頭部を保つ、肘はバーの下へ向ける、制御して戻す。首の後ろへ引く動作とは分ける。
- 現在の標準ケーブル型の資料として採用。Optimaの別動画はレバー式の機種だったため、器具構造の参照には採用しない。
- MAGの支持部・幅はMAG公式製品資料、基本の座位と肘の方向はケーブル式の実演を参照。グリップの相違を消して同一フォームにしない。

## Decline press machine: manufacturer reference correction
- Source: https://shop.lifefitness.com/products/hammer-strength-plate-loaded-iso-lateral-decline-chest-press
- Embedded manufacturer demonstration: https://player.vimeo.com/video/1038957272
- Observed product photo and demonstration at 14 and 19 seconds: near-upright back support, upper pivot in front of the user, forward/downward converging press. This differs from the incline machine's upper/rear pivot. The old negative-angle bench draft was incorrect.
- Reuse rigid hinged-press authoring with a front pivot; do not reuse the old below-body press linkage. Artist-defined dimensions are fitted to the existing human, not claimed to be exact manufacturer CAD dimensions.
- Static draft generated; camera occlusion and full movement review remain. Not production-approved.

## Assisted chin-up: further review (not yet authored from this source)
- Manufacturer demonstration: https://www.youtube.com/watch?v=acMgjzqo5AI (Panatta, Chin and Dip Counterbalanced / FitEvo).
- Observed at 20 s: access steps, front-facing user and raised knee platform. At 35–40 s: knees supported, lower legs bent behind, upper grips fixed, assistance platform carried by a linked lever rather than floating or unsupported in space.
- Old authored draft's isolated moving knee pad is insufficient. Linkage, counterweight and user path need reconstruction and endpoint/loop review. These observations do not certify the old draft.

## Unassisted チンニング
- Reference: https://www.acefitness.org/resources/everyone/exercise-library/191/pull-ups/
- Preserve the existing exercise identity and overhand variation when changing the Japanese display name. This is the pronated pull-up reference, not ACE's distinct supinated chin-up variation.
- Review criteria: controlled vertical trunk without swinging, closed grip with thumb opposition, neutral wrist, elbows downward, chin reaching bar height and controlled return toward extension. Bent legs clear the floor; the unsupported exercise has no knee pad.

## Low row: manufacturer review and draft v2
Source: https://www.lifefitness.com/ja-jp/catalog/strength-training/plate-loaded/plate-loaded-iso-lateral-low-row and embedded official https://player.vimeo.com/video/1089148269 . Reviewed 10/20/25/27-second frames: chest-supported seated posture facing the tower, upper front pivots, low overhand handles; 27 seconds shows unilateral pulling. This is not a claim of continuous full-video review or exact CAD reproduction. Original simplified rigid levers use author-selected dimensions. V1 shortened the arm reach excessively; V2 uses measured athlete shoulder positions and adjusted endpoints. Blender evaluated weighted foot vertices have minimum Z 0.000579m against the intended floor Z=0, so the floorless preview does not indicate elevated feet. Native playback and production route remain pending.

## DY row draft
Manufacturer https://www.lifefitness.com/ja-jp/catalog/strength-training/plate-loaded/plate-loaded-iso-lateral-d-y-row and official embedded demonstration https://player.vimeo.com/video/1050766924 . Inspected 9s equipment, 19s rear pulled posture, 24s grip/chest contact. Underhand grip, overhead pivot, independent rigid levers and chest support differ from low row. Artist-selected geometry, not exact CAD. V1 pulled too high; revised handle height/axis and downward elbow pole. IK rejects unreachable wrists rather than stretching limbs. Rear oblique camera revised after the side pillar obscured the arm. Static draft only until native review.

## High row draft
Manufacturer https://www.lifefitness.com/ja-jp/catalog/strength-training/plate-loaded/plate-loaded-iso-lateral-high-row and embedded official https://player.vimeo.com/video/1064752886 . Observed equipment at4/9s, unilateral motion at19s, overhand grip closeup at24s: chest and thigh supports, overhead start, separate pivoting arms, rear loading horns. The modeled linkage is original simplified equipment, not exact manufacturer CAD. Increased the initial hand height to reduce excessive elbow flexion, then corrected the pivot circle so the terminal handle remains ahead of the shoulder instead of behind it. Native testing pending.

## Back extension draft
Sources: https://shop.lifefitness.com/products/hammer-strength-back-extension and official https://player.vimeo.com/video/1161896691 (19/24s pad adjustment,34s lower-body support,39s plate held at chest during hinge); https://www.jssm.org/volume20/iss2/cap/jssm-20-181.pdf methods pp2-3 describe neutral-back hip flexion and chest-held plates. PDF text was read; its figure did not render and was not visually reviewed. Existing athlete legs retain fixed world transforms while the torso pivots at the hip. 45-degree split thigh pads, tilted footplate and calf restraint; authored dimensions, not CAD. Chose60-degree demonstration flexion to avoid excessive folding. Chest-hand pose and optional plate path supported; optional weighted animation not yet device-tested. All5 sampled frame closest-vertex/handle-axis estimates exceed.216m; this is an approximate clearance check, not full mesh collision proof. Native playback pending.
