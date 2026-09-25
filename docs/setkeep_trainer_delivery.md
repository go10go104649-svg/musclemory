# SETKEEP / SETKEEP TRAINER 共通メニュー・コメント仕様

2026-09-25。一般版とTRAINER双方の現行連携仕様。従来の「トレーナーのみがメニュー・指導メモを閲覧する」という制約は、以下の範囲で更新する。

## 共通データと本人識別

両アプリは同じSupabaseプロジェクト、同じAuthユーザーを使用する。メニューやコメントをSK向けテーブルやSharedPreferencesのマイメニューへ複製しない。

- `tenant_clients.id`：テナント内の顧客ID。Auth IDと混同しない。
- `tenant_clients.linked_user_id -> auth.users.id`：本人の識別子。表示名・メールによる照合はしない。
- `tenant_assignments(tenant_id, client_id, user_id)`：担当トレーナーとの関係。
- `tenant_menus(tenant_id, client_id)`：割り当てメニュー。同じID・行を両アプリで読む。
- `tenant_menu_exercises(menu_id, position)`：種目ID、名前、部位、設備、記録タイプ、種目順。
- `tenant_menu_sets(exercise_id, position, values)`：セット順と既存SKのRecordedSet JSON値。
- `tenant_comments(tenant_id, client_id)`：本文、作成者Auth ID、編集者Auth ID、作成日時、更新日時、version、任意のmenu_id／workout_date。

オフライン顧客は本人が既存の招待コードを承認するまでSKには表示されない。承認後はlinked_user_idを使って既存行を参照し、メニュー／コメントIDは変えない。

## メニュー登録・更新・利用

TRAINERの既存MenuEditor、tenant_mutate('menu')、正規化済みの既存表を継続使用する。単発／繰り返し、期限、メニュー名、対象顧客、メモ、種目順、全セットを保持する。

セットは重量、回数、時間、距離、距離の表示単位、速度、傾斜、負荷レベル、ペースを既存RecordedSet形式で保持する。TrainerMenuCodecをTRAINER編集画面とSK開始処理で共用し、別のTRAINER専用保存形式は追加しない。

一般版ホームの「トレーナーからのメニュー・コメント」から閲覧する。未ログイン時はアカウントでのログインを案内する。取得時には現在のAuth IDで対象を限定し、DBのRLSでも検査する。

画面を開く、再読み込み、引っ張って更新、アプリ復帰でクラウドの最新行を取得する。常時Realtime購読は使用しない。リロード失敗時は古い内容を隠して再試行を案内する。ログアウト／アカウント切替では表示を消し、前アカウントの遅延レスポンスを破棄する。

開始直前にIDで最新行を再取得する。取消・解除・権限喪失・取得失敗時は開始しない。versionが変わっていれば最新内容を表示し、再度の開始操作を求める。plannedのみ開始でき、completedは閲覧のみ、canceledは本人向け一覧から非表示。復元すると同じIDで再表示する。

実際のトレーニングは既存Dashboardの開始処理から既存WorkoutPageを開く。進行中下書きの確認、利用場所、店舗／設備、セット入力、完了チェック、休憩タイマー、履歴保存は既存経路を使用する。メニューを恒久的なローカルマイメニューへ取り込まない。開始後の作業用下書きと完了した本人のトレーニング記録は通常どおり保存する。

開始済みトレーニングを後から届いたメニュー変更で書き換えない。SKで完了しても、指導側メニューのstatusを自動変更しない。既存のTRAINER側実施状態管理を維持する。繰り返し予定の自動生成は追加しない。

## コメントの公開・編集・削除

新規コメントは「本人のSETKEEPにも表示する」を初期ONとし、OFFなら担当者だけが閲覧する。メニュー／日別コメントも同じ公開設定を持つ。

**従来「担当者間の指導メモ」として保存された行は自動公開しない。** migrationでshared_with_client=falseとし、編集画面もその値を維持する。既存メモを本人へ共有する場合は担当者が明示的にONへ変更する。

新しいtenant_save_comment RPCで作成・編集・公開設定変更・削除する。作成者／編集者はauth.uid()から決定し、入力されたトレーナーIDは使わない。編集と削除はid、tenant_id、client_id、versionを確認する。別顧客／別テナントへの付け替えや、古いversionでの上書きを拒否する。新規menu_idは同じ顧客・同じテナントに所属する場合だけ受け付ける。

編集は同じコメントIDの本文とupdated_atを更新する。削除は確認後に同じ行を削除し、既存tenant_auditへ監査を残す。SKでは次の取得で編集・削除・非公開化が反映される。

旧tenant_mutate('comment')は互換性のため維持し、その経路の新規行も従来どおり非公開。旧内部メモを誤って公開する変更はしない。

## RLS・権限

既存RLSを有効なまま維持し、一般ユーザーにはSELECTのみを追加する。

- メニュー：担当active Trainer、またはactive clientのlinked_user_id=auth.uid()。
- 種目・セット：親メニューのRLSを通過する行のみ。別ポリシーで子だけを公開しない。
- コメント：担当active Trainer、またはactive client本人かつshared_with_client=true。
- 顧客本人はメニュー／コメントを直接INSERT・UPDATE・DELETEできない。
- Adminのみ／未担当／所属解除済み／匿名ユーザーには指導内容を公開しない。
- 連携解除後は本人向けのメニューとコメントも非表示。

既存workouts、履歴、体重、カタログ、Auth／OAuthポリシーは今回変更しない。SECURITY DEFINER関数のsearch_pathは固定し、PUBLIC／anonの実行権限を剥奪する。更新RPCはテナント行ロックを取り、既存の割当・解除処理と直列化する。

## migrationと適用条件

今回：`202609250003_trainer_client_delivery.sql`。
コメントへshared_with_client、updated_at、edited_by、versionを追加し、本人判定関数、RLS SELECT、コメント更新RPCを追加する。メニュー保存テーブルは増やさない。

前提：`202609250001_trainer_foundation.sql`、`202609250002_tenant_foundation.sql`。
2026-09-25の接続先確認では001まで適用済み、002／003は未適用、tenant_menus／tenant_commentsは未作成だった。
002は旧TRAINERの直接書込みAPIを退役させるため、両アプリとDBの切替を揃える必要がある。今回のローカルテスト成功だけで本番適用済み・実アカウント疎通済みとは扱わない。

## 回帰検証

- `supabase/tests/trainer_client_delivery.sql`：A/B隔離、子行RLS、旧メモ非公開、メニュー／コメント更新、取消復元、公開切替、削除、連携解除、匿名／不正更新拒否、監査、重複なし。
- `supabase/tests/tenant_foundation.sql`：既存テナント権限の回帰。
- `test/trainer_delivery_test.dart`：最新値、同じモデルの全数値、アカウント切替の遅延応答、取消／version確認、取得失敗時の非表示。
- `apps/setkeep_trainer/test/comment_delivery_test.dart`：TRAINERのコメント作成・更新・確認付き削除・旧メモ公開設定維持。
- `integration_test/trainer_delivery_test.dart`：実際のSK WorkoutPageへ遷移して種目ID、セット順、重量、回数、未完了状態を確認。

native UIテストは専用QA端末とfixture repositoryを用い、本番Authへテストデータを送らない。SQL検証はPostgreSQLの隔離DBで実施する。実アカウントを使ったTRAINER登録からSK表示までのネットワーク通し確認とGalaxy／iPhone実機確認は別途必要。
