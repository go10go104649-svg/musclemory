# SETKEEP TRAINER 初期実装（移行前の記録）

**テナント対応の最新ローカル実装・移行手順は [setkeep_trainer_tenants.md](setkeep_trainer_tenants.md) を参照してください。本書の配色・個人紐付け・簡易UIは初期版の履歴です。**

2026-09-25。SETKEEPと同一GitHubリポジトリ内の独立Flutterアプリです。

## 1. 実装した内容

一般版はリポジトリ直下に残し、`apps/setkeep_trainer` にiOS / Androidアプリを追加しました。一般版のAuthサービス、Supabase設定、種目カタログ、`WorkoutRecord` / `RecordedSet` とそのJSON形式をpath依存で再利用します。コピーした履歴テーブル・種目マスターはありません。

一般版を先に `apps/setkeep` へ移す大規模な変更は避けています。共通資産は現在の `lib/` を正とし、将来 `packages/setkeep_auth` / `setkeep_training` / `setkeep_exercises` へ段階的に移せます。path依存には既存のネイティブプラグイン・アセット依存も含まれるため、配布サイズの最適化は今後の課題です。

アプリ名は **SETKEEP TRAINER**、両OSの識別子は **com.setkeep.trainer**。一般版 **com.setkeep.app** と共存します。TRAINERは指定の `#00D084` をアクセントの基準にし、既存一般版の現在の配色は変更していません。スマートフォンは下部4タブ、幅720以上はサイドナビゲーション。日本語・英語のUI文言を用意しています。

## 2. 新規ファイル

- `apps/setkeep_trainer/lib/main.dart`: 起動、認証、プロフィール登録、ホーム、顧客・メニュー・マイページ。
- `apps/setkeep_trainer/lib/client_page.dart`: 顧客詳細、履歴、指導メモ。
- `apps/setkeep_trainer/lib/menu_editor.dart`: メニュー作成とセッション記録。
- `apps/setkeep_trainer/lib/trainer_widgets.dart`: 共通表示、既存履歴モデルのアダプター、簡易部位ヒートマップ。
- `apps/setkeep_trainer/test/trainer_app_test.dart`: 設定、認証遷移、画面幅、顧客権限、作成操作、入力検証。
- `apps/setkeep_trainer/pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.metadata`, `.gitignore`, `README.md`。
- `apps/setkeep_trainer/android/`: アプリ設定、MainActivity、Gradle設定、標準アイコン・起動画面。
- `apps/setkeep_trainer/ios/`: Runner / RunnerTests、Xcode設定、Info.plist、標準アイコン・起動画面、依存ロック。
- `lib/trainer/trainer_repository.dart`: 両アプリで使う共有DBアクセス境界。
- `lib/trainer/trainer_sharing_page.dart`: 一般版での招待確認・承認・解除・共有・受信。
- `test/trainer_sharing_test.dart`: 明示承認、権限初期値、受信、要求ID。
- `supabase/migrations/202609250001_trainer_foundation.sql`。
- `supabase/tests/trainer_foundation.sql`。
- 本ドキュメント。

## 3. 変更した既存ファイル

- `lib/main.dart`: 一般版の「Trainerと連携」の遷移先と、代理記録の既存履歴への取り込み。既にある同時刻の記録はUTCで照合し、ローカル編集を上書きしません。
- `lib/services/account_auth_service.dart`: OAuthのリダイレクトURLを注入可能に変更。一般版の既定値は `setkeep://login-callback/` のままです。
- `lib/trainer_qr_page.dart`: 検出結果コールバック追加。カメラ所有・破棄処理と従来の解析テストを保持。
- `test/widget_test.dart`: QRカメラ直行から承認画面への変更を検証。
- `test/workout_completion_test.dart`: 再開後の実時間加算を許す検証へ修正。変更前から負荷時に120秒/121秒の揺れがありました。
- `README.md`: TRAINERの開発ガイドへのリンク。

## 4–6. Supabase、migration、RLS

共通Supabase Authの `auth.users.id` を使用します。`trainer_profiles` の存在がトレーナーの役割を表し、一般ユーザーとの兼任を許可します。別の認証ユーザーを作る設計ではありません。既存リポジトリと接続先を照合し、独立した汎用 `profiles` / `users` テーブルは確認されなかったため、役割専用プロフィールを追加しました。

追加テーブル:

| テーブル | 用途 | アクセス |
|---|---|---|
| trainer_profiles | トレーナー表示名・共通ユーザーID | 本人が編集、承認済み顧客が参照 |
| trainer_invites | UUID招待・24時間の期限・使用者 | 直接アクセス不可、RPCのみ |
| trainer_client_links | 双方のID、顧客表示名、状態、共有権限 | 当事者だけ参照、変更はRPCのみ |
| trainer_notes | 顧客別指導メモ | 作成トレーナー本人のみ |
| trainer_menus | 顧客別メニュー、種目ID・目標セット/重量/回数・メモ | 作成トレーナー本人のみ |

`workouts` に `recorded_by` / `record_source` を追加しました。代理記録は顧客の `user_id` でこの同じテーブルへ書き込みます。トレーナー専用履歴は作成しません。代理記録RPCは要求UUIDにより同じ保存の再試行を重複登録しません。本人の既存更新処理からも記録者を偽装できないトリガーを設置しています。

接続先には `supabase/schema.sql` で定義されていた `workouts` が未配備でした。migrationは未作成時に限って同じ定義と本人向けRLSで作成します。既存テーブルがある環境では保持します。既存の本人向けSELECT / INSERT / UPDATE / DELETEポリシーを広げず、トレーナーの履歴アクセスは `trainer_client_workouts` を通します。

招待はトレーナー自身が発行し、再発行で以前の未使用コードを無効化します。プレビューだけでは連携されません。ログイン中の顧客本人が表示名と権限を確認して承認するRPCだけがリンクを作成します。自分との連携、使用済み・期限切れ招待、無承認の直接リンク作成を拒否します。解除と代理記録はリンク行のロックで直列化します。

すべての新規テーブルでRLSを有効化し、匿名権限を除去しています。データにアクセスするSECURITY DEFINER関数は固定search_path、認証済みロール限定の実行権限、`auth.uid()` に基づく検査を持ちます。呼出側からトレーナーIDは受け取りません。

権限は `share_workouts` / `allow_recording` / `share_heatmap` / `share_body_weight` で分離しています。代理記録・ヒートマップは初期値false、体重は本実装で一切取得・共有しません。履歴を共有すると種目から使用部位も分かるため、ヒートマップのフラグは独立した秘密データの境界ではなく表示への同意です。この点を承認画面で説明しています。

migration **202609250001 は共通Supabaseへ適用済み**。適用後のmigration一覧とRLSを確認しました。顧客・トレーナーの本番実データをテスト用に作成していません。

## 7. 実装済み機能と操作

1. 共通アカウントのメール/パスワード認証・登録、Google OAuth呼び出し、ログアウト。
2. 同一ユーザーへのトレーナープロフィール追加。
3. ホーム、顧客、メニュー、マイページの4画面。
4. 招待QR / コード発行、一般版のQR読取 / コード入力、相手名確認、明示承認、連携解除。
5. 顧客一覧の表示名・最終記録日・最近の種目。未連携/未共有/取得失敗を区別。
6. 顧客詳細の基本情報・履歴・セットごとの種目/重量/回数・メニュー・非公開メモ。
7. 共通カタログの種目を複数追加できるメニュー作成。代理記録は初期版として重量・回数系種目に対応。
8. 顧客本人のクラウド履歴への代理記録と一般版での受信。
9. 承認済みの場合の簡易部位別セット数ヒートマップ。読み込み済み件数を表示。
10. 履歴の100件単位の追加読み込み、読み込み再試行、入力値検証。

一般版は従来どおりローカル保存が中心です。Premium向けクラウドバックアップは従来の無効状態を維持します。本人が「Trainerと連携」で選択したローカル記録だけを共有できます。クラウド上の共有済み履歴は、承認したすべての連携中トレーナーが閲覧できます。体重・写真・一般版の個人メモを一括アップロードしません。

代理記録の受信は一般版の「Trainerと連携」→「トレーナーの代理記録を受信」で明示的に行います。取り込み後は通常の履歴タブで表示できます。自動同期、オフライン送信キュー、編集/削除の双方向同期は未実装です。

## 8. 未実装・制約

- 予約、チャット、通知、AI、課金、決済、売上、SETKEEP BUSINESS。
- 体重共有と詳細な権限変更UI。権限を変える場合は解除後に新しい招待で承認し直します。
- 顧客へのメニュー配信、メニュー編集/削除UI、指導メモ編集/削除UI。
- 時間・距離・有酸素系の代理記録入力。過去履歴は既存モデルで読み取ります。
- 3Dヒートマップの統合、専用アプリアイコン、配布サイズ最適化。
- 実機上での2アカウント間の顧客連携全操作とメール確認フローは未検証。GoogleログインはGalaxyでTRAINERへの復帰と一般版との共通ユーザーIDを確認済み（[修正記録](setkeep_trainer_oauth_fix.md)）。
- 共通SupabaseのAuth許可リストに `setkeep-trainer://login-callback/` と `setkeep://login-callback/` を登録済みです。旧一般版のURLも維持しています。別環境・再配布時は `python3 tool/check_oauth_redirects.py` でサーバー設定を含めて検証してください。コード側では両OSに専用schemeを登録し、Flutterルーティングとコールバック処理の競合を無効化しています。
- 端末にログイン資格情報があり、共通プロジェクトのAuth設定が整っている必要があります。テスト用ユーザーやパスワードは同梱しません。
- 連携解除は今後のサーバー取得を止めます。既に閲覧・保存された情報やトレーナー所有のメモは自動消去しません。

## 9. 検証

- 一般版 `flutter analyze`: 問題なし。
- 一般版 `flutter test`: **269件通過**。
- TRAINER `flutter analyze`: 問題なし。
- TRAINER `flutter test`: **10件通過**。
- 一般版のAndroidデバッグ・iOSシミュレータービルド: 成功。
- TRAINERのAndroidデバッグ、iOSシミュレータービルド: 成功。iOSシミュレーターへのインストール・起動も確認。
- PostgreSQL 17の隔離DBで、既存workoutsあり/なしの双方からmigrationを適用し、SQLテスト通過。
- SQLテストは35項目。招待の期限切れ・再発行、他人ID、無承認リンク、記録権限、非公開メモ、匿名アクセス、解除後アクセス、値検証、記録者偽装、冪等性を含みます。テストデータはトランザクションでロールバック。

Supabaseテスト用プロジェクトなど、**破棄可能なDB**でのみ次を実行してください。

```sh
psql "$TRAINER_TEST_DATABASE_URL" -X -v ON_ERROR_STOP=1 -f supabase/tests/trainer_foundation.sql
```

テストにはSupabase互換の `auth.users` / `auth.uid()` / `authenticated` / `anon` が必要です。本番DBには実行しないでください。

## 10. 一般版への影響

保存形式、既存の種目ID、Premium判定、テーマ、パッケージ名、署名、既存認証URLは保持しています。一般版の「Trainerと連携」は認証・同意を先に確認する画面へ変わります。連携操作をしないユーザーの履歴・体重を自動共有する処理はありません。本人向けの既存RLSは維持しています。

## 11. 次の優先順位

1. 2つの実アカウントを使い、Android / iPhoneで招待→承認→共有→代理記録→受信→解除を通して確認。
2. 安全な同期キュー、アカウントごとの端末内履歴分離、共有解除・編集・削除の同期設計。
3. 共通モデル/認証/カタログの独立packageへの抽出とアセット依存縮小。
4. メニュー編集・顧客への配信、権限変更UI、実用的な部位分析。
5. 予約・所属店舗などの拡張。

## 12. Android実機確認

端末の開発者向けオプションとUSBデバッグを有効にし、USB接続を許可します。

```sh
cd apps/setkeep_trainer
flutter pub get
flutter devices
flutter run -d <Android端末ID> --dart-define-from-file=../../supabase.json
```

一般版はリポジトリ直下から別途 `flutter run -d <Android端末ID> --dart-define-from-file=supabase.json` で起動してください。別の顧客アカウントを使って承認し、連携完了前には顧客が一覧に現れないこと、代理記録を許可しなければ記録ボタンが無効なことを確認します。端末1台でも別アプリに異なるアカウントでログインできます。

## 13. iPhone実機確認

MacにiPhoneを接続して信頼を許可し、開発者モードを有効にします。`apps/setkeep_trainer/ios/Runner.xcworkspace` をXcodeで開き、RunnerのSigning & Capabilitiesで自分のTeamを選択してください。一般版のTeam・Bundle ID・署名情報は変更しないでください。秘密鍵やプロビジョニングプロファイルはGitに含めません。

```sh
cd apps/setkeep_trainer
flutter pub get
flutter devices
flutter run -d <iPhone端末ID> --dart-define-from-file=../../supabase.json
```

iPadでは横向きと縦向き、スマートフォンではキーボード表示中の入力・保存も確認してください。一般版と併用し、カメラ権限、QR承認、セッション受信、連携解除後のアクセス拒否を確認します。OAuthは専用URLを許可リストへ追加したうえで、外部ブラウザーからTRAINERへ戻ることを確認してください。

## SETKEEP本人向け連携の追加仕様（2026-09-25）

[SETKEEP / SETKEEP TRAINER 共通メニュー・コメント仕様](setkeep_trainer_delivery.md) を両アプリ共通の現行仕様とする。既存tenantメニューを本人Auth IDで参照し、一般版の通常トレーニング開始処理へ渡す。コメントは公開設定と編集・削除を持ち、従来の内部メモは明示公開するまで非公開。データの複製、RLS無効化、別Authプロジェクト化は行わない。migration 202609250003と先行002の適用・アプリ更新を揃える。
