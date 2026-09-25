import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/design/app_colors.dart';

(int, int) pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  test('SETKEEP green palette uses the approved brand color', () {
    expect(AppColors.primaryGreen, const Color(0xFFC7F36B));
    expect(AppColors.primaryGreenStrong, const Color(0xFF83AD30));
    expect(AppColors.primaryGreenDeep, const Color(0xFF6B8E23));
    expect(AppColors.primaryGreenSoft, const Color(0xFFE9F4D1));
    expect(AppColors.primaryGreenVerySoft, const Color(0xFFEFF2EA));
  });

  test('launcher icon sets contain the required source dimensions', () {
    expect(
      pngSize(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      ),
      (1024, 1024),
    );
    for (final entry in {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    }.entries) {
      expect(pngSize('android/app/src/main/res/${entry.key}/ic_launcher.png'), (
        entry.value,
        entry.value,
      ));
    }
  });

  test('native splash screens use the app background and SETKEEP artwork', () {
    final android = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final ios = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
        .readAsStringSync();

    expect(android, contains('@color/setkeep_background'));
    expect(android, contains('@drawable/launch_logo'));
    expect(ios, contains('image="LaunchImage"'));
    expect(
      pngSize(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
      ),
      (540, 540),
    );
  });
}
