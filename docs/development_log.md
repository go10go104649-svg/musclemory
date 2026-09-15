# 継続開発記録

## 2026-09-14：トレーニング時間・下書きの信頼性

過去に明示されたタイマー停止仕様を最優先で再確認。

実装済み：
- 最後のセットを削除した場合にも時間を確定して停止。
- 停止済み下書きの正確な経過時間を復元し、復元中のメモ変更による不完全な再保存を防止。
- 下書き保存を直列化し、全削除・完了後の遅延書き込みによる復活を防止。
- 中断時は最後の保存完了を待って戻る。ユーザーが下書きを明示的に再開する既存動作は維持し、中断期間を時間に加算しない。
- 終了済み履歴の時間、既存の保存キー・JSON形式は維持。

関連する休憩通知の修正：
- iOSの通知許可・追加処理が遅れても、キャンセル済みの通知を再作成しない。
- 新しい休憩の予約を、古い許可コールバックで上書きしない。
- 通知許可待ちも元の終了時刻に含め、期限が過ぎた予約は行わない。
- 残り秒数を切り上げ、最後の1秒を早く終了しない。
- Androidのキャンセルは予約だけでなく表示済み通知も取り消す。

確認済み：
- Flutter静的解析：指摘なし。全78テスト成功。
- iOSシミュレーター向け・Android arm64 APK：ビルド成功。
- iOSネイティブ競合テスト4件：成功（許可待ちキャンセル、古い許可、追加待ちキャンセル、絶対終了時刻）。
- iPhone 17 / iOS 26.5：開始して時間が進む、完了して停止、停止した秒数が履歴に保存、中断期間を除外して明示再開、最後のセット削除で停止、全削除後に下書きが復活しない、を実画面テストで確認。
- 当初、SharedPreferencesのモックだけで既存保存データを保護できると誤認した。下記インシデントを参照。

検証継続中：
- iOSの休憩終了画面は許可後に撮り直し、実表示を確認済み。
- iOSバックグラウンド通知：予約1件・許可状態を検査後、ホーム画面上の休憩終了通知を実際に確認済み。
- Android 16 / Pixel 7：同じ3件の実画面テストが成功。タイマー停止と休憩終了のスクリーンショットを確認済み。
- 通常エントリーポイントでビルド成功。通常版をインストールし、バックアップ復元後のホーム表示を確認済み。

次の既存要件の確認候補：SNS共有（写真選択・プレビュー・共有シート）、体重入力・編集・グラフ、種目タイプごとの入力の端末上での回帰確認。新規3D種目の展開はユーザーの品質確認条件を守る。

GitHubへの送信はこの開発ブロックでは未承認のため実行しない。

## 関連する起動時の描画負荷

Android実行ログで、未表示の部位タブにもFilamentの3Dモデルが初期化されていた。
IndexedStackのタブ状態は保持しつつ、非表示時はネイティブ3Dビューを破棄するよう修正。
再表示時は選択していた前面／側面／背面を保持する。ウィジェット回帰テストを追加し、全79テストが成功。
Androidの更新後の実画面テストも成功。実機性能の数値やANRの全原因解消は主張しない。

検証ツール上の問題：AndroidのDDS接続が失敗する場合は `--no-dds --use-existing-app` で実行中のVMに接続して検証。画面取得はAndroidのSurface変換を各テストにつき1回だけ行う。

iOSの `debugStatus` はシミュレーター専用の予約状態検査。実機向けビルドには含まれない。

検証の注意：`flutter drive` がiOSビルド失敗後に旧版へ接続したケースがあった。新設した `tool/verify_workout_lifecycle.sh` は明示的なbuild成功後、`--use-application-binary` でその成果物に限定して検証する。通知状態検査の初回ビルド失敗（UNNotificationTriggerの型）を修正して再確認中。失敗した試行を成功扱いにしない。

## 保存データ保護のインシデント（開発を中断して復旧対応）

Flutter SDKのdrive終了処理がアプリをアンインストールすることを確認。
ユーザー用iPhone 17シミュレーターで実行したため、既存アプリとその保存領域が削除された。
実機には操作していない。検証用SharedPreferencesを使っていたが、OSの保存領域削除を防げなかった。

Filesの共有領域に9月12日のエクスポートを発見し、リポジトリ外へ保全。
履歴6件・マイメニュー1件を含む。現在のアプリで検証して復旧する。
9月12日以降の未バックアップデータの有無・復旧は未確認。Time Machineのローカルスナップショット、他のSimulator保存領域には復元元が見つからなかった。

安全策：統合テストは専用端末名のガードと `--keep-app-running` を追加。
通常のユーザー端末でテストを続けない。元データの復旧状況が確認できるまでは新しい機能追加を停止。

復旧結果：9月12日のバックアップ全6件とマイメニュー1件を現在のモデルで正常に復号・検証し、空の保存領域へ復元した。通常版起動後も件数が保持され、ホームにマイメニューとクイックスタートが表示された。9月12日以降のデータの有無はユーザーへ確認が必要。
復元元とスクリーンショットは `/Users/macintosh/Documents/Codex/2026-09-11/r/recovery/` に保全（MUSCLEMORYのGitリポジトリ外）。
再発防止ガードが元のiPhoneシミュレーターIDを拒否することを確認済み。

空の専用iOSシミュレーター MUSCLEMORY QA: `0B986FD3-05C1-4ECF-8CA8-035433154498`。未起動。今後の統合テストはこちらだけを使用する。

## 2026-09-14：復旧対応の終了・開発再開（ユーザー承認）

GitHubのmain先端とローカル履歴が一致することを確認し、全10コミットにも記録バックアップがないことを確認。過去ログには削除前の履歴17件の存在が残るが、完全な記録データの復元元は見つからなかった。ユーザーの「ないならもういいよ」により捜索を終了し、「はい、それで進めてください」により開発を再開。復元済み6件・マイメニュー1件を保護し、元のユーザー端末では統合テストしない。

次の対応は既存要件の体重記録。入力→保存→グラフ→編集→再表示を専用QA端末で確認する。
- 非有限値（NaN、Infinity等）を体重として保存できないよう修正。
- 保存データ内の1件が不正な型でも、他の正常な体重記録まで読み込み対象から失われないよう修正。
- ネイティブ保存を使用する専用端末テストを追加。トレーニング履歴が変更されないことも検査。
- 従来の保存キー・正常なデータ形式・同日複数記録を維持。

体重機能の検証結果：静的解析・82テスト・iOS／Android arm64ビルド成功。専用iOS 26.5とAndroid 16で、82.5kg入力→保存→81.9kgに編集→画面再作成／保存再読み込み→グラフ反映を確認。トレーニング履歴が変わらないことも確認。OSプロセス再起動は未確認。詳細は `docs/qa/body_weight_2026-09-14/verification.md`。

次にSNS共有の実写真ピッカー・プレビュー・共有シートを確認する。画像書き出し後にui.Imageをdisposeし、繰り返し共有時の画像リソース保持を防ぐ修正を追加。

SNS検証：修正後の解析・82テスト・iOSビルドは成功。実際の写真ピッカー表示まで確認したが、Computer UseのwindowNotFoundAtPositionエラーで写真を選べず、共有シートまでの確認は未完了。ウインドウ選択・位置調整・接続リセットでも解決しなかったため、専用QAアプリだけ終了。ユーザー用端末には干渉せず。詳細は `docs/qa/share_photo_2026-09-14/verification.md`。次回はこの未確認フローを優先する。

最終反映：通常版iOSビルド20.5秒、Android arm64ビルド11.5秒で成功。専用QA端末のみ保持インストール／起動し、両OSともネイティブ保存領域に81.9kgが保持されていた。ユーザー用端末の記録には書き込みなし。GitHub commit/pushは実行していない。

Android最終画面のOS側ANRを発見したため追加対応。ログ上はテスト前のSystem UI／Phone起動失敗。専用AVDをホストGPUで再起動し、通常ホーム・保存済み81.9kgの保持・新しい起動にANR／クラッシュイベントがないことを確認した。実機性能は未確認。

## 2026-09-14：AGENTS.md追加最優先「複数種目の一括追加」

新しい最優先指定を確認し、SNS共有の未確認作業より先に着手。この項目の実装・実画面確認が終わるまで他の改善へ進まない。

実装：種目選択シート内にチェックボックス、選択件数、一括追加、全選択、全解除を追加。カテゴリ間の移動でも選択を保持。検索時の全選択は表示中の検索結果が対象であることを明示する。
マイメニューを追加シートから開き、その登録順・保存セット内容を維持して複数追加できる。追加済みの種目は選択不可。反映直前にも重複を除外。完了チェックは新しいトレーニングでは未完了にする。
1種目だけ選択して追加する操作を維持。カスタム種目作成後も選択一覧に入り、一括確定する。ホームの既存マイメニュー開始操作は維持。

小画面390×844のテストで、3種目選択・解除・再選択・全選択、登録順、保存セット、重量入力、再選択時の重複防止、別の1種目追加を確認。最初のテストは遅延描画の追加ボタンへのensureVisibleで失敗したため、スクロールして表示させる手順へ修正し成功。
専用iOS／Android端末での統合テストを続行する。

一括追加の検証結果：flutter analyze指摘なし、全83テスト成功。iOS 26.5とAndroid 16の専用端末で統合テスト成功。3種目選択・一括追加・全選択／全解除／個別解除・登録順・重複防止・追加後の重量入力・既存1種目追加を確認。実画面は `docs/qa/bulk_exercise_ios_2026-09-14/` と `docs/qa/bulk_exercise_android_2026-09-14/` に保存。最優先の確認条件を満たした。実機は未確認。

通常版の最終反映も完了：iOS／Android通常エントリーポイントでビルド成功後、専用QA端末へ保持インストール・起動。iOSの通常起動画面を保存。元のユーザー端末のインストール／記録変更、GitHub commit/pushは行っていない。AGENTS.md末尾に最優先対応の確認済み状況を追記。

## 2026-09-14: Beta distribution preparation

User is not enrolled in Apple Developer Program and wants to distribute to other testers. Prepared a release-signed Android APK for direct distribution and an unsigned physical-device iOS release build. No enrollment, payment, contracts or store uploads performed. Beta 1 uses 1.0.0+2.
Android release signing no longer falls back to a debug key. Private signing files are outside Git and excluded by gitignore; added a repeatable beta build script. Added INTERNET permission for optional release networking. This build has no Supabase configuration and uses local storage. The release key stays in MUSCLEMORY-private, never in Git or distribution artifacts.

## Beta build verification (2026-09-14)

- Version 1.0.0, build 2. flutter analyze: no issues. flutter test: all 83 passed.
- Android release APK built successfully. APK v2 signature verified, debuggable=false, 16KB zipalign verification passed. All 7 arm64 shared libraries have LOAD alignment >=16KB; execution on a 16KB device is unverified.
- Fresh install and normal app launch succeeded on a dedicated Android 16 / API36 / arm64 emulator. Home screen captured, crash log empty at inspection. Physical devices unverified.
- APK size: 89,077,844 bytes. SHA-256: `6fa5b635d4c7de2deaae3b6507997586a19ea06a336d449d57db9678872cc018`.
- iOS physical-device release build succeeded WITHOUT signing. Bundle ID `com.musclememory.muscleMemory`, version `1.0.0`, build `2`. No signed IPA, physical installation or TestFlight upload yet.
- Original user simulator and its records untouched. No GitHub commit/push.

APK, checksum, launch screenshot, logs and instructions are in the thread workspace beta/1.0.0-2 directory. TestFlight requires owner enrollment and signing setup. Native photo selection through sharing remains unverified.

## 2026-09-15：次回一括修正

依頼されたトレーニング記録、設定、種目追加、3D、ホーム、マイメニュー、SNS画像の関連修正を一括実施。

- 新規トレーニングは0種目、通常追加は1セット。最後の種目も削除できる。
- 休憩タイマーはセット完了設定に従い、終了時に短いシステム音と画面表示を行う。設定は親項目の直下へ配置。
- 旧2設定は保存互換性を保って「トレーニング時間」1項目へ統合。
- カスタム種目は部位別一覧の右上から作成し、その部位を固定して引き継ぐ。独立したカスタムカテゴリは廃止。
- ホームの「詳細」「履歴」「最近鍛えた部位」「クイックスタート」を除去し、体重推移を同一データ源からホームへ表示。ボリュームはkg表示。
- マイメニュー管理で名前、複数種目、並び替え、保存を直接行える。
- SNS画像はトレーニング時間を表示でき、長い種目名を固定領域で縮小・省略し、「保存」でiOS/Androidの写真ライブラリへ書き込む。
- 3D一覧導線を明示。Android 16でGLB内の編集用 `_MUSCLE_*` 頂点属性をFilamentが解釈してSIGSEGVとなる共通原因を特定。元素材は変更せず、ネイティブ描画へ渡すメモリ上コピーからだけ属性を除去した。Filament 1.74.0へ更新し、新APIへ追従。

最終確認は `flutter analyze` 指摘なし、全85テスト成功。Android 16 / API 36専用エミュレーターでベンチプレス3D、チェストプレス3D、SNS画像の写真保存を統合テストし、2シナリオとも成功。iOS 26.5専用シミュレーターではベンチプレス、インクラインダンベルプレス、チェストプレスの3D、新規記録から履歴、SNS保存、設定、マイメニュー入口を実画面確認。

Android署名済みRelease APKとiOSシミュレーター版をビルド。Android Releaseはversion 1.0.0 / code 2、debuggable=false、v2署名、16KB zipalign確認済み。物理端末とApple署名IPAは未確認。詳細は `docs/qa/batch_fixes_2026-09-15/verification.md`。GitHub commit/pushは行っていない。
