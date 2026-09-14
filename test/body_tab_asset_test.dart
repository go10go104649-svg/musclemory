import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_memory/muscle_targets.dart';

void main() {
  test(
    'body asset covers every aggregate region without equipment or animation',
    () {
      final bytes = File('assets/models/body_tab.glb').readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      final length = data.getUint32(12, Endian.little);
      final gltf =
          jsonDecode(utf8.decode(bytes.sublist(20, 20 + length))) as Map;
      expect(gltf['animations'] ?? [], isEmpty);
      expect(gltf['skins'] ?? [], isEmpty);
      expect(gltf['meshes'], hasLength(1));
      expect(gltf['nodes'], hasLength(1));
      final names = (gltf['materials'] as List).map((n) => n['name']).toSet();
      expect(names, {
        'body_neutral',
        ...MuscleRegion.values.map((r) => 'body_${r.name}'),
      });
      expect(bytes.length, lessThan(4500000));
      for (final material in gltf['materials'] as List) {
        final color =
            (material['pbrMetallicRoughness']['baseColorFactor'] ??
                    [1.0, 1.0, 1.0, 1.0])
                as List;
        expect(color[0], lessThanOrEqualTo(color[1]));
        expect(color[1], lessThanOrEqualTo(color[2]));
      }
    },
  );
}
