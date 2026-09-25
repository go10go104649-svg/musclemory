import 'package:flutter/material.dart';

/// SETKEEP's shared brand and surface colors.
abstract final class AppColors {
  static const primaryGreen = Color(0xFFC7F36B);
  static const primaryGreenStrong = Color(0xFF83AD30);
  static const primaryGreenDeep = Color(0xFF6B8E23);
  static const primaryGreenSoft = Color(0xFFE9F4D1);
  static const primaryGreenVerySoft = Color(0xFFEFF2EA);

  // TRAINER: the same brand components, with a cyan accent.
  static const trainerPrimary = Color(0xFF38C6FF);
  // Primary composited over white at 20% and 10% opacity.
  static const trainerPrimarySoft = Color(0xFFD7F4FF);
  static const trainerPrimaryVerySoft = Color(0xFFEBF9FF);
  static const trainerDark = Color(0xFF0F1720);
  static const trainerTextPrimary = trainerDark;
  static const trainerBackground = Color(0xFFF3F7FA);

  static const ink = Color(0xFF101820);
  static const background = Color(0xFFF4F5F0);
}
