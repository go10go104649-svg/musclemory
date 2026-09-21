import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/config/supabase_config.dart';

void main() {
  const url = 'https://example.supabase.co';

  test('rejects placeholder and invalid header keys without exposing them', () {
    for (final key in [
      'あなたのPublishable Key',
      'your-publishable-key',
      'sb_publishable_test\r\nInjected: value',
      'sb_publishable_test ',
      '',
    ]) {
      expect(
        () => SupabaseConfig.validate(url: url, apiKey: key),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Supabaseの公開キーの設定を確認してください',
          ),
        ),
      );
    }
  });

  test('accepts publishable and legacy JWT key formats', () {
    for (final key in [
      'sb_publishable_test-only',
      'eyJhbGci.eyJyb2xl.signature',
    ]) {
      expect(
        () => SupabaseConfig.validate(url: url, apiKey: key),
        returnsNormally,
      );
    }
  });

  test('rejects invalid project URLs', () {
    for (final url in [
      '',
      'example.supabase.co',
      'ftp://example.supabase.co',
    ]) {
      expect(
        () => SupabaseConfig.validate(url: url, apiKey: 'sb_publishable_test'),
        throwsFormatException,
      );
    }
  });
}
