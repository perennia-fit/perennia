import 'package:flutter/material.dart';

import 'design_tokens.g.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color save;
  final Color record;
  final Color background;
  final Color surface;
  final Color chrome;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Map<String, Color> category;

  const AppColors({
    required this.save,
    required this.record,
    required this.background,
    required this.surface,
    required this.chrome,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.category,
  });

  static const AppColors dark = AppColors(
    save: DesignTokens.save,
    record: DesignTokens.record,
    background: DesignTokens.backgroundDark,
    surface: DesignTokens.surfaceDark,
    chrome: DesignTokens.chromeDark,
    divider: DesignTokens.dividerDark,
    textPrimary: DesignTokens.textPrimaryDark,
    textSecondary: DesignTokens.textSecondaryDark,
    category: DesignTokens.category,
  );

  static const AppColors light = AppColors(
    save: DesignTokens.save,
    record: DesignTokens.record,
    background: DesignTokens.backgroundLight,
    surface: DesignTokens.surfaceLight,
    chrome: DesignTokens.chromeLight,
    divider: DesignTokens.dividerLight,
    textPrimary: DesignTokens.textPrimaryLight,
    textSecondary: DesignTokens.textSecondaryLight,
    category: DesignTokens.category,
  );

  Color categoryColor(String name) => category[name] ?? category['other']!;

  @override
  AppColors copyWith({
    Color? save,
    Color? record,
    Color? background,
    Color? surface,
    Color? chrome,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Map<String, Color>? category,
  }) {
    return AppColors(
      save: save ?? this.save,
      record: record ?? this.record,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      chrome: chrome ?? this.chrome,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      category: category ?? this.category,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }

    return AppColors(
      save: Color.lerp(save, other.save, t)!,
      record: Color.lerp(record, other.record, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      category: t < 0.5 ? category : other.category,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

Color colorFromHex(String colorHex, {required Color fallback}) {
  final normalized = colorHex.trim().replaceFirst('#', '');
  if (normalized.length != 6) {
    return fallback;
  }
  final value = int.tryParse(normalized, radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}
