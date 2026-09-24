# Android Live Update / 通知セット完了（2026-09-24）

## 実装

- API 36で`POST_PROMOTED_NOTIFICATIONS`と正式なpromotion extra `android.requestPromotedOngoing`を使用。現在のSDKにBuilderの便宜メソッドがないため、公開extraで要求する。`canPostPromotedNotifications()`を診断に記録する。
- 標準BigTextStyle、ongoing、タイトル、LOWチャンネル、Chronometer countdown。RemoteViews・毎秒通知更新・新規通知パッケージなし。昇格の可否はOS/OEM設定に従い、不可でも通常の拡張通知が残る。
- セットに紐づく休憩は、終了時に同じ7340通知を「休憩終了／セット完了」へ更新する。終了後はChronometerと昇格要求を外す。前面は既存MediaPlayer、背景は既存音付きチャンネルを使う。対象セットのない手動タイマーは従来の終了通知を維持。
- 「セット完了」は非公開Receiver宛てのimmutable Broadcast PendingIntent。ActivityやFlutterエンジンを起動しない。

## 永続化と競合対策

既存の`active_workout_draft` JSONを保持する。Androidの読み書きだけMethodChannel経由の同一ネイティブ書き込み窓口へ集約し、SharedPreferencesの既存`flutter.active_workout_draft`へcommitする。iOSの保存経路とJSONフィールドは変更しない。

Android draftにはsessionId、種目インスタンスID、setId、versionを追加する。旧draftは従来どおり読め、次の通常保存でIDを持つ。履歴の一括変換はしない。

通知はworkout/exercise/直前set/対象set/timerId/draftVersionを固定する。存在・隣接関係・直前完了・対象未完了・期限終了・現在の通知世代を実行直前に照合する。古い通知、別セット、再押下、編集後、削除後は拒否する。

完了フラグとAction消費を同一commitで保存してから次の休憩を予約する。元の重量・回数・その他JSON値は維持。最終セットでは予約しない。AndroidのUI書き込みが遅れて届いても、完了journal/revisionで確定済みチェックを取り消さない。既に新revisionを読んだユーザーの明示的な完了解除は可能。

復帰時はnative draftの完了情報をIDでUIへ反映する。トレーニング全体の完了ではActionを止めて最新の確定情報を取り込んでから履歴を保存し、終了直前の通知操作も落とさない。

## 制約

Galaxy S25実機は未接続。One UIでの実際の昇格、表示サイズ、PIN付きロック画面での操作、音楽併用、省電力モードは実機確認が必要。既存のinexact AlarmManager方式は維持しており、深いDozeの遅延やユーザーによるOSの「強制停止」を回避する変更ではない。

公式仕様: https://developer.android.com/develop/ui/views/notifications/live-update

## 検証結果

- 関連Flutterテスト106件＋完了保存/画面12件＋セット位置/休憩1件、計119件成功。
- Android API 36エミュレーター：既存の終了音・停止・延長・最終セット・OS抑制の5テスト成功。
- 新規`rest_set_action_test.dart`の4テスト成功。対象固定、連打、古い通知、編集/削除後、値保持、次の休憩、最終セット、遅れたUI保存との競合、通常完了保存への反映を確認。
- 実際のBroadcast PendingIntentをロック状態（Keyguard=true）で送信し、Activityが前面にならず対象セットだけ保存されたことを確認。手指によるGalaxy実機操作ではない。
- 初回ロックテストはエミュレーターのロック無効設定で失敗。設定を直し、同じテストを再実行して成功。
- ロック画面の「休憩終了」通知を画像確認。標準通知では折りたたみ状態になるため、Actionは展開時に表示される。Live Update昇格を実機確認したとは扱わない。
- 背景プロセスを終了した後、永続化ファイルを読み、完了チェック・80.5kg・未完了の次セットが維持されていることを確認。OS強制停止中に通知Actionを動かす保証はしない。
- `flutter analyze --no-pub`：No issues found。`git diff --check`：成功。
- iOSネイティブファイルは変更なし。今回iOS実機テストは行わない。
- commit/pushなし。一時ログ・スクリーンショットは`build/`内のみ。

## 変更ファイル

- `lib/main.dart`
- `lib/services/android_workout_draft.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/MainActivity.kt`
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/RestTimerState.kt`
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/RestTimerReceiver.kt`
- `android/app/src/main/kotlin/com/musclememory/muscle_memory/WorkoutNotificationState.kt`
- `integration_test/rest_set_action_test.dart`
- 本QA記録

最終Android debug APKビルドも成功。Galaxyへのインストールは行っていない。
