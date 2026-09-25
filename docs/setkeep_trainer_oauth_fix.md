# SETKEEP TRAINER Google OAuthコールバック修正

2026-09-25。

## 原因

TRAINERの `redirectTo` は既に `setkeep-trainer://login-callback/`、Android applicationIdとiOS Bundle IDも `com.setkeep.trainer` でした。両OSとも専用schemeを登録しており、一般版とschemeを取り合ってはいませんでした。

一方、接続中の共通Supabaseの許可Redirect URLは `musclemory://login-callback/` のみ、Site URLも同じ旧一般版URLでした。TRAINERのURLが未登録だったため、認証後にSite URLへ戻り、その旧schemeを引き続き受け取る一般版SETKEEPが開いていました。[SupabaseのRedirect URL仕様](https://supabase.com/docs/guides/auth/redirect-urls)でも、`redirectTo` を許可リストへ登録する必要があります。

前回の初期実装では、専用URLのコード・ネイティブ設定を追加した一方、サーバー側の登録を未完了として残していました。今回その登録漏れを解消しました。

## 修正

共通Supabaseの許可リストを以下に更新しました。

| 用途 | 許可したURI | アプリID / Bundle ID |
|---|---|---|
| TRAINER | `setkeep-trainer://login-callback/` | `com.setkeep.trainer` |
| 一般版 | `setkeep://login-callback/` | `com.setkeep.app` |
| 一般版の旧リンク互換 | `musclemory://login-callback/` | `com.setkeep.app` |

既存許可URLを残し、許可リストだけを宣言した一時設定を使って差分を確認してから反映しました。Site URL、Googleプロバイダー、メール確認、MFAなど、他の設定は変更していません。別Supabaseプロジェクト、新しいAuthユーザー基盤、DB migrationは作成していません。

- `lib/config/auth_redirects.dart`: アプリ別の正規コールバックを共通定数として管理。末尾スラッシュを含む値で統一。
- `lib/config/supabase_config.dart`: 一般版の既定値を共通定数へ参照変更。値は従来どおり。
- `apps/setkeep_trainer/lib/main.dart`: TRAINER専用定数をAuthサービスへ渡す。
- `supabase/config.toml`: ローカル設定にもTRAINERのURLを追加。
- `test/oauth_redirect_test.dart`: Android / iOS × 一般版 / TRAINERの4組合せで、実際のGoogle認証URLの `redirect_to`、共通Supabaseホスト、PKCE、外部ブラウザー起動を検証。ブラウザー起動だけをログイン成功にしないこと、起動失敗を通知することも検証。
- `pubspec.yaml` / `pubspec.lock`: URL起動境界のテスト用に、既に使用中のplatform interfaceをdev dependencyとして明示。パッケージのバージョン更新なし。
- `tool/check_oauth_redirects.py`: Native設定と実際の共通Supabase許可リストを検査する読み取り専用の配布前チェック。
- `docs/setkeep_trainer.md`: OAuthの登録済み状態と実機確認結果を更新。

AndroidManifest / Info.plistは既に正しく分離されていたため、内容を検証し、不必要な変更は行っていません。両OSの `FlutterDeepLinkingEnabled` 相当設定も無効で、Supabase/app_linksがコールバックを処理します。

## Galaxy実機での確認

端末: SM-S9310（Galaxy）、Android 16。

1. SETKEEP TRAINERを起動し、未ログイン状態であることを確認。
2. Googleボタンから外部ChromeのGoogleアカウント選択画面へ遷移。
3. Google認証完了後にTRAINERへ復帰し、トレーナープロフィール登録画面が表示されることを確認。
4. Androidの最前面Activityが `com.setkeep.trainer/.MainActivity` であることを確認。
5. 一般版・TRAINERの保存済みセッションのユーザーIDを端末上で照合し、**同一ID**で、どちらもGoogleプロバイダーのログイン状態であることを確認。セッショントークンはログ・Git・報告書へ出力していません。

Androidの `query-activities` でも、TRAINERのURIに応答するActivityはTRAINERの1件のみ、一般版のURIは一般版の1件のみでした。

問題解消はSupabaseの許可URL修正で確認でき、既存インストール済みアプリでも動作します。確認後にGalaxyのUSB接続が切れたため、今回の定数整理を含む再ビルドAPKの再インストールは行っていません。コールバックURIの値自体は同じです。

## 自動検証・iOS

- 両アプリの `flutter analyze`: 問題なし。
- OAuth・認証関連テスト: 12件通過（新規4件＋既存8件）。
- TRAINER画面テスト: 10件通過。
- 一般版の全体テスト: 273件中272件通過。変更していない休憩タイマーの瞬間表示 `01:00` を期待する既存テストが1件失敗しました。該当ファイルを単独再実行して5件すべて通過し、認証関連の失敗はありません。
- TRAINERのAndroidデバッグAPKとiOSシミュレーター向けビルド: 成功。
- 配布前チェック: Android/iOSの専用scheme、host、アプリID、Flutterルーティング設定、共通Supabase許可リストのすべてに合格。
- iOSシミュレーターで専用URIを開くと、OSが「SETKEEP TRAINERで開きますか？」と正しい宛先を提示することを確認。
- iOSのGoogleアカウント選択からの認証完了は、iPhone実機では未実施です。両OSが同じ専用URIと同じ修正済み許可リストを使用し、iOS向けURL生成もテストしています。

## 配布前の確認手順

リポジトリ直下で実行します。

```sh
python3 tool/check_oauth_redirects.py
```

CLIログイン・リンク済みプロジェクトが必要です。URL未登録なら失敗し、問題のURIを表示します。別プロジェクトやステージング環境へ移す場合も、アプリのビルド成功だけで済ませず、このチェックを通してください。ローカル設定のみの確認は `--local-only` を使用できます。

リポジトリの `supabase/config.toml` にはローカル開発向けの設定も含まれます。サーバー設定変更時は `supabase config diff` で宣言済み差分を確認し、意図した項目だけを更新してください。
