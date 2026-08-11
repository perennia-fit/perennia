import 'dart:io';

import 'package:yaml/yaml.dart';

const _outPath = 'lib/theme/design_tokens.g.dart';

const _colorIdents = <String, String>{
  'primary': 'primary',
  'on-primary': 'onPrimary',
  'save': 'save',
  'on-save': 'onSave',
  'destructive': 'destructive',
  'on-destructive': 'onDestructive',
  'record': 'record',
  'on-record': 'onRecord',
  'background-dark': 'backgroundDark',
  'surface-dark': 'surfaceDark',
  'chrome-dark': 'chromeDark',
  'text-primary-dark': 'textPrimaryDark',
  'text-secondary-dark': 'textSecondaryDark',
  'divider-dark': 'dividerDark',
  'background-light': 'backgroundLight',
  'surface-light': 'surfaceLight',
  'chrome-light': 'chromeLight',
  'text-primary-light': 'textPrimaryLight',
  'text-secondary-light': 'textSecondaryLight',
  'divider-light': 'dividerLight',
};

const _typographyOrder = <String, String>{
  'numeral-hero': 'numeralHero',
  'numeral-row': 'numeralRow',
  'h1': 'h1',
  'h2': 'h2',
  'body': 'body',
  'label': 'label',
  'caption': 'caption',
};

void main() {
  final markdown = File('DESIGN.md').readAsStringSync();
  final yaml = loadYaml(_frontMatter(markdown)) as YamlMap;

  final colors = yaml['colors'] as YamlMap;
  final rounded = yaml['rounded'] as YamlMap;
  final spacing = yaml['spacing'] as YamlMap;
  final typography = yaml['typography'] as YamlMap;

  final unmapped = colors.keys
      .cast<String>()
      .where((key) =>
          !_colorIdents.containsKey(key) && !key.startsWith('category-'))
      .toList();
  if (unmapped.isNotEmpty) {
    stderr.writeln(
      'Unmapped color tokens in DESIGN.md: $unmapped\n'
      'Add them to _colorIdents in tool/generate_design_tokens.dart.',
    );
    exit(1);
  }

  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Source of truth : DESIGN.md (YAML front matter).')
    ..writeln('// Regenerate      : dart run tool/generate_design_tokens.dart')
    ..writeln(
        '// Drift guard     : test/theme/design_tokens_test.dart re-parses DESIGN.md and')
    ..writeln('//                   fails if any value below diverges.')
    ..writeln()
    ..writeln("import 'dart:ui';")
    ..writeln()
    ..writeln('class DesignTokens {')
    ..writeln('  DesignTokens._();')
    ..writeln()
    ..writeln('  // ---- colors ----');

  for (final entry in _colorIdents.entries) {
    buffer.writeln(
        '  static const Color ${entry.value} = ${_color(colors[entry.key] as String)};');
  }

  buffer
    ..writeln()
    ..writeln('  // ---- category palette ----')
    ..writeln('  static const Map<String, Color> category = <String, Color>{');
  for (final key in colors.keys
      .cast<String>()
      .where((key) => key.startsWith('category-'))) {
    final name = key.substring('category-'.length);
    buffer.writeln("    '$name': ${_color(colors[key] as String)},");
  }
  buffer.writeln('  };');

  buffer
    ..writeln()
    ..writeln('  // ---- radii (logical px) ----')
    ..writeln('  static const double radiusSm = ${_num(rounded['sm'])};')
    ..writeln('  static const double radiusMd = ${_num(rounded['md'])};')
    ..writeln('  static const double radiusFull = ${_num(rounded['full'])};')
    ..writeln()
    ..writeln('  // ---- spacing (logical px) ----')
    ..writeln('  static const double spacingBase = ${_num(spacing['base'])};')
    ..writeln('  static const double spacingDense = ${_num(spacing['dense'])};')
    ..writeln(
        '  static const double rowHeight = ${_num(spacing['row-height'])};')
    ..writeln(
        '  static const double touchTarget = ${_num(spacing['touch-target'])};')
    ..writeln()
    ..writeln('  // ---- typography ----');

  for (final entry in _typographyOrder.entries) {
    final token = typography[entry.key] as YamlMap;
    buffer.writeln(
        '  static const TokenTextStyle ${entry.value} = ${_tokenStyle(token)};');
  }

  buffer
    ..writeln('}')
    ..writeln()
    ..writeln('class TokenTextStyle {')
    ..writeln(
        '  // Stored for drift checks; platform defaults win in Flutter theme mapping.')
    ..writeln('  final String family;')
    ..writeln('  final double size;')
    ..writeln('  final int weight;')
    ..writeln('  final double height;')
    ..writeln('  final double letterSpacingEm;')
    ..writeln('  final bool tabularFigures;')
    ..writeln()
    ..writeln('  const TokenTextStyle({')
    ..writeln('    required this.family,')
    ..writeln('    required this.size,')
    ..writeln('    required this.weight,')
    ..writeln('    required this.height,')
    ..writeln('    this.letterSpacingEm = 0,')
    ..writeln('    this.tabularFigures = false,')
    ..writeln('  });')
    ..writeln('}');

  File(_outPath).writeAsStringSync(buffer.toString());
  stdout.writeln('Wrote $_outPath');
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

String _color(String hex) {
  final value = hex.replaceAll('#', '').toUpperCase();
  return 'Color(0xFF$value)';
}

String _num(Object? value) {
  if (value is num) {
    return value == value.toInt() ? '${value.toInt()}' : '$value';
  }
  final parsed = double.parse(value.toString().replaceAll('px', '').trim());
  return parsed == parsed.toInt() ? '${parsed.toInt()}' : '$parsed';
}

String _tokenStyle(YamlMap token) {
  final parts = <String>[
    "family: '${token['fontFamily']}'",
    'size: ${_num(token['fontSize'])}',
    'weight: ${token['fontWeight']}',
    'height: ${token['lineHeight']}',
  ];
  final letterSpacing = token['letterSpacing'];
  if (letterSpacing != null) {
    parts.add(
      'letterSpacingEm: ${letterSpacing.toString().replaceAll('em', '').trim()}',
    );
  }
  if (token['fontFeature'] == 'tnum') {
    parts.add('tabularFigures: true');
  }
  return 'TokenTextStyle(${parts.join(', ')})';
}
