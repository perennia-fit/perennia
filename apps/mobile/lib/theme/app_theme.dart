import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_text_styles.dart';
import 'design_tokens.g.dart';

/// The filled button that saves or finishes: Log set, Update, the Finish
/// summary's Done.
ButtonStyle saveButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: context.colors.save,
    foregroundColor: Theme.of(context).colorScheme.onSecondary,
    minimumSize: const Size.fromHeight(AppDimens.rowHeight),
  );
}

/// [saveButtonStyle] in a form: the Profile editor's Save, onboarding's actions,
/// Workout capture's Save. Its corners match the form's fields.
ButtonStyle saveFormButtonStyle(BuildContext context) {
  return saveButtonStyle(context).copyWith(
    shape: const WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
    ),
  );
}

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
      // Material 3 draws selection (chips, the navigation indicator, tonal
      // buttons) in secondaryContainer, which would otherwise fall back to
      // the Save teal. DESIGN.md makes selection Signal Cyan, so it is a cyan
      // tint over the surface, with primary text on it.
      secondaryContainer: Color.alphaBlend(
        DesignTokens.primary.withValues(alpha: 0.22),
        colors.surface,
      ),
      onSecondaryContainer: colors.textPrimary,
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
      // A selected tile reads from its check or trailing mark; tinting its
      // label Signal Cyan would fall below AA contrast on the light ground.
      listTileTheme: ListTileThemeData(selectedColor: colors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.chrome,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      snackBarTheme: _noticeTheme(),
    );
  }

  /// The DESIGN.md `notice` component. The bar is dark in both themes because
  /// one colour pair then passes AA in both; Signal Cyan on a light bar is
  /// about 2.4:1 and would need a new token.
  static SnackBarThemeData _noticeTheme() {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DesignTokens.chromeDark,
      contentTextStyle: AppTextStyles.tokens.body.copyWith(
        color: DesignTokens.textPrimaryDark,
      ),
      actionTextColor: DesignTokens.primary,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.cardMd,
        side: BorderSide(color: DesignTokens.dividerDark),
      ),
      insetPadding: const EdgeInsets.all(AppDimens.base),
      elevation: 0,
    );
  }
}
