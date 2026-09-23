# トレーニング完了時の保存確定 — 2026-09-23

## 修正

原因はWorkoutPageが完了ダイアログを表示した後、ダイアログ内の操作で
Navigatorから記録を返し、呼び出し元がそこで履歴を保存する順序だったこと。

- ホーム、新規/再開、履歴からのリピート、履歴修正の全本番導線から保存コールバックを渡す。
- 完了押下 → ローカル履歴保存成功 → 入力途中データ削除完了 → 完了ダイアログ。
- 履歴は保存成功後に画面へ反映する。自己ベスト表示は既存の履歴計算を維持。
- ダイアログのホーム/共有操作は遷移のみ。遷移後の二重保存を廃止。
- 処理中の連打・編集・離脱を防止。保存失敗時はダイアログを出さず再試行可能。
- 履歴保存後のdraft削除を再試行しても、同じ記録を再度挿入しない。
- クラウド同期はローカル保存後に非同期で開始する。クラウド完了を待ってダイアログを出すことはしない。
- データ形式・種目・3D・ネイティブ通知処理は変更なし。

## 検証結果

- flutter analyze --no-pub: 問題なし
- flutter test --no-pub test/workout_completion_test.dart test/workout_draft_store_test.dart test/workout_gym_test.dart: 12件成功
- test/widget_test.dartの関連回帰: 5件成功
  - completed workout appears in history
  - editing history does not remove an active workout draft
  - workout draft is saved and leaving asks for confirmation
  - repeating from history protects the active draft
  - SNS preview contains exercise data without workout totals
- git diff --check: 成功

## OSプロセス終了・再起動

integration_test/workout_completion_restart_test.dartをテスト用端末だけで実行。
SharedPreferencesはmockせず、ネイティブの実ストレージを使用する。

1. QA用の入力途中記録を作成。
2. 完了を押し、ダイアログ表示、履歴1件、draft削除を確認。
3. ダイアログを閉じずにプロセスを終了。
4. 同じアプリを再起動し、実ストレージから履歴1件を復元。
5. 入力途中カードなし、履歴の重量65kg/8回、日時、ジム、メモの保持を検証。

- Android: MUSCLEMORY_Batch_QA / emulator-5554、am force-stop後の再起動に成功。
- iOS: MUSCLEMORY QA / 0B986FD3-05C1-4ECF-8CA8-035433154498、simctl terminate後の再起動に成功。
- ビルド・再起動検証とも両OS成功。物理端末でのタスク終了操作は未実施。
- 第1起動のdriver接続切断は意図したプロセス終了によるもの。第2起動はテスト成功。
- 証跡: build/completion_android_before_kill.log / completion_android_after_restart.log、
  build/completion_ios_before_kill.log / completion_ios_after_restart.log

再実行時は専用QA端末で本統合テストを起動し、
COMPLETION_READY_FOR_PROCESS_TERMINATION表示後にプロセスを終了して再起動する。
2回目にCOMPLETION_RESTART_VERIFIEDが出れば成功。
QA用履歴を上書きするため、ユーザー実機では実行しない。
