# 報告管理

マイページの「報告管理」は `app_admins` に登録したログインユーザーのみ表示される。
登録・解除は信頼されたDB管理者がSupabase管理環境で行う。アプリからの自己登録は不可。
メールによるクライアント判定やサービスキーは使用しない。

- 初期表示: 対応種目 / 未確認。設備情報へ切替可能。
- 件数は選択した報告種類全体、検索は店舗名・種目名・設備名が対象。
- 50件単位で取得。新しい順。同じ状態へのメモ保存も可能。
- 未確認 → 確認中 → 反映済み / 却下。未確認からの却下も可能。
- 却下はメモ必須。反映済み・却下は確認ダイアログあり。
- マスターを手動で確認・修正してから反映済みにする。状態変更だけではマスターを更新しない。
- 同時編集で状態が変わっていた場合は更新を拒否。戻って再読み込みする。
- 設備報告の既存 approved は reviewing、resolved は applied に移行。
- 管理更新はstatus/admin_noteのみ許可。reviewed_by/reviewed_atはDBトリガーで設定。
- 管理者登録はローカルmigrationへ個人情報を含めず、環境ごとに行う。

検証:

```
flutter test --no-pub test/report_management_test.dart test/private_place_equipment_test.dart test/gym_integration_test.dart
flutter analyze --no-pub
supabase db query --linked --file supabase/tests/report_admin.sql
supabase db query --linked --file supabase/tests/private_place_equipment.sql
```

SQLテストは仮ユーザー・店舗をトランザクション内に作り、最後にrollbackする。
実際の報告や店舗設備を変更しない。Android/iOSのWidgetテストと実機確認は別扱い。
