import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// An injectable asset loader keeps the scene format independent from delivery.
/// Today all chunks are bundled; no network or persistent cache is introduced.
Future<Uint8List> loadFormAsset(String path, {AssetBundle? bundle}) async {
  final source = bundle ?? rootBundle;
  // Recipe references are root-relative within the same Flutter package.
  final packagePrefix =
      RegExp(r'^packages/[^/]+/').firstMatch(path)?.group(0) ?? '';

  if (!path.endsWith('.form.json')) {
    final bytes = await source.load(path);
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }
  final recipe =
      jsonDecode(await source.loadString(path)) as Map<String, dynamic>;
  if (recipe['schemaVersion'] != 1) {
    throw const FormatException('Unsupported form recipe');
  }
  final gltf = recipe['gltf'] as Map<String, dynamic>;
  final views = gltf['bufferViews'] as List;
  final chunks = recipe['chunks'] as List;
  if (chunks.length != views.length) {
    throw const FormatException('Incomplete form recipe');
  }
  final binary = BytesBuilder(copy: false);
  final loaded = <String, Uint8List>{};
  for (var i = 0; i < chunks.length; i++) {
    final ref = chunks[i] as Map;
    final asset = ref['path'] as String;
    if (!RegExp(r'^assets/models/form_chunks/[a-f0-9]{64}\.bin$')
        .hasMatch(asset)) {
      throw const FormatException('Invalid form chunk path');
    }
    var data = loaded[asset];
    if (data == null) {
      final value = await source.load('$packagePrefix$asset');
      data = value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
      loaded[asset] = data;
    }
    if (data.length != ref['length'] || data.length != views[i]['byteLength']) {
      throw const FormatException('Incomplete form chunk');
    }
    final padding = (4 - binary.length % 4) % 4;
    binary.add(Uint8List(padding));
    views[i]['buffer'] = 0;
    views[i]['byteOffset'] = binary.length;
    binary.add(data);
  }
  gltf['buffers'] = [
    {'byteLength': binary.length}
  ];
  final json = utf8.encode(jsonEncode(gltf));
  final jsonSize = (json.length + 3) & ~3;
  final binSize = (binary.length + 3) & ~3;
  final result = Uint8List(28 + jsonSize + binSize);
  final header = ByteData.sublistView(result);
  header.setUint32(0, 0x46546c67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, result.length, Endian.little);
  header.setUint32(12, jsonSize, Endian.little);
  header.setUint32(16, 0x4e4f534a, Endian.little);
  result.fillRange(20, 20 + jsonSize, 0x20);
  result.setRange(20, 20 + json.length, json);
  header.setUint32(20 + jsonSize, binSize, Endian.little);
  header.setUint32(24 + jsonSize, 0x004e4942, Endian.little);
  result.setRange(
      28 + jsonSize, 28 + jsonSize + binary.length, binary.takeBytes());
  return result;
}
