import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_3d/src/form_asset_bundle.dart';

class FileBundle extends CachingAssetBundle {
  FileBundle(this.prefix);
  final String prefix;
  final requested = <String>[];
  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    if (!key.startsWith(prefix)) throw StateError('Escaped package scope');
    return ByteData.sublistView(
      await File(key.substring(prefix.length)).readAsBytes(),
    );
  }
}

void main() {
  test(
    'shared form recipes keep every chunk in the consuming package',
    () async {
      final root = FileBundle(''), trainer = FileBundle('packages/setkeep/');
      const path = 'assets/models/forms/seated_leg_curl.form.json';
      final original = await loadFormAsset(path, bundle: root);
      final packaged = await loadFormAsset(
        'packages/setkeep/$path',
        bundle: trainer,
      );
      expect(packaged, orderedEquals(original));
      expect(trainer.requested.length, greaterThan(1));
      expect(
        trainer.requested.every(
          (p) => p.startsWith('packages/setkeep/assets/'),
        ),
        isTrue,
      );
    },
  );
}
