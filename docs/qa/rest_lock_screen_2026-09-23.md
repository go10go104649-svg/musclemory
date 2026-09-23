# 休憩タイマー OS表示 QA — 2026-09-23

## 実装

終了予定時刻（epoch milliseconds）をFlutterとネイティブの共通基準とする。
開始・延長・停止・終了でのみOS表示を更新し、毎秒の通知再生成はしない。
既存の完了通知、通知音、最終セット判定、保存形式、3Dには変更を広げない。

- Android: 既存RestTimerState/Receiverへ継続通知を接続。OS Chronometerによるカウントダウン、停止/+30秒アクション、ローカル永続化、アプリ復帰時の同期。通常のongoing通知を使用し、Live Update昇格やForeground Serviceは追加しない。
- iOS: RestTimerWidget拡張、ActivityKit属性、Live Activityのライフサイクル管理。ロック画面とDynamic Islandのcompact/minimal/expanded表示。通知許可ダイアログから復帰した場合も表示を開始する。
- iOSのロック画面操作ボタンは未追加。アプリ内の停止・延長から表示を同期する。
- 前面復帰で保存した終了予定時刻を照合し、期限切れのActivityを終了する。新規開始では既存Activityを終了して1件にする。

## 制約（未達条件）

iOSでアプリがサスペンド・強制終了されている場合、ローカルコードだけでは
「0秒になった瞬間にLive Activityを完全除去する」ことは保証できない。
staleDateはActivityの終了予約ではない。OSカウントダウンは0で止まり、
stale状態では「休憩終了 / 00:00」を表示し、アプリ実行・復帰時に終了する。
厳密なバックグラウンド自動除去にはAPNsによるActivity終了等の追加設計が必要。
今回APNsサーバーや認証・クラウド変更は行っていない。

Androidは既存のsetAndAllowWhileIdleを維持しているため、Doze等で終了通知が
遅延する可能性は残る。継続通知はtimeoutAfterも指定する。
OSの通知許可、チャンネル設定、ロック画面のプライバシー設定、DNDに従う。
iOSのAlways On表示はOS側の更新頻度・表示制限に従う。

## 検証環境・証跡

ユーザー実機は操作していない。
- Android: MUSCLEMORY_Batch_QA / emulator-5554
- iOS: MUSCLEMORY QA / 0B986FD3-05C1-4ECF-8CA8-035433154498 / iOS 26.5
- ログ: build/rest_live_*log
- Android通知領域: build/rest_live_qa/android/notifications.png
- iOSロック画面: build/rest_live_qa/ios/lock_screen_allowed.png

Android通知領域で種目名とカウントダウンを目視確認。
iOSロック画面でLive Activityとカウントダウンを目視確認。
Androidのロック画面、Dynamic Islandの展開表示は未確認。
物理端末の通知音・音楽併用・DND・電池節約・強制終了・再起動は未確認。

## テスト

- flutter analyze --no-pub — 成功（問題なし）
- flutter test --no-pub test/feedback_20260917_test.dart test/workout_layout_test.dart test/workout_gym_test.dart
  - 11件成功（開始、停止、再開、最終セット、既存レイアウト/ジム回帰）
- integration_test/rest_lock_screen_test.dart を両OSでビルド・実行 — 各2件成功
  - 表示生成、延長、停止、再開、最終セット、復帰時同期
  - 期限切れ時の表示終了、キャンセルした期限後に通知が残らないこと
  - Android通知アクションはdebug限定入口から実際のReceiver用処理へ渡す
  - OS許可はQA端末で事前に許可。実ネットワーク不要
- --dart-define=REST_DISPLAY_VISUAL_QA=true で45秒の目視確認用待機を有効にできる。
  通常のテストでは待機しない。
- スクリーンショット取得用uiautomatorはFlutter semanticsを有効化するため、
  自動テストの完了判定とは分離する。

## 変更ファイル

- lib/main.dart
- android/app/src/main/kotlin/com/musclememory/muscle_memory/MainActivity.kt
- android/app/src/main/kotlin/com/musclememory/muscle_memory/RestTimerState.kt
- ios/Runner/AppDelegate.swift
- ios/Runner/SceneDelegate.swift
- ios/Runner/Info.plist
- ios/Runner/RestTimerAttributes.swift
- ios/Runner/RestTimerDisplay.swift
- ios/RestTimerWidget/Info.plist
- ios/RestTimerWidget/RestTimerWidget.swift
- ios/Runner.xcodeproj/project.pbxproj
- integration_test/rest_lock_screen_test.dart
- docs/qa/rest_lock_screen_2026-09-23.md

git diff --check: 成功。commit / pushなし。
