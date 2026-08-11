// GENERATED FILE - DO NOT EDIT BY HAND.
//
// Source of truth : DESIGN.md (YAML front matter).
// Regenerate      : dart run tool/generate_design_tokens.dart
// Drift guard     : test/theme/design_tokens_test.dart re-parses DESIGN.md and
//                   fails if any value below diverges.

import 'dart:ui';

class DesignTokens {
  DesignTokens._();

  // ---- colors ----
  static const Color primary = Color(0xFF1FB6CC);
  static const Color onPrimary = Color(0xFF06262B);
  static const Color save = Color(0xFF2FAE8F);
  static const Color onSave = Color(0xFF06262B);
  static const Color destructive = Color(0xFFC9333A);
  static const Color onDestructive = Color(0xFFFFFFFF);
  static const Color record = Color(0xFFE2B53E);
  static const Color onRecord = Color(0xFF06262B);
  static const Color backgroundDark = Color(0xFF14181B);
  static const Color surfaceDark = Color(0xFF1E2428);
  static const Color chromeDark = Color(0xFF101316);
  static const Color textPrimaryDark = Color(0xFFECF1F4);
  static const Color textSecondaryDark = Color(0xFF9AA7AE);
  static const Color dividerDark = Color(0xFF2C343A);
  static const Color backgroundLight = Color(0xFFF2F4F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color chromeLight = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF1A2126);
  static const Color textSecondaryLight = Color(0xFF5B6770);
  static const Color dividerLight = Color(0xFFE3E8EA);

  // ---- category palette ----
  static const Map<String, Color> category = <String, Color>{
    'chest': Color(0xFFE06C5A),
    'back': Color(0xFF4A8FE0),
    'legs': Color(0xFF5FB05C),
    'shoulders': Color(0xFFE0A23F),
    'arms': Color(0xFFA06CD5),
    'core': Color(0xFF3FBFB0),
    'cardio': Color(0xFFE0608F),
    'other': Color(0xFF8A969E),
  };

  // ---- radii (logical px) ----
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusFull = 999;

  // ---- spacing (logical px) ----
  static const double spacingBase = 16;
  static const double spacingDense = 12;
  static const double rowHeight = 48;
  static const double touchTarget = 48;

  // ---- typography ----
  static const TokenTextStyle numeralHero = TokenTextStyle(family: 'Roboto', size: 34, weight: 600, height: 1.1, tabularFigures: true);
  static const TokenTextStyle numeralRow = TokenTextStyle(family: 'Roboto', size: 18, weight: 600, height: 1.3, tabularFigures: true);
  static const TokenTextStyle h1 = TokenTextStyle(family: 'Roboto', size: 22, weight: 600, height: 1.25);
  static const TokenTextStyle h2 = TokenTextStyle(family: 'Roboto', size: 17, weight: 600, height: 1.3);
  static const TokenTextStyle body = TokenTextStyle(family: 'Roboto', size: 15, weight: 400, height: 1.45);
  static const TokenTextStyle label = TokenTextStyle(family: 'Roboto', size: 13, weight: 500, height: 1.3, letterSpacingEm: 0.04);
  static const TokenTextStyle caption = TokenTextStyle(family: 'Roboto', size: 12, weight: 400, height: 1.35);
}

class TokenTextStyle {
  // Stored for drift checks; platform defaults win in Flutter theme mapping.
  final String family;
  final double size;
  final int weight;
  final double height;
  final double letterSpacingEm;
  final bool tabularFigures;

  const TokenTextStyle({
    required this.family,
    required this.size,
    required this.weight,
    required this.height,
    this.letterSpacingEm = 0,
    this.tabularFigures = false,
  });
}
