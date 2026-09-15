# ホーム・体重・3D・休憩・クラウド整理（2026-09-15）

## 実装

- ホーム末尾のpaddingを120から32へ詰めた。
- ホームの「今週の記録」「前回のトレーニング」をUIから削除。履歴・集計データは削除していない。
- 体重グラフ下の常設記録行を最新1件へ制限。補足文を削除。グラフ選択中の最新値も常設行と二重表示しない。過去の点の選択・編集、全期間データの保存は維持。
- Androidの3D描画面再生成で汎用カメラへ戻る経路を修正。人体用の固定投影・視点を再適用し、描画停止・再開を揃えた。表示領域の0/非有限サイズを拒否し、生成中に破棄されたTextureの解放を追加。モデルやモデルscaleは変更していない。
- 休憩終了の既定音を2.4秒・6音のWAVへ変更。iOS/Androidで同じ音を使用。ネイティブ再生でカウントダウン表示の破棄に依存させない。
- ストップボタンでタイマー・通知予約・再生中の音・振動を取り消す。Androidはキャンセル後に遅れて届くBroadcastも保存した期限で無効化。iOSの世代番号による競合防止は維持。
- Supabaseの独立したマイページ項目を削除し、バックアップ・データ管理内のクラウドエリアへ統合。ファイル書き出し・ファイル復元は無料のまま。クラウドはUIとサービス層の両方で制限。
- 加入管理は未導入との回答に従い、クラウドは全ユーザーでロック。加入確認なしで解除する設定や、ダミー課金判定は導入していない。

## 原因

### 3D縮小

Androidの `createSwapChain` はSurfaceの再生成時にも呼ばれるが、人体用のorthographic（平行投影）カメラを汎用のperspective（透視投影）カメラと遠いorbit距離へ上書きしていた。viewport更新や方向切替のタイミングでは人体用カメラに戻るため、常時ではなく断続的に発生する構造だった。

コード確認では、停止状態の単発描画でFilamentの `beginFrame` がSurface準備中に描画を受け付けなかった場合、そのまま再描画されない経路も確認。モデル読込完了・画面復帰・色変更時は、描画が受け付けられるまで再試行し、少数の成功フレームを描いた後に停止する方式へ変更。

停止中のモデルは描画予約がないため、Surfaceを失った後も描画中フラグだけが残ると再描画されない経路があった。Surface破棄時に描画ループを停止し、作成後に再予約するよう修正。

BoundingBoxは読取のみで、期間・色・方向の切替によるモデルscaleの累積変更はなかった。iOSは独立したSceneKitの固定カメラを使用しており、同じAndroidの上書き経路はない。iOSのカメラ値は変更せず反復表示で確認した。「3方向表示」は元々、前面・側面・背面の切替を示すラベルで、別の同時3画面モードは実装されていない。

### 終了音

AndroidはToneGeneratorの再生時間が180ms、解放が250msに明示設定されていた。iOSは1057のシステム音を1回だけ再生していた。カウントダウンWidgetの破棄が主因ではなかった。今回は同一の2.4秒音源を画面表示中とバックグラウンド通知に使用する。

## 変更ファイル

- `lib/main.dart`: ホーム・体重・ストップ・通知連携・クラウド画面と呼出側の制限。
- `lib/services/supabase_sync_service.dart`: 全クラウド操作のPremiumゲート（現在は未導入のため閉じる）。
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/MainActivity.kt`
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/RestTimerFeedback.kt`（追加）
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/RestTimerReceiver.kt`
- `ios/Runner/AppDelegate.swift`: カスタム通知音、継続再生・取消、フォアグラウンド二重音防止。
- `assets/sounds/rest_complete.wav`、`android/app/src/main/res/raw/rest_complete.wav`（追加）、`pubspec.yaml`
- `packages/interactive_3d/lib/src/widget.dart`
- `packages/interactive_3d/android/src/main/kotlin/com/example/interactive_3d/renderer/FilamentRenderer.kt`
- `packages/interactive_3d/android/src/main/kotlin/com/example/interactive_3d/Interactive3dTextureEntry.kt`
- `packages/interactive_3d/android/src/main/kotlin/com/example/interactive_3d/Interactive3dPlugin.kt`: debugビルド限定のカメラ状態確認・Surface再生成テスト窓口。
- `test/widget_test.dart`、`test/home_rest_cloud_revision_test.dart`（追加）
- `integration_test/home_rest_cloud_revision_test.dart`、`integration_test/rest_sound_lifecycle_test.dart`、`integration_test/body_resume_test.dart`（追加）
- `ios/RunnerTests/RunnerTests.swift`: 通知音の長さ検証追加。

## 検証結果

- Flutterテスト94件成功。無料時の履歴削除・復元、保存・バックアップ形式、3D素材、タイマーを含む。
- Android API 36 ARM64 / 専用MUSCLEMORY_Batch_QA、iOS 26.5 / 専用MUSCLEMORY QAでホーム・体重編集・クラウドロック・休憩停止の実画面テスト成功。
- 両OSで、4期間×3方向×3回の切替と3回のタブ離脱・再表示を実施。
- Androidで36回のSurface再生成前後の投影行列が一致し、平行投影のまま維持されることを検証。
- Androidの実際のセット完了から、休憩表示が消えた後にも音源が継続再生され、所定時間後に停止することを検証。
- Androidのバックグラウンド通知の配信、カスタム音URI、振動パターンをOSの通知状態から確認。ストップ後は通知なし。
- 音源: 2.4秒、mono PCM 22,050Hz、105,884 bytes。Android rawとFlutter/iOS用ファイルは同一。

## 未導入・確認限界

- Premium加入管理・ストア課金・検証済み加入情報の取得は未導入。Premium表示の解除側はUIテスト用の入力で確認しただけで、実加入による解除やSupabaseへの実通信は未確認。
- 課金導入時は `canUseCloud` に信頼できる加入判定を接続し、サーバー側の認可も合わせて整備する必要がある。既存SupabaseのRLS/認証・本番データは変更していない。
- 実Android端末・実iPhoneでの聞こえ方、音量、振動の体感は未確認。OSの通知無効・消音・ユーザー指定チャンネル音を優先する。
- 今回はファイルバックアップのネイティブ共有/ファイル選択UIを再操作していない。既存処理を維持し、無料で有効であることとデータ形式の回帰テストを確認。
- GitHubへのcommit/pushは行っていない。

### 追加のシミュレーター検証

- 両OSの `rest_sound_lifecycle_test.dart` 成功。実際のセット完了→0秒→休憩表示消去後もネイティブプレーヤーが再生中で、約1秒後も継続し、音源終了後に停止することを確認。キャンセル呼出で再生中の音が停止することも確認。
- 両OSの実際のバックグラウンド移行中にローカル通知を受信したことをOSのdelivered一覧で検証。キャンセルした通知は予定時刻を過ぎてもdeliveredに残らない。
- iOSの `body_resume_test.dart` 成功。ホームの12件保持・最新1行の編集、OSホーム移動→アプリ復帰後の3D表示を実画面で確認。Androidは投影行列の確認だけでは空の描画を検出できなかったため、画素ベースの人体サイズ検証を追加して再検証。
- Androidのデバッグ起動時、デバッガー接続待ちに伴うFocusEventタイムアウトが1回発生。3D読み込みより前の時刻のANRで、デバッグの起動一時停止を外した再実行では完走した。検証用・配布用Flutterビルド同時実行による生成プラグイン登録の競合も発生し、その後はビルドを直列化。
- 新たなDart解析警告はなし。既存のAndroid環境光ロード警告・SDK XML世代警告は今回の修正対象外。

音源は今回のために自作したPCM波形で、外部の音源素材は使用していない。

- iOSネイティブXCTest 5件成功（通知予約と取消の競合4件、同梱音源が2.4秒であること1件）。

- Androidの自動撮影は、FlutterのSurface変換による古いフレームの取得と、非同期モデル読込完了前の撮影を切り分けた。通常アプリのOSスクリーンショットでは背景復帰前後とも正常サイズを確認。追加の画素検証ではSurfaceを変換せずPixelCopyを使用し、モデル読込・Surface準備を画素で待機する。

- Androidの追加画素検証も成功。バックグラウンド移行前後で、人体の高さは描画領域の86.3%、明るい人体画素の占有率は約11.0%で一致。両方とも待機検証の1回目で取得。これは静止画のサイズ検証で、描画性能値ではない。

## 最終表示の証跡

- Android: [ホーム・最新体重1件](android/home_final_single_weight.png)、[背景復帰前](android/body_before_background.png)、[背景復帰後](android/body_after_background.png)、[通常アプリの背景復帰後](android/normal_app_body_resumed.png)
- iOS: [ホーム](ios/home_final_single_weight.png)、[背景復帰後](ios/body_after_background.png)

- 最終 `flutter analyze`: No issues found。最終 `flutter test`: 94件すべて成功（ホーム余白と撮影テスト修正後）。

## 最終ビルド

- Android release: 成功。`MUSCLEMORY-beta4-1.0.0-4.apk`（1.0.0 / build 4）。APK v2署名検証成功、16KB zipalign検証成功。90,813,763 bytes。
- SHA-256: `14c3c73e987d56d4d3b7aadee2db073c4ed59a4af95f064e87d64cc916081cfd`
- iOS simulator: `lib/main.dart`の最終ビルド成功。TestFlight/署名済みIPAの配布は今回実施していない。

- 配布APKは新規の専用 `MUSCLEMORY_Release_QA`（Android API36）にインストールし、通常ホーム起動を確認。既存アプリの削除は行わず、専用の新規エミュレーターを使用。
- iOS最終アプリを専用 `MUSCLEMORY QA` に再インストールし、通常ホーム起動を確認。

- Android配布版でも部位タブを操作し、3D人体が正常サイズで表示されることを確認（`android/release_body.png`）。
