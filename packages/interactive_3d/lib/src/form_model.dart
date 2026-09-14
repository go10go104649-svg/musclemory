import 'dart:convert';
import 'dart:typed_data';

/// SceneKit's GLTF importer rejects valid custom vertex semantics. Keep the
/// authored GLB (including editable muscle masks) intact and adapt only the
/// in-memory drawing copy. Skin weights, vertex colours and BIN data are kept.
Uint8List prepareFormModelForSceneKit(Uint8List bytes) {
  final header = ByteData.sublistView(bytes);
  if (bytes.length < 28 || header.getUint32(0, Endian.little) != 0x46546c67) {
    throw const FormatException('Form asset is not a binary glTF model');
  }
  final length = header.getUint32(12, Endian.little);
  if (20 + length + 8 > bytes.length ||
      header.getUint32(16, Endian.little) != 0x4e4f534a) {
    throw const FormatException('Form asset has an invalid JSON chunk');
  }
  final document =
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + length))) as Map;
  for (final mesh in document['meshes'] as List) {
    for (final primitive in mesh['primitives'] as List) {
      (primitive['attributes'] as Map).removeWhere(
        (key, _) => key is String && key.startsWith('_MUSCLE_'),
      );
    }
  }
  final json = utf8.encode(jsonEncode(document));
  final paddedLength = (json.length + 3) & ~3;
  final rest = bytes.sublist(20 + length);
  final result = Uint8List(20 + paddedLength + rest.length);
  final resultHeader = ByteData.sublistView(result);
  resultHeader.setUint32(0, 0x46546c67, Endian.little);
  resultHeader.setUint32(4, 2, Endian.little);
  resultHeader.setUint32(8, result.length, Endian.little);
  resultHeader.setUint32(12, paddedLength, Endian.little);
  resultHeader.setUint32(16, 0x4e4f534a, Endian.little);
  result.setRange(20, 20 + json.length, json);
  result.fillRange(20 + json.length, 20 + paddedLength, 0x20);
  result.setRange(20 + paddedLength, result.length, rest);
  return result;
}
