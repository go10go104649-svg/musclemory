# SETKEEP TRAINER テナント対応 — 実装・検証記録

2026-09-25。作業ブランチのローカル変更です。commit / push、本番DBへの適用は行っていません。Galaxyは手元にないとの回答のため実機検証は未実施です。

## 1. 現行GitHubで確認した既存仕様

作業開始時のローカルHEADと `git ls-remote origin HEAD` はともに `6eaedc472bfbdcfcb80d09f9617079a83f8057e2`。README、AGENTS、移行・TRAINER・OAuth資料と実装を確認しました。一般版はルート、TRAINERは `apps/setkeep_trainer`。共通Auth / 種目カタログ / 記録形式を使用し、アプリIDとOAuth URIはアプリごとに独立しています。適用済みの `202609250001` は変更していません。

## 2. 不足していた仕様

従来は trainer_id と本人の client_id を直接結び付ける構造でした。契約主体、複数所属、スタッフ権限、オフライン顧客、複数担当、課金人数・試用期間、共有編集、取消・復元、監査が不足。部位画面とメニュー入力は簡易な独自UIでした。

## 3. tenant

`tenants` を契約主体として追加。personal / gym / store / company を格納でき、Authユーザーから独立します。アプリは所属が1件なら自動選択し、複数なら上部から切り替えます。新規作成UIは個人テナント、他の種別は同じ作成RPCで扱えます。取得中は旧データを非表示にし、テナントごとの不変RepositoryとNavigatorを作成します。切替時に顧客詳細・編集中ルートを破棄し、遅れて完了した旧取得結果を反映しません。

## 4. membership / role

`tenant_memberships` は `(tenant_id, user_id)` ごとに active / removed と独立した Admin / Trainer フラグを保持。Billing Ownerはtenantの1つのユーザー参照です。Ownerのみ、Adminのみ、Trainerのみ、兼任を表現できます。個人テナント作成時は本人をOwner / Admin / Trainerにします。Ownerの所属解除前には所有権移譲が必要。所属解除またはTrainer権限の削除時には担当割当を解除し、再招待で過去の権限・担当が自動復活しないようにします。スタッフは確認済みの招待先メールでログインして招待を受け、待機中の招待はmembershipを作りません。

## 5. client

`tenant_clients.id` はAuthユーザーIDとは別です。`linked_user_id` はNULLで登録可能。オフラインのままメニュー・コメント・代理記録を使い、既存のコード / QRを本人が確認済みアカウントで承認すると紐付きます。既存の顧客ID、メニュー、メモ、履歴を作り直しません。1テナント内の同じ本人への重複リンクをDBで防ぎます。

## 6. Trainer assignment

`tenant_assignments` は顧客とトレーナーの多対多。複合外部キーで異なるtenantの組合せを拒否します。Adminはスタッフ・顧客一覧と割当を管理しますが、Admin権限だけでは指導データを取得できません。同じ顧客を担当するactive Trainerがメニューとコメントを共有します。未担当・所属解除・連携解除後はサーバーで拒否します。

## 7. TRAINER ID算定

当該tenantの `status=active AND is_trainer` を数えます。Adminのみは0、兼任は1、招待待ちは0、同じユーザーでも別tenantでは別に算定。サーバーの見積は `3980 + max(count - 5, 0) * 500` 円/月。実課金はまだ行いません。

## 8. subscription / trial

`tenant_subscriptions` にStripe customer / subscription ID、契約状態、plan、カード登録状態、試用開始・終了を保持。14日、カード必須、1tenant1回、trial中5 Trainerまでをサーバー側で検査します。権限更新・招待受諾はtenant行ロックで直列化します。ブラウザーやアプリから課金状態を直接更新できません。`tenant_apply_billing` はservice_roleのみ実行可能で、イベントIDによる重複適用防止を備えます。**Stripe署名を検証するWebhook / Checkoutとの接続は未実装**です。このRPCをクライアント入力を受ける公開エンドポイントへ直結しないでください。自動決済・支払失敗時の利用制限を有効化したものではありません。

## 9. 新規migration

`supabase/migrations/202609250002_tenant_foundation.sql`。追加テーブル、workoutsへの所属・取消列、バックフィル、RLS、RPC、監査を1トランザクションにまとめています。既存テーブルやAuthプロジェクトをDROP / 作り直す処理はありません。オフライン記録のためworkouts.user_idをNULL許可にし、本人IDまたはtenant+clientのいずれかが必須となるCHECKを追加しています。

## 10. 既存データの移行

既存trainerごとに `md5('setkeep.personal.' || user_id)::uuid` で個人tenantを作成します。同じ顧客を持つtrainer同士を推測して統合しません。既存link IDをtenant client IDとして維持し、共有フラグ・状態・日時を保持。メニューID、メモID、記録IDを保持し、従来のセット数と一律目標値をセット行に展開します。workoutsのuser_id / recorded_by / record_sourceを維持。未使用の旧招待トークンも移行します。元のtrainerテーブル行は残します。

## 11. RLS

新しい全テーブルでRLSを有効化し、匿名・直接書込み権限を剥奪。読み取りも所属・担当によって制限します。顧客一覧の管理権限と指導情報の閲覧権限を分けています。workoutsの本人向けRLSは広げません。Trainerの履歴参照は専用RPCのみ。本人の共有履歴と当該tenantで作られた代理記録だけを返し、別tenantで作られた代理記録を共有対象に混ぜません。体重は自動取得しません。

## 12. SECURITY DEFINER RPC

全関数のsearch_pathを固定し、PUBLIC / anonへの既定EXECUTEを除去しています。実行者はauth.uid()から取得。`tenant_mutate` は操作ごとにactive所属、必要なrole、clientとの同tenant性、担当、編集可能状態、versionを検証します。招待、権限変更、割当、代理記録、取消はtenant行ロックを共有。`tenant_workouts` はshare_workoutsとheatmap用途のshare_heatmapを検査し、記録・取消はallow_recordingを検査。オフライン顧客では当該tenant内の担当者が指導記録を管理します。

## 13. 監査

`tenant_audit` にactor、対象、時刻、変更前 / 後を追加専用で記録。membership、招待受諾、assignment、本人連携・解除、メニューと各セット、コメント、テンプレート、代理記録・取消・復元、Owner変更、subscription変更を対象にします。既存データの移行は専用イベントを記録します。Owner向けの監査SELECTも管理情報に限定し、指導内容を含むsnapshotをOwner / Admin権限だけで読めないようにしています。包括的な監査閲覧UIは未実装です。

## 14. Auth / OAuth

Auth、Google OAuth実装、Supabase接続先、アプリID、署名設定、Manifest / Info.plistは変更していません。一般版 `setkeep://login-callback/`、TRAINER `setkeep-trainer://login-callback/`、一般版の旧schemeを保持。`tool/check_oauth_redirects.py` により両OSの設定と接続先Supabaseの明示許可リストを検査済みです。今回の実Googleアカウント選択から同一user_idまでの再確認は未実施です。

## 15. 共通UI

共通テーマを `lib/design/family_theme.dart` に抽出し、両アプリから利用。`BodyMapPage`、`MuscleMannequinView`、`ExercisePickerViewport`、`ExercisePickerSheet`、`ExerciseInputCard`、`SetRow`と既存数値入力を直接使用します。別実装のコピーはありません。TRAINERから参照する画像、3Dモデル、フォームの分割アセットを `packages/setkeep/` 経由で読みます。共通部品の日本語中心の文言は本体を維持しており、TRAINER全画面の完全な英語化は今回完了していません。

## 16. 水色Theme

TRAINERのaccent / Primaryは `#79D5F6`。薄い背景と選択色もFamilyPaletteに集約。小さい文字のボタンは暗い前景色にして可読性を保ちます。旧 `#00D084` は実装から除去。一般版は `#C7F36B` と既存ThemeDataを維持し、テーマ等価性テストで検証します。

## 17. 部位画面

簡易棒グラフ画面を本体のBodyMapPageへ置換。期間切替、3D角度切替、部位カードが同一です。開く際に許可をサーバー確認し、履歴の全ページを取得して期間集計するため、「読み込んだ先頭100件だけ」の分析にはしません。取消記録は集計から除外。筋肉の赤い濃淡は一般版と同じ分析表現として保持します。

## 18. メニュー / セット

複数種目と各セット個別の重量・回数・既存の時間距離系入力、セット追加・削除に対応。許可された顧客の履歴から前回値を反映できます。完了チェックを局所的に非表示にし、本体の設定値は変更しません。ワークアウト完了処理・休憩タイマーは組み込んでいません。名前、顧客、メモ、single / repeat、期限を保存。担当者間の未実施メニュー編集にversion検査を使います。実施済みの再オープン編集は拒否し、取消から復元すると元の状態へ戻します。日別 / メニュー別コメント、tenant内テンプレート保存・読込、代理記録の取消・復元UIを追加。repeatは種別を保持するもので、カレンダー上への自動展開・予約生成は含みません。

## 19. 一般版への影響

本体の配置・保存形式・カタログ・Auth・Premium判定を維持。一般版の連携一覧はtenant clientを返すRPCへ切替え、同意文を「テナントの担当者」へ更新。取消済み代理記録は新規受信対象から除外します。**既に端末へ取り込んだ履歴の取消を自動的に双方向同期する機能はありません。** 共通テーマは一般版では従来と同じ値を返します。

## 20. Android確認

一般版・TRAINERのdebug APKビルド成功。専用QAエミュレーターでTRAINERの3D表示、セット追加、共通種目ピッカーを通すnativeテスト1件が成功し、画面を目視確認しました。通常の両アプリを同時インストール後、OSのquery-activitiesで `setkeep://login-callback/` はcom.setkeep.appだけ、`setkeep-trainer://login-callback/` はcom.setkeep.trainerだけに解決されることを確認。Galaxy実機は未実施です。

## 21. iOS確認

一般版・TRAINERのdebug simulatorビルド成功。新規の専用iPhone 17 Pro / iOS 26.5シミュレーターで、TRAINERの共通3D、セット追加、種目画像を通すnativeテスト1件が成功。3Dモデルと水色UIの画面を目視確認しました。iPhone実機、実Googleアカウント認証は未実施です。

## 22. Flutter確認

一般版 `flutter test` **275件通過**。TRAINER **14件通過**。両アプリの `flutter analyze` は問題なし。追加検証には別tenantへの切替中に到着する旧レスポンスの破棄、詳細ルートの破棄、共有セット入力と前回記録の反映、パッケージ経由の3D分割アセット再構築を含みます。一般版のThemeData等価性を既存テストで維持しました。

## 23. Supabase / SQL確認

PostgreSQL 17の隔離DBで、**新テナント55項目＋既存データ移行11項目＋移行前の既存35項目＝101項目通過**。認証・ロール・RLS・RPCをSupabase相当のauth.users / auth.uid()とroleで検証しました。本番Supabaseの実ユーザーを使ったテストではありません。

権限・ID差替え・未担当・Adminのみ・同意・オフライン本人リンク・代理記録冪等性・取消復元・実施済みメニューの編集拒否・編集version・Owner独立権限・5名上限・課金人数・カード必須・trial再利用拒否・クライアントによる課金状態偽装拒否・旧招待トークン保持を確認。`tool/check_oauth_redirects.py` のローカル設定 / 接続先Supabase許可リスト検査も通過しました。

## 24. 本番適用と残作業

本番migrationは**未適用**。新しい連携画面も新RPCを利用するため、一般版・TRAINER・DBの切替を揃える必要があります。旧TRAINERの直接書込み権限と旧trainer専用RPCを退役させるため、本番DBへ先に適用すると旧TRAINERの操作が失敗します。バックアップ、ステージングでの実ユーザー相当の受入確認、両アプリ更新を揃えて適用してください。DBダウングレードや旧テーブルへの書戻しを自動実行する手順は用意していません。

Galaxy / iPhone実機でのGoogleログインと本人同一性、2つの実アカウントでの招待から解除までの通し確認は残っています。Stripe Checkout・検証済みWebhook・実請求・支払状態に応じた提供制御、詳細な監査管理画面、体重データの共有、端末履歴との取消双方向同期、繰返し予定の自動展開は未実装。BUSINESS本体には着手していません。

### 隔離DBでの再検証

`trainer_foundation.sql` は202609250001までの環境向けです。202609250002適用後は新しい権限契約を検査する `tenant_foundation.sql` を実行します。

バックフィルは空の隔離DBに202609250001までを適用し、順に以下を実行します（本番では実行しないこと）。

1. `supabase/tests/tenant_backfill_fixture.sql`
2. `supabase/migrations/202609250002_tenant_foundation.sql`
3. `supabase/tests/tenant_backfill_assertions.sql`

アプリのnative UIテストは本番Authを使わないfixture方式です。専用QA端末に対して、TRAINERディレクトリで `flutter test integration_test/shared_ui_test.dart -d <QA device>` を実行してください。

## 25. 変更ファイル

- 新規: `lib/design/family_theme.dart`, `lib/trainer/tenant_repository.dart`
- 新規: `apps/setkeep_trainer/lib/tenant_gate.dart`, `tenant_management.dart`
- 新規: `supabase/migrations/202609250002_tenant_foundation.sql`
- 新規: `supabase/tests/tenant_foundation.sql`, `tenant_backfill_fixture.sql`, `tenant_backfill_assertions.sql`
- 新規: `test/family_assets_test.dart`, `apps/setkeep_trainer/integration_test/shared_ui_test.dart`
- 変更: `lib/main.dart`, `lib/bench_press_form.dart`, `lib/body_part_illustration.dart`
- 変更: `lib/trainer/trainer_repository.dart`, `trainer_sharing_page.dart`
- 変更: `packages/interactive_3d/lib/src/form_asset_bundle.dart`
- 変更: `apps/setkeep_trainer/lib/main.dart`, `client_page.dart`, `menu_editor.dart`, `trainer_widgets.dart`
- 変更: `apps/setkeep_trainer/test/trainer_app_test.dart`, `pubspec.yaml`, `pubspec.lock`
- 文書: 本書、`docs/setkeep_trainer.md`

## SETKEEP本人向け連携の追加仕様（2026-09-25）

[SETKEEP / SETKEEP TRAINER 共通メニュー・コメント仕様](setkeep_trainer_delivery.md) を両アプリ共通の現行仕様とする。既存tenantメニューを本人Auth IDで参照し、一般版の通常トレーニング開始処理へ渡す。コメントは公開設定と編集・削除を持ち、従来の内部メモは明示公開するまで非公開。データの複製、RLS無効化、別Authプロジェクト化は行わない。migration 202609250003と先行002の適用・アプリ更新を揃える。
