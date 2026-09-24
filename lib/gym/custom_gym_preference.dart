import 'dart:convert';
import 'dart:math';

import 'gym_repository.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const standardGyms = ['自宅', 'エニタイムフィットネス', 'ゴールドジム', 'FIT PLACE24'];

List<String> decodeCustomGyms(Object? source) {
  if (source is! List<dynamic>) return [];
  final unique = <String, String>{};
  for (final item in source.whereType<String>()) {
    final name = item.trim();
    if (name.isEmpty || standardGyms.contains(name)) continue;
    unique.putIfAbsent(name.toLowerCase(), () => name);
  }
  return unique.values.toList(growable: false);
}

class CustomGymPreference {
  CustomGymPreference._();

  static const _storageKey = 'custom_gyms';
  static List<String> gyms = [];
  static Map<String, String> _ids = {};
  static String? idFor(String name) => _ids[name];
  static String newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static Future<void> _saveIds() async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setString('custom_place_ids_v1', jsonEncode(_ids))) {
      throw StateError('場所IDを保存できませんでした');
    }
  }

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedIds = preferences.getString('custom_place_ids_v1');
    _ids = encodedIds == null
        ? {}
        : Map<String, String>.from(jsonDecode(encodedIds) as Map);
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      gyms = [];
      return;
    }
    try {
      gyms = decodeCustomGyms(jsonDecode(encoded));
      for (final name in gyms) {
        _ids.putIfAbsent(name, newId);
      }
      await _saveIds();
    } catch (_) {
      gyms = [];
    }
  }

  static bool contains(String name, {String? excludingName}) {
    final normalized = name.trim().toLowerCase();
    return standardGyms.any((item) => item.toLowerCase() == normalized) ||
        gyms.any(
          (item) => item != excludingName && item.toLowerCase() == normalized,
        );
  }

  static Future<bool> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || standardGyms.contains(trimmed)) return false;
    if (gyms.any((item) => item.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    await replaceAll([...gyms, trimmed]);
    return true;
  }

  static Future<bool> update(String originalName, String updatedName) async {
    final trimmed = updatedName.trim();
    if (trimmed.isEmpty || contains(trimmed, excludingName: originalName)) {
      return false;
    }
    if (!gyms.contains(originalName)) return false;
    final id = _ids.remove(originalName);
    if (id != null) _ids[trimmed] = id;
    await replaceAll(
      gyms.map((item) => item == originalName ? trimmed : item).toList(),
    );
    return true;
  }

  static Future<void> remove(String name) async {
    final id = _ids[name];
    if (id != null) await GymServices.repository.deletePrivateEquipment(id);
    _ids.remove(name);
    await replaceAll(gyms.where((item) => item != name).toList());
  }

  static Future<void> replaceAll(List<String> updated) async {
    gyms = decodeCustomGyms(updated);
    for (final name in gyms) {
      _ids.putIfAbsent(name, newId);
    }
    await _saveIds();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(gyms));
  }
}

Future<String?> addCustomGym(BuildContext context) async {
  final name = await showCustomGymDialog(context);
  if (name == null) return null;
  return await CustomGymPreference.add(name) ? name : null;
}

Future<String?> showCustomGymDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CustomGymDialog(initialName: initialName),
  );
}

class _CustomGymDialog extends StatefulWidget {
  const _CustomGymDialog({this.initialName});

  final String? initialName;

  @override
  State<_CustomGymDialog> createState() => _CustomGymDialogState();
}

class _CustomGymDialogState extends State<_CustomGymDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialName == null ? '場所を追加' : '場所名を変更'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('customGymNameField'),
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return '場所の名前を入力してください';
            if (CustomGymPreference.contains(
              name,
              excludingName: widget.initialName,
            )) {
              return '同じ名前の場所があります';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: '場所の名前',
            hintText: '例：近所の体育館',
          ),
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveCustomGymButton'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
