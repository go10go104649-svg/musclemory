# 体重記録の検証（2026-09-14）

- iOS 26.5 / 専用 MUSCLEMORY QA（iPhone 17）、Android 16 / 専用 musclemory_qa（Pixel 7）。実機は未確認。
- 通常のSharedPreferencesプラグインを使い、82.5kgを画面から入力・保存。81.9kgへ編集し、アプリのウィジェットを再作成して保存領域を再読み込み。
- グラフ・選択値・編集済み記録を実スクリーンショットで確認。履歴保存文字列が変更されないことも検査。
- OSプロセスの終了／再起動はこの統合テストには含まれない。
- 静的解析成功、全82テスト成功、iOSとAndroid arm64のdebugビルド成功。統合テストは両OSで成功。
- Androidの初回接続はANDROID_HOME未指定で失敗。指定後の再実行で成功。
- 不正な体重入力（NaN、Infinity、オーバーフロー、ゼロ、負数）と、不正な保存データに正常記録が混在した場合の回帰テストを追加。
- iOS画像: body_weight_saved.png / body_weight_edited_reloaded.png。
- Android画像: ../body_weight_android_2026-09-14/。
- ユーザー用iPhoneシミュレーターにはインストール・データ更新・テストを実施していない。専用端末のアプリもアンインストールしていない。

最終追加確認：通常エントリーポイントでiOS／Androidを再ビルドし、専用端末へ保持インストールして起動。両OSのネイティブ保存領域に編集済み81.9kgが保持されていることを確認。通常版のホーム画面をnormal_app_restarted.pngに保存。通常版でグラフまで再操作する確認は行っていない。

通常版のAndroid最終スクリーンショットにSystem UIのANRダイアログを確認。イベントログではテスト開始前の15:43にcom.android.systemuiとcom.android.phoneの起動失敗が発生していた。アプリの正常起動確認と混同せず、専用AVDをデータ保持で再起動して追加確認する。

Android追加確認結果：専用AVDを-gpu hostで再起動し、起動完了後に通常版を起動。新しい起動のイベントログにANR／クラッシュなし。警告のない通常ホーム表示と、81.9kgの永続データ保持を確認。これは今回の観測範囲であり、実機の性能保証ではない。初回警告画像はAndroid側normal_app_system_ui_warning.pngへ保全。
