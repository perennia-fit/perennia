import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'design_tokens.g.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);
  static ThemeData light() => _build(Brightness.light, AppColors.light);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: DesignTokens.primary,
      onPrimary: DesignTokens.onPrimary,
      secondary: colors.save,
      onSecondary: DesignTokens.onSave,
      error: DesignTokens.destructive,
      onError: DesignTokens.onDestructive,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surface,
      onSurfaceVariant: colors.textSecondary,
      outlineVariant: colors.divider,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      dividerColor: colors.divider,
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      textTheme: buildTextTheme(colors.textPrimary),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        AppTextStyles.tokens,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.chrome,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
    );
  }
}
