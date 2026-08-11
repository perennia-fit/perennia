import 'package:flutter/material.dart';

import 'design_tokens.g.dart';

FontWeight _weight(int weight) {
  final index = ((weight ~/ 100) - 1).clamp(0, FontWeight.values.length - 1).toInt();
  return FontWeight.values[index];
}

TextStyle tokenToTextStyle(TokenTextStyle token, {Color? color}) {
  return TextStyle(
    fontSize: token.size,
    height: token.height,
    fontWeight: _weight(token.weight),
    letterSpacing: token.letterSpacingEm == 0
        ? null
        : token.letterSpacingEm * token.size,
    fontFeatures: token.tabularFigures
        ? const <FontFeature>[FontFeature.tabularFigures()]
        : null,
    color: color,
  );
}

@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  final TextStyle numeralHero;
  final TextStyle numeralRow;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle body;
  final TextStyle label;
  final TextStyle caption;

  const AppTextStyles({
    required this.numeralHero,
    required this.numeralRow,
    required this.h1,
    required this.h2,
    required this.body,
    required this.label,
    required this.caption,
  });

  static final AppTextStyles tokens = AppTextStyles(
    numeralHero: tokenToTextStyle(DesignTokens.numeralHero),
    numeralRow: tokenToTextStyle(DesignTokens.numeralRow),
    h1: tokenToTextStyle(DesignTokens.h1),
    h2: tokenToTextStyle(DesignTokens.h2),
    body: tokenToTextStyle(DesignTokens.body),
    label: tokenToTextStyle(DesignTokens.label),
    caption: tokenToTextStyle(DesignTokens.caption),
  );

  @override
  AppTextStyles copyWith({
    TextStyle? numeralHero,
    TextStyle? numeralRow,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? body,
    TextStyle? label,
    TextStyle? caption,
  }) {
    return AppTextStyles(
      numeralHero: numeralHero ?? this.numeralHero,
      numeralRow: numeralRow ?? this.numeralRow,
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      body: body ?? this.body,
      label: label ?? this.label,
      caption: caption ?? this.caption,
    );
  }

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) {
      return this;
    }

    return AppTextStyles(
      numeralHero: TextStyle.lerp(numeralHero, other.numeralHero, t)!,
      numeralRow: TextStyle.lerp(numeralRow, other.numeralRow, t)!,
      h1: TextStyle.lerp(h1, other.h1, t)!,
      h2: TextStyle.lerp(h2, other.h2, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
    );
  }
}

TextTheme buildTextTheme(Color onSurface) {
  return TextTheme(
    headlineSmall: tokenToTextStyle(DesignTokens.h1, color: onSurface),
    titleMedium: tokenToTextStyle(DesignTokens.h2, color: onSurface),
    bodyMedium: tokenToTextStyle(DesignTokens.body, color: onSurface),
    labelLarge: tokenToTextStyle(DesignTokens.label, color: onSurface),
    bodySmall: tokenToTextStyle(DesignTokens.caption, color: onSurface),
  );
}

extension AppTextStylesX on BuildContext {
  AppTextStyles get textStyles => Theme.of(this).extension<AppTextStyles>()!;
}
