# SETKEEP TRAINER

SETKEEPと同一リポジトリ・同一Supabase Authを使う独立したiOS / Androidアプリ。
アプリIDは両OSとも `com.setkeep.trainer`。一般版 `com.setkeep.app` と同時にインストールできます。

リポジトリ直下の `supabase.example.json` を参考に、共通プロジェクトの公開接続設定を `supabase.json` に用意してください。

```sh
cd apps/setkeep_trainer
flutter pub get
flutter run --dart-define-from-file=../../supabase.json
flutter analyze
flutter test
```

接続設定を省略すると設定案内画面が起動します。サーバー障害時にプロフィール登録済みと誤認しないよう、読み込み失敗と未登録を区別しています。

既存アカウントでログイン → トレーナープロフィール作成 → 招待発行 → 一般版で本人承認 → 顧客を開く、という順番で確認できます。

詳細な実装・DB・権限・実機確認手順は [開発ガイド](../../docs/setkeep_trainer.md) を参照してください。
