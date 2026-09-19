# 2026-09-17 実機フィードバック対応

今回の範囲はチェック時の表示位置、インターバル操作/最終セット/通知、インクラインフライマシンのみ。前回の未完了3D制作などは再開していない。

## 原因と修正
- スクロール: ListView先頭付近へ休憩欄を条件付き挿入/削除していたため、下のセット行の座標が変化していた。設定が有効な間は同じ領域を維持し、表示/操作状態だけを更新。後からscrollToで戻す処理は追加していない。
- ストップ: 以前は残秒0へのリセットだった。期限から残秒を算出して保持し、periodic timerと予約通知を解除。再開は保持した秒数から新期限を1つだけ作る。
- 最終セット: 全チェックで無条件に自動開始していた。現在のsets.lengthの末尾チェック/一括完了では旧インターバルを終了し予約解除。手動開始は維持。
- 終了音: 従来2.4秒音源、Android foregroundは音声フォーカス要求なし。2.8秒の6パルス/中高域の倍音付き音源に変更。AndroidはMAY_DUCKを取得、完了/キャンセル/失敗で解放。音量や他アプリの再生操作は変更しない。
- iOS: ambientの独自再生からforegroundの即時ローカル通知音に変更。期限通知のforeground表示は抑制し、Dartが取消後に1回だけOS通知を出す。サイレント/集中モード/通知設定/音量の判断をOSに委ねる。保存済み音源も最新版へ原子的に更新。バックグラウンドは従来の予約通知。
- 通知タップ: Android NotificationにContentIntentがなく、タップ先が存在しなかった。MainActivityのimmutable PendingIntent追加。iOSはUNUserNotificationCenter delegateと自分の通知応答の完了処理を明示。
- 新種目: 共通catalogへincline_fly_machineを追加。日本語インクラインフライマシン、英語Incline Fly Machine、胸、weightReps。専用3Dはplannedで非公開。既存アプリは日本語固定で言語切替なし。英語名をマスタと検索へ追加し、pickerは英語localeで英語名を表示できる構造にした。アプリ全体の英語化はしていない。

## 確認の限界
- ユーザー提供動画そのものはこのターンのファイルとしては受領していない。コードと独自の実画面再現テストで確認。
- 音楽アプリ各種/イヤホン/実機での聞こえ方は、確認していない限り成功扱いにしない。OSによるduckingは相手アプリやOS設定に依存する。
- Android/iOSの実施結果は検証完了後に追記する。

## 技術資料
- https://developer.android.com/media/optimize/audio-focus
- https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/duckothers
