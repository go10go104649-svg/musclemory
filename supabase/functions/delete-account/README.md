# アカウント削除

Google・メール共通。Premiumに依存しない。端末内の記録は保持する。
`POST /functions/v1/delete-account` は認証済みユーザーのBearerトークンを必須とし、
Authの `/user` で検証した本人だけを管理APIで完全削除する。リクエスト本文のIDは使用しない。
管理キーはEdge Functionの環境変数のみで使用し、アプリへ渡さない。

## 反映前の確認

- サーバー環境の `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_SERVICE_ROLE_KEY` を確認する。キーをソースやチャットに転記しない。
- 対象プロジェクト `meyrtimwibqonozsewbt` には `public.workouts` が存在しないことを確認済み。Functionはこのテーブルを要求しないため、今回は `schema.sql` の適用・DB pushは行わない。将来クラウド保存を開放する際は `workouts.user_id` の `auth.users(id) ON DELETE CASCADE` を確認する。
- 他の外部キーやStorage所有物がある場合、Auth削除が失敗する場合がある。無断で関連データを削除せず、対象を確認する。
- `supabase functions deploy delete-account --project-ref meyrtimwibqonozsewbt --use-api` で反映する。`config.toml` の `verify_jwt = true` でゲートウェイのJWT検証を維持する。
- 2026-09-21: 上記プロジェクトへ反映済み。Function一覧で `ACTIVE`、version 1、`verify_jwt: true` を確認。実機での削除成功・再起動確認は未実施。
- Function反映前はアプリの削除操作が失敗する。アプリ配布前に以下の実機確認を完了する。

## 確認

ローカルのサーバーハンドラテスト（ネットワーク不要）:
`node --test supabase/functions/delete-account/handler_test.mjs`

テスト専用Google・メールアカウントそれぞれで、iOS/Android上から確認する:
1. キャンセルではアカウント・記録・セッションが残る。
2. 確定後にSupabase Authentication Usersから本人が消え、別ユーザーが残る。今回はクラウド記録テーブルがないため、クラウド記録の削除確認は対象外。
3. 端末の記録を保持し、再起動後もログアウト状態になる。
4. Premium権限を持たなくても削除できる。
5. 無効トークンや別ユーザーID指定で他人を削除できない。

Auth削除後も発行済みアクセストークンは期限まで有効になり得る。
このFunctionは毎回Authにユーザーの存在を問い合わせる。既存の他APIの即時失効は保証しない。
削除成功応答を受けたアプリはローカルsignOut後、保存済み認証情報の消去を明示的に待機・確認する。
通信断で削除の応答を受け取れない場合は成功と表示しない。再試行でも確認できなければ、
管理画面でAuthユーザーの有無を確認する必要がある。削除済みなら再ログインはできない。

参考: https://supabase.com/docs/reference/javascript/auth-admin-deleteuser
