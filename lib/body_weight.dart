import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum BodyWeightPeriod {
  oneMonth('1ヶ月', 1),
  threeMonths('3ヶ月', 3),
  sixMonths('6ヶ月', 6),
  oneYear('1年', 12);

  const BodyWeightPeriod(this.label, this.months);

  final String label;
  final int months;
}

class BodyWeightEntry {
  const BodyWeightEntry({
    required this.id,
    required this.recordedAt,
    required this.weightKg,
  });

  final String id;
  final DateTime recordedAt;
  final double weightKg;

  BodyWeightEntry copyWith({DateTime? recordedAt, double? weightKg}) {
    return BodyWeightEntry(
      id: id,
      recordedAt: recordedAt ?? this.recordedAt,
      weightKg: weightKg ?? this.weightKg,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'recordedAt': recordedAt.toIso8601String(),
    'weightKg': weightKg,
  };

  static BodyWeightEntry? tryFromJson(Object? source) {
    if (source is! Map) return null;
    final recordedAt = DateTime.tryParse(source['recordedAt'] as String? ?? '');
    final weight = (source['weightKg'] as num?)?.toDouble();
    if (recordedAt == null || weight == null || weight <= 0) return null;
    final id = source['id'] as String?;
    return BodyWeightEntry(
      id: id?.isNotEmpty == true
          ? id!
          : '${recordedAt.toIso8601String()}_${weight.toStringAsFixed(3)}',
      recordedAt: recordedAt,
      weightKg: weight,
    );
  }
}

List<BodyWeightEntry> sortBodyWeights(Iterable<BodyWeightEntry> entries) {
  final sorted = entries.toList();
  sorted.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  return sorted;
}

List<BodyWeightEntry> bodyWeightsForPeriod(
  Iterable<BodyWeightEntry> entries,
  BodyWeightPeriod period, {
  DateTime? now,
}) {
  final end = now ?? DateTime.now();
  final cutoff = DateTime(
    end.year,
    end.month - period.months,
    end.day,
    end.hour,
    end.minute,
    end.second,
  );
  return sortBodyWeights(
    entries.where(
      (entry) =>
          !entry.recordedAt.isBefore(cutoff) && !entry.recordedAt.isAfter(end),
    ),
  );
}

class BodyWeightPreference {
  BodyWeightPreference._();

  static const storageKey = 'body_weight_entries';

  static Future<List<BodyWeightEntry>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey);
    if (encoded == null) return [];
    try {
      final source = jsonDecode(encoded);
      if (source is! List) return [];
      return sortBodyWeights(
        source.map(BodyWeightEntry.tryFromJson).whereType<BodyWeightEntry>(),
      );
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(Iterable<BodyWeightEntry> entries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode(
        sortBodyWeights(entries).map((entry) => entry.toJson()).toList(),
      ),
    );
  }
}
