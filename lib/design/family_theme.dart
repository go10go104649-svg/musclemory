import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Brand tokens vary; the family uses the same components and typography.
@immutable
class FamilyPalette extends ThemeExtension<FamilyPalette> {
  const FamilyPalette({
    required this.accent,
    required this.soft,
    required this.subtle,
    required this.background,
    this.assetPrefix = '',
  });
  final Color accent, soft, subtle, background;
  final String assetPrefix;
  static const setkeep = FamilyPalette(
    accent: AppColors.primaryGreen,
    soft: AppColors.primaryGreenSoft,
    subtle: AppColors.primaryGreenVerySoft,
    background: AppColors.background,
  );
  static const trainer = FamilyPalette(
    accent: AppColors.trainerPrimary,
    soft: AppColors.trainerPrimarySoft,
    subtle: AppColors.trainerPrimaryVerySoft,
    background: AppColors.trainerBackground,
    assetPrefix: 'packages/setkeep/',
  );
  static FamilyPalette of(BuildContext context) =>
      Theme.of(context).extension<FamilyPalette>() ?? setkeep;
  @override
  FamilyPalette copyWith({
    Color? accent,
    Color? soft,
    Color? subtle,
    Color? background,
    String? assetPrefix,
  }) => FamilyPalette(
    accent: accent ?? this.accent,
    soft: soft ?? this.soft,
    subtle: subtle ?? this.subtle,
    background: background ?? this.background,
    assetPrefix: assetPrefix ?? this.assetPrefix,
  );
  @override
  FamilyPalette lerp(covariant FamilyPalette? other, double t) => other == null
      ? this
      : FamilyPalette(
          accent: Color.lerp(accent, other.accent, t)!,
          soft: Color.lerp(soft, other.soft, t)!,
          subtle: Color.lerp(subtle, other.subtle, t)!,
          background: Color.lerp(background, other.background, t)!,
          assetPrefix: t < .5 ? assetPrefix : other.assetPrefix,
        );
}

ThemeData familyTheme([
  FamilyPalette palette = FamilyPalette.setkeep,
]) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: palette.accent,
    primary: palette == FamilyPalette.trainer ? palette.accent : AppColors.ink,
    onPrimary: palette == FamilyPalette.trainer ? AppColors.ink : null,
    secondary: palette.accent,
    primaryContainer: palette == FamilyPalette.trainer ? palette.soft : null,
    secondaryContainer: palette == FamilyPalette.trainer ? palette.soft : null,
    tertiary: palette == FamilyPalette.trainer ? palette.accent : null,
    tertiaryContainer: palette == FamilyPalette.trainer ? palette.subtle : null,
    onSecondary: palette == FamilyPalette.trainer
        ? AppColors.trainerDark
        : null,
    surface: palette.background,
  ),
  scaffoldBackgroundColor: palette.background,
  fontFamily: '.SF Pro Display',
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: Colors.white,
  ),
  textButtonTheme: palette == FamilyPalette.trainer
      ? TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.ink),
        )
      : null,
  outlinedButtonTheme: palette == FamilyPalette.trainer
      ? OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink),
        )
      : null,
  extensions: palette == FamilyPalette.setkeep ? const [] : [palette],
  navigationBarTheme: palette == FamilyPalette.trainer
      ? NavigationBarThemeData(indicatorColor: palette.accent)
      : null,
);
