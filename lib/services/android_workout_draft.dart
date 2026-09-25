import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android actions and Flutter use one committed draft. Other platforms retain
/// the existing SharedPreferences path and JSON compatibility.
class AndroidWorkoutDraft {
  static const key = 'active_workout_draft';
  static const channel = MethodChannel('com.setkeep.app/rest_timer');
  static Future<Map<String, String>?> nextTarget(
    String session,
    String exercise,
  ) => channel.invokeMapMethod<String, String>('nextWorkoutTarget', {
    'sessionId': session,
    'exerciseInstanceId': exercise,
  });

  static Future<String?> freezeActions() async {
    if (!Platform.isAndroid) return null;
    return channel.invokeMethod<String>('freezeWorkoutActions');
  }

  static Future<String?> read() async {
    if (Platform.isAndroid) {
      try {
        return await channel.invokeMethod<String>('readWorkoutDraft');
      } on MissingPluginException {
        /* Widget tests have no Android host. */
      }
    }
    return (await SharedPreferences.getInstance()).getString(key);
  }

  static Future<String> write(String value) async {
    if (Platform.isAndroid) {
      try {
        return (await channel.invokeMethod<String>('writeWorkoutDraft', {
          'draft': value,
        }))!;
      } on MissingPluginException {
        /* Widget tests. */
      }
    }
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Workout draft could not be saved');
    }
    return value;
  }

  static Future<void> clear() async {
    if (Platform.isAndroid) {
      try {
        await channel.invokeMethod<void>('clearWorkoutDraft');
        return;
      } on MissingPluginException {
        /* Widget tests. */
      }
    }
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Workout draft could not be removed');
    }
  }
}
