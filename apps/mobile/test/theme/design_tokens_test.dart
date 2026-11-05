import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/theme/app_theme.dart';
import 'package:perennia/theme/design_tokens.g.dart';
import 'package:yaml/yaml.dart';

void main() {
  final yaml =
      loadYaml(_frontMatter(File('DESIGN.md').readAsStringSync())) as YamlMap;
  final colors = yaml['colors'] as YamlMap;
  final components = yaml['components'] as YamlMap;
  final rounded = yaml['rounded'] as YamlMap;
  final spacing = yaml['spacing'] as YamlMap;
  final typography = yaml['typography'] as YamlMap;

  Color hex(String key) {
    final value = (colors[key] as String).replaceAll('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  double px(Object? value) {
    return double.parse(value.toString().replaceAll('px', '').trim());
  }

  group('design tokens match DESIGN.md', () {
    test('colors', () {
      expect(DesignTokens.primary, hex('primary'));
      expect(DesignTokens.onPrimary, hex('on-primary'));
      expect(DesignTokens.save, hex('save'));
      expect(DesignTokens.onSave, hex('on-save'));
      expect(DesignTokens.destructive, hex('destructive'));
      expect(DesignTokens.onDestructive, hex('on-destructive'));
      expect(DesignTokens.record, hex('record'));
      expect(DesignTokens.onRecord, hex('on-record'));
      expect(DesignTokens.backgroundDark, hex('background-dark'));
      expect(DesignTokens.surfaceDark, hex('surface-dark'));
      expect(DesignTokens.chromeDark, hex('chrome-dark'));
      expect(DesignTokens.textPrimaryDark, hex('text-primary-dark'));
      expect(DesignTokens.textSecondaryDark, hex('text-secondary-dark'));
      expect(DesignTokens.dividerDark, hex('divider-dark'));
      expect(DesignTokens.backgroundLight, hex('background-light'));
      expect(DesignTokens.surfaceLight, hex('surface-light'));
      expect(DesignTokens.chromeLight, hex('chrome-light'));
      expect(DesignTokens.textPrimaryLight, hex('text-primary-light'));
      expect(DesignTokens.textSecondaryLight, hex('text-secondary-light'));
      expect(DesignTokens.dividerLight, hex('divider-light'));
    });

    test('category palette', () {
      for (final name in const [
        'chest',
        'back',
        'legs',
        'shoulders',
        'arms',
        'core',
        'cardio',
        'other',
      ]) {
        expect(DesignTokens.category[name], hex('category-$name'),
            reason: name);
      }

      final designCategories = colors.keys
          .cast<String>()
          .where((key) => key.startsWith('category-'))
          .map((key) => key.substring('category-'.length))
          .toSet();
      expect(DesignTokens.category.keys.toSet(), designCategories);
    });

    test('radii and spacing', () {
      expect(DesignTokens.radiusSm, px(rounded['sm']));
      expect(DesignTokens.radiusMd, px(rounded['md']));
      expect(DesignTokens.radiusFull, px(rounded['full']));
      expect(DesignTokens.spacingBase, px(spacing['base']));
      expect(DesignTokens.spacingDense, px(spacing['dense']));
      expect(DesignTokens.rowHeight, px(spacing['row-height']));
      expect(DesignTokens.touchTarget, px(spacing['touch-target']));
    });

    test('Progress components', () {
      final statusIcon = components['status-icon'] as YamlMap;
      final legendIcon = components['legend-icon'] as YamlMap;
      final trainedDaysCell = components['trained-days-cell'] as YamlMap;
      expect(DesignTokens.statusIconSize, px(statusIcon['size']));
      expect(DesignTokens.legendIconSize, px(legendIcon['size']));
      expect(DesignTokens.trainedDaysCellSize, px(trainedDaysCell['size']));
      expect(DesignTokens.trainedDaysCellGap, px(trainedDaysCell['gap']));
      expect(
        DesignTokens.trainedDaysFillOpacity,
        px(trainedDaysCell['fillOpacity']),
      );
      final sparkline = components['progress-sparkline'] as YamlMap;
      expect(DesignTokens.progressSparklineHeight, px(sparkline['height']));
      expect(
        DesignTokens.progressSparklinePointRadius,
        px(sparkline['pointRadius']),
      );
      expect(
        DesignTokens.progressSparklineRingWidth,
        px(sparkline['ringWidth']),
      );
      expect(
        DesignTokens.progressSparklineLineWidth,
        px(sparkline['lineWidth']),
      );
    });

    test('notice component', () {
      final notice = components['notice'] as YamlMap;
      Color color(String key) => _resolveColor(notice[key] as String, colors);

      expect(notice['typography'], '{typography.body}');

      final radius = px(rounded[_tokenKey(notice['rounded'] as String)]);
      final inset = px(spacing[_tokenKey(notice['inset'] as String)]);

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final reason = theme.brightness.name;
        final snackBar = theme.snackBarTheme;
        expect(snackBar.backgroundColor, color('backgroundColor'),
            reason: reason);
        expect(snackBar.actionTextColor, color('actionColor'), reason: reason);
        expect(snackBar.contentTextStyle?.color, color('textColor'),
            reason: reason);
        expect(snackBar.contentTextStyle?.fontSize, DesignTokens.body.size,
            reason: reason);

        final shape = snackBar.shape;
        expect(shape, isA<RoundedRectangleBorder>(), reason: reason);
        final rectangle = shape as RoundedRectangleBorder;
        expect(rectangle.borderRadius, BorderRadius.circular(radius),
            reason: reason);
        expect(rectangle.side.color, color('borderColor'), reason: reason);
        expect(rectangle.side.width, 1, reason: reason);

        expect(snackBar.insetPadding, EdgeInsets.all(inset), reason: reason);
        expect(snackBar.behavior, SnackBarBehavior.floating, reason: reason);
        expect(snackBar.elevation, 0, reason: reason);
      }
    });

    test('typography', () {
      void check(TokenTextStyle style, String key) {
        final token = typography[key] as YamlMap;
        expect(style.family, token['fontFamily'], reason: '$key family');
        expect(style.size, px(token['fontSize']), reason: '$key size');
        expect(style.weight, token['fontWeight'], reason: '$key weight');
        expect(style.height, (token['lineHeight'] as num).toDouble(),
            reason: '$key height');

        final letterSpacing = token['letterSpacing'];
        final expectedLetterSpacing = letterSpacing == null
            ? 0.0
            : double.parse(
                letterSpacing.toString().replaceAll('em', '').trim());
        expect(style.letterSpacingEm, expectedLetterSpacing,
            reason: '$key letterSpacing');
        expect(style.tabularFigures, token['fontFeature'] == 'tnum',
            reason: '$key tnum');
      }

      check(DesignTokens.numeralHero, 'numeral-hero');
      check(DesignTokens.numeralRow, 'numeral-row');
      check(DesignTokens.h1, 'h1');
      check(DesignTokens.h2, 'h2');
      check(DesignTokens.body, 'body');
      check(DesignTokens.label, 'label');
      check(DesignTokens.caption, 'caption');
    });
  });

  group('WCAG AA contrast', () {
    const aa = 4.5;

    test('dark theme', () {
      expect(_ratio(DesignTokens.textPrimaryDark, DesignTokens.backgroundDark),
          greaterThanOrEqualTo(aa));
      expect(_ratio(DesignTokens.textPrimaryDark, DesignTokens.surfaceDark),
          greaterThanOrEqualTo(aa));
      expect(
          _ratio(DesignTokens.textSecondaryDark, DesignTokens.backgroundDark),
          greaterThanOrEqualTo(aa));
      expect(_ratio(DesignTokens.textSecondaryDark, DesignTokens.surfaceDark),
          greaterThanOrEqualTo(aa));
    });

    test('light theme', () {
      expect(
          _ratio(DesignTokens.textPrimaryLight, DesignTokens.backgroundLight),
          greaterThanOrEqualTo(aa));
      expect(_ratio(DesignTokens.textPrimaryLight, DesignTokens.surfaceLight),
          greaterThanOrEqualTo(aa));
      expect(
          _ratio(DesignTokens.textSecondaryLight, DesignTokens.backgroundLight),
          greaterThanOrEqualTo(aa));
      expect(_ratio(DesignTokens.textSecondaryLight, DesignTokens.surfaceLight),
          greaterThanOrEqualTo(aa));
    });

    test('on primary', () {
      expect(_ratio(DesignTokens.onPrimary, DesignTokens.primary),
          greaterThanOrEqualTo(aa));
    });

    test('action colors', () {
      expect(_ratio(DesignTokens.onSave, DesignTokens.save),
          greaterThanOrEqualTo(aa));
      expect(_ratio(DesignTokens.onDestructive, DesignTokens.destructive),
          greaterThanOrEqualTo(aa));
      expect(_ratio(DesignTokens.onRecord, DesignTokens.record),
          greaterThanOrEqualTo(aa));
    });

    test('action components use AA token pairs', () {
      void checkComponent(String key) {
        final component = components[key] as YamlMap;
        final background =
            _resolveColor(component['backgroundColor'] as String, colors);
        final foreground =
            _resolveColor(component['textColor'] as String, colors);

        expect(_ratio(foreground, background), greaterThanOrEqualTo(aa),
            reason: key);
      }

      checkComponent('button-save');
      checkComponent('button-destructive');
    });

    test('notice', () {
      final notice = components['notice'] as YamlMap;
      final background =
          _resolveColor(notice['backgroundColor'] as String, colors);
      final text = _resolveColor(notice['textColor'] as String, colors);
      final action = _resolveColor(notice['actionColor'] as String, colors);

      expect(_ratio(text, background), greaterThanOrEqualTo(aa));
      expect(_ratio(action, background), greaterThanOrEqualTo(aa));
    });
  });
}

String _frontMatter(String markdown) {
  final lines = markdown.split('\n');
  final fences = <int>[];
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].trim() == '---') {
      fences.add(index);
      if (fences.length == 2) {
        break;
      }
    }
  }
  if (fences.length < 2) {
    throw StateError('DESIGN.md is missing YAML front matter fences.');
  }
  return lines.sublist(fences[0] + 1, fences[1]).join('\n');
}

double _channel(int value) {
  final normalized = value / 255.0;
  return normalized <= 0.03928
      ? normalized / 12.92
      : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final red = (color.r * 255.0).round();
  final green = (color.g * 255.0).round();
  final blue = (color.b * 255.0).round();
  return 0.2126 * _channel(red) +
      0.7152 * _channel(green) +
      0.0722 * _channel(blue);
}

double _ratio(Color a, Color b) {
  final luminanceA = _luminance(a);
  final luminanceB = _luminance(b);
  final lighter = math.max(luminanceA, luminanceB);
  final darker = math.min(luminanceA, luminanceB);
  return (lighter + 0.05) / (darker + 0.05);
}

/// The token name in a reference such as `{rounded.md}`.
String _tokenKey(String ref) {
  return ref.substring(ref.indexOf('.') + 1, ref.length - 1);
}

Color _resolveColor(String value, YamlMap colors) {
  final tokenRef = RegExp(r'^\{colors\.([^}]+)\}$').firstMatch(value);
  final colorValue =
      tokenRef == null ? value : colors[tokenRef.group(1)!] as String;
  final hex = colorValue.replaceAll('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}
