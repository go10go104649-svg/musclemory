# SETKEEP配布手順

現行の識別子・移行手順は [SETKEEPブランド移行](../setkeep_migration.md) を参照。以下の旧APK名とビルド実績は過去履歴です。

# 店舗検索対応のAndroid更新版（2026-09-24）

店舗検索・アカウント機能を利用する版は、Git対象外の接続設定を
`--dart-define-from-file` で必ず指定する。`tool/build_android_beta.sh` は
`SETKEEP_SUPABASE_CONFIG`（省略時 `supabase.json`）を検査し、設定なしでは生成しない。
旧版の「接続情報を組み込まない」という記述は過去の配布履歴であり、現在の手順ではない。
署名は従来の配布鍵を継続し、更新時にアプリを先に削除しない。

# 最新版：ベータ5（1.0.0 / ビルド5）

ファイル: `MUSCLEMORY-beta5-1.0.0-5.apk`。
既存2種目の3Dを維持し、ローロー・DYロー・ハイロー・バックエクステンションの3Dを通常の種目詳細で有効化。追加65種目の全展開は未完了。
Android用の署名済みAPK。既存ベータへ上書きインストールし、記録を守るため先にアプリを削除しない。
確認範囲と残作業: `../qa/forms_expansion_2026-09-16/progress.md` / `next_session.md`。

以下は以前の配布記録。

# ベータ4（1.0.0 / ビルド4）

ファイル: `MUSCLEMORY-beta4-1.0.0-4.apk`。ホーム・体重最新行・3Dカメラ復帰・休憩音とストップ・クラウド領域の整理を反映。
通常のバックアップ・復元は無料。Premium加入管理は未導入のため、クラウド部分のみ利用不可。
検証詳細は `../qa/home_rest_cloud_2026-09-15/verification.md` を参照。

既存の署名済みベータ版へ上書きインストールする。記録を保持するため、旧版を先に削除しない。

以下は初回配布時の記録。

# MUSCLEMORY ベータ1（1.0.0 / ビルド2）

## Android

今回の配布方式は直接インストールする署名済みAPK。Google Playには未公開。
テスターはAPKをAndroid端末へ保存し、ファイルを開いてインストールする。端末から求められた場合は、このファイルを開くアプリにインストールを許可する。Play Protectなどの保護機能を無効にしない。
更新時は同じ署名の新版を上書きインストールする。データを維持するため、旧版を先に削除しない。開発中のデバッグ版と今回の署名は異なるため、署名エラー時は削除せず、先にアプリ内のバックアップを書き出して開発者へ相談する。

## iPhone

Apple Developer Programは未登録。現時点ではインストールできるIPAやTestFlight招待リンクは発行していない。

1. アプリ所有者が https://developer.apple.com/programs/enroll/ から登録する。契約・支払いは所有者が行う。
2. 登録完了後、XcodeにそのApple Accountを追加し、SETKEEPのSigning Teamを設定する。
3. App Store Connectにアプリを作成する。Bundle IDは com.setkeep.app（登録可否はアカウントで確認）。
4. 署名済みArchiveを作り、App Store Connectへアップロードする。
5. TestFlightのベータ説明、連絡先、必要な輸出管理回答を実際の情報に基づいて入力する。
6. 外部テストの審査を申請し、承認後にテスターへTestFlight招待を配る。

Apple公式：
- https://developer.apple.com/support/compare-memberships/
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers

## テスター向け確認内容

- 種目を複数選択して一括追加し、重量・回数・時間などを記録する。
- トレーニングを完了し、履歴に記録とトレーニング時間が残ることを確認する。
- 任意で体重を追加・編集し、推移を確認する。
- 休憩タイマー、写真を使ったSNS共有、3D表示は端末ごとの動作を確認する。
- 気になった点は、端末名・OSバージョン・操作手順・画面写真を添えてアプリ所有者へ伝える。

## データと確認済み範囲

今回のビルドにはSupabaseの接続情報を組み込まない。ログイン不要で、記録は端末内に保存する。定期的にマイページのバックアップ機能で記録を書き出せる。
本ビルドには広告や課金を追加していない。所有者から指定されていない連絡先や個人情報を仮入力してストアへ送らない。
83件の自動テストと開発用iOS／Android専用端末での記録・一括追加等を確認済み。実機全般の互換性は未確認。SNS写真選択から共有までの一連の実画面確認は操作ツールの制約で未完了。

## 開発者向け

Androidの署名設定は環境変数 SETKEEP_SIGNING_PROPERTIES でGit外のファイルを指定する。署名情報なしのreleaseビルドは失敗させ、debug署名を配布版に流用しない。署名鍵とパスワードは配布フォルダーやGitHubへ含めない。
更新版は同じ鍵を使用し、pubspec.yamlのビルド番号を増やす。tool/build_android_beta.shで再作成できる。

## Beta build verification (2026-09-14)

- Version 1.0.0, build 2. flutter analyze: no issues. flutter test: all 83 passed.
- Android release APK built successfully. APK v2 signature verified, debuggable=false, 16KB zipalign verification passed. All 7 arm64 shared libraries have LOAD alignment >=16KB; execution on a 16KB device is unverified.
- Fresh install and normal app launch succeeded on a dedicated Android 16 / API36 / arm64 emulator. Home screen captured, crash log empty at inspection. Physical devices unverified.
- APK size: 89,077,844 bytes. SHA-256: `6fa5b635d4c7de2deaae3b6507997586a19ea06a336d449d57db9678872cc018`.
- iOS physical-device release build succeeded WITHOUT signing. Bundle ID `com.musclememory.muscleMemory`, version `1.0.0`, build `2`. No signed IPA, physical installation or TestFlight upload yet.
- Original user simulator and its records untouched. No GitHub commit/push.
