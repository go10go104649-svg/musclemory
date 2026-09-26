# Android休憩通知UI・セット進行（2026-09-24 追加修正）

> 本書は通知UIと自動操作の検証記録です。現行の確定仕様では、Galaxy実機で停止ボタンを押すとポップアップが消え、画面を開かないと続行できない不具合が残っているため、ロック画面からの停止・続行・次タイマー遷移を実装済みとは扱いません。詳細は [現行確定仕様](../current_spec.md) を参照してください。

## 今回の変更

前回の `android_live_rest_set_2026-09-24.md` は当時の検証記録。本修正では終了前の操作・次種目への進行・大きな時計を優先した。

- 標準Chronometer / BigTextでは時計のサイズや折りたたみ時の操作を制御できないため、DecoratedCustomViewStyle + RemoteViewsを採用。
- 折りたたみ時は30spの時計と「セット完了」、展開時は40spの時計・種目名・次セット番号・停止/+30秒/セット完了。種目名は長い場合省略し、セット番号の領域を分離する。
- OS側Chronometerが終了日時を基準に更新する。毎秒通知再発行なし。終了後は停止した時計ではなく明示的な00:00へ置換。
- カスタムRemoteViewsはpromoted Live Updateの要件に適合しないため、昇格要求は出さない。今回は大きな時計と継続操作を優先し通常ongoing通知を利用する。権限やOS設定を勝手に変更しない。
- 通知内「セット完了」は、実行中も終了後も同じBroadcast PendingIntentで処理する。古いtimerId/対象ID/draftVersionは拒否する。置換通知が高速に描画された場合の連打も1秒の永続化済みガードで抑止。
- 次セット探索はネイティブの1処理へ集約。現在種目の未完了セット→後続種目→残っている前方種目の順。Androidのアプリ内チェック・すべて完了・通知完了・手動タイマー開始がこの判定を共有する。
- 全ワークアウトの未完了セットがなくなった場合だけ自動休憩を終了する。iOSの既存判定は変更しない。
- 重量/回数/メモの編集後も同じ未完了セットへの操作を維持する。対象セットの削除・完了・先行チェックの取消しで次セットが変わった場合は無効化する。
- 既存のdraft完了journal・即時commit・復帰時同期を使用する。通知からのセット操作では終了音を鳴らさず、新しい期限でのみ既存の終了音処理が走る。
- 停止/+30秒のPendingIntentも世代固有のURIで固定し、古いボタンが新しいタイマーを操作しないようにする。

## 検証と実機の区別

- Galaxy SM-S9310 / Android API 36をUSB接続。通常アプリとは異なる `.restqa` 検証アプリを一時ビルドして使用し、通常アプリの記録には触れていない。検証用のapplicationIdSuffixとアプリ名変更はソースから戻している。
- Galaxyでカウントダウン中・終了後のロック画面/通知の画像を確認。折りたたみ状態でも時計と「セット完了」が表示された。
- Galaxy上の実PendingIntentをロック状態で送信し、Activityを前面にせずチェック保存と次休憩が進むことを確認。ただし、実画面の停止ボタンを手指で押した場合はポップアップが消えて続行できないため、PendingIntentの自動送信成功だけで完了とは判定しない。
- Galaxyの+30秒/停止の画面操作確認は途中で接続が切れ、ユーザー指示によりそれ以上の実機確認は終了。エミュレーターで補完する。
- サイレント時の音抑制をログで確認。その後ユーザーがサウンドモードへ変更。背景で通知チャンネルによる出力が行われたが、音を人が聞いて確認したとは扱わない。
- 通常アプリへの更新版インストールは行っていない。検証アプリは切断時点で端末に残っている。

## OS制約

既存inexact AlarmManagerを維持するため、深いDozeやプロセス停止時の終了通知に遅延する可能性がある。ロック画面の表示可否/折りたたみ、通知音、DND、クールダウンはOS設定に従う。強制停止を回避する仕組みではない。

参考：
- https://developer.android.com/develop/ui/views/notifications/custom-notification
- https://developer.android.com/reference/android/app/Notification.DecoratedCustomViewStyle
- https://developer.android.com/develop/ui/views/notifications/live-update

## 最終検証結果

- Flutter関連118テストを実行。最終一括実行は117成功、完了保存の経過時間テスト1件のみ120秒に対し121秒となった。該当ファイル5件を単独再実行し全件成功。初回一括実行は118件すべて成功しており、時間境界の不安定性として記録する。テストを通すための保存ロジック変更はしていない。
- Android API 36：終了音・停止・延長・背景通知・最終セットの既存5件とセット通知7件の計12件成功。最終の通常編集/削除/チェック取消しの修正後もセット通知7件を再実行し成功。
- `flutter analyze --no-pub`：No issues found。
- `git diff --check`：成功。
- Android debugビルド：成功。
- エミュレーターの実通知を展開し、セット完了ボタンの座標タップ→保存済みset flags `[true,true,false]`→次休憩300秒表示を確認。+30秒ボタンをタップし永続化済みdeadlineが正確に30000ms増加、停止ボタンをタップしdeadline消去とremainingSeconds保持を確認。
- 動作中の時計に対するホスト側UI自動探索が不安定だったため、画面を確認した上で実ボタンの座標タップと保存状態の照合に切り替えた。Flutterだけの疑似操作ではない。
- 最終の通知完了後に背景プロセスを終了し、draftの完了状態と80.5kg・10回が永続化されていることを再確認。
- Galaxyの実機確認範囲は前節のとおり。接続切断後の追加修正（連打ガード、短縮した次セット表記、通常編集時の操作保持）はエミュレーターで検証した。通常アプリを最新版へ更新済みとは扱わない。
- commit/pushなし。画面画像・ログ・一時QAビルドはbuild配下（Git対象外）。

実行範囲：

```sh
flutter test --no-pub test/workout_draft_store_test.dart test/workout_completion_test.dart test/workout_detail_ui_test.dart test/widget_test.dart test/home_rest_cloud_revision_test.dart
flutter test --no-pub test/workout_completion_test.dart
flutter analyze --no-pub
```

Androidの実行対象：`rest_set_action_test.dart`、`rest_notification_native_test.dart`、`rest_lock_screen_test.dart`、`rest_sound_lifecycle_test.dart`。既存ドライバーとホストからのロック/復帰操作を使用。`REST_BOUNDARY_HOST_QA=true` のケースはホスト操作を伴う。

## 変更ファイル

- lib/main.dart
- lib/services/android_workout_draft.dart
- android/app/src/main/kotlin/com/musclememory/muscle_memory/MainActivity.kt
- android/app/src/main/kotlin/com/musclememory/muscle_memory/RestTimerState.kt
- android/app/src/main/kotlin/com/musclememory/muscle_memory/WorkoutNotificationState.kt
- android/app/src/main/res/layout/rest_notification_compact.xml
- android/app/src/main/res/layout/rest_notification_expanded.xml
- integration_test/rest_set_action_test.dart
- 本QA記録
