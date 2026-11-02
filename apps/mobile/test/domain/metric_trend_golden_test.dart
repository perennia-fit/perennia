import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/metrics/metric_trend.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion` and its schema's constant
/// (packages/golden-vectors/vectors/README.md).
const int _schemaVersion = 1;

/// The shared golden vector for the Trend core
/// (docs/designs/progress-overview.md, D5): `metricTrend`. The agent API runs
/// the same file (`apps/server/test/metric-trend.golden.test.mjs`), so the
/// Body card and an Agent's `trendValue` never disagree.
void main() {
  final vector = jsonDecode(
    _vectorFile('m37-metric-trend.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the metric-trend vector header matches this runner', () {
    expect(vector['name'], 'm37-metric-trend');
    expect(vector['domain'], 'metric-trend');
    expect(vector['schemaVersion'], _schemaVersion);
    expect(vector['schema'], 'm37-metric-trend.schema.json');
    expect(vector['tolerance'], 1e-9);
    expect(vector['cases'], isNotEmpty);
  });

  // `trend` is compared within the file's tolerance, because pow can differ
  // in the last bit between Dart and JavaScript; everything else exactly.
  final tolerance = (vector['tolerance']! as num).toDouble();

  group('the Trend core matches the shared golden vectors', () {
    for (final rawCase in vector['cases']! as List<Object?>) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final name = vectorCase['name']! as String;
      final function = vectorCase['function']! as String;
      test('$function: $name', () {
        final input = vectorCase['input']! as Map<String, Object?>;
        final actual = _run(function, input);
        final expected = _list(vectorCase['expected'])
            .map((raw) => raw! as Map<String, Object?>)
            .toList();

        expect(
          actual.map(_pointWithoutTrend).toList(),
          expected
              .map((point) => Map<String, Object?>.of(point)..remove('trend'))
              .toList(),
          reason: name,
        );
        for (var index = 0; index < actual.length; index += 1) {
          expect(
            actual[index].trend,
            closeTo((expected[index]['trend']! as num).toDouble(), tolerance),
            reason: '$name: point $index',
          );
        }
      });
    }
  });

  // Not vector cases: trendChange is Dart only (D5).
  group('trendChange', () {
    final start = DateTime.utc(2026, 10, 5);
    final end = DateTime.utc(2026, 10, 12);

    test('subtracts the Trend at the last point before the period', () {
      final points = metricTrend(<TrendInput>[
        _reading('r1', DateTime.utc(2026, 10, 3, 7), 80),
        _reading('r2', DateTime.utc(2026, 10, 4, 7), 81),
        _reading('r3', DateTime.utc(2026, 10, 6, 7), 82),
        _reading('r4', DateTime.utc(2026, 10, 9, 7), 79),
        _reading('r5', DateTime.utc(2026, 10, 13, 7), 90),
      ]);

      // r5 is after the period and does not count.
      expect(
        trendChange(points, start, end),
        closeTo(points[3].trend - points[1].trend, 1e-12),
      );
    });

    test('uses the first point in the period with none before it', () {
      final points = metricTrend(<TrendInput>[
        _reading('r1', DateTime.utc(2026, 10, 6, 7), 80),
        _reading('r2', DateTime.utc(2026, 10, 7, 7), 82),
        _reading('r3', DateTime.utc(2026, 10, 8, 7), 81),
      ]);

      expect(
        trendChange(points, start, end),
        closeTo(points[2].trend - points[0].trend, 1e-12),
      );
    });

    test('is null when the period has no point', () {
      final points = metricTrend(<TrendInput>[
        _reading('r1', DateTime.utc(2026, 10, 1, 7), 80),
        _reading('r2', end, 82),
      ]);

      expect(trendChange(points, start, end), isNull);
      expect(trendChange(const <TrendPoint>[], start, end), isNull);
    });

    test('a Reading exactly at start is in the period, not before it', () {
      final points = metricTrend(<TrendInput>[
        _reading('r1', DateTime.utc(2026, 10, 1, 7), 80),
        _reading('r2', start, 84),
        _reading('r3', DateTime.utc(2026, 10, 7, 7), 83),
      ]);

      expect(
        trendChange(points, start, end),
        closeTo(points[2].trend - points[0].trend, 1e-12),
      );

      final onlyAtStart = metricTrend(<TrendInput>[_reading('r1', start, 84)]);
      expect(trendChange(onlyAtStart, start, end), 0);
    });
  });
}

List<TrendPoint> _run(String function, Map<String, Object?> input) {
  switch (function) {
    case 'metric_trend':
      return metricTrend(_list(input['readings']).map(_inputFrom));
  }
  throw StateError('Unknown metric-trend function: $function.');
}

TrendInput _inputFrom(Object? raw) {
  final map = raw! as Map<String, Object?>;
  return TrendInput(
    id: map['id']! as String,
    at: DateTime.parse(map['at']! as String),
    value: _valueFrom(map['value']),
  );
}

/// JSON has no non-finite numbers, so the vector spells them as strings.
double? _valueFrom(Object? value) {
  return switch (value) {
    null => null,
    final num number => number.toDouble(),
    'NaN' => double.nan,
    'Infinity' => double.infinity,
    '-Infinity' => double.negativeInfinity,
    _ => throw StateError('Malformed reading value: $value.'),
  };
}

Map<String, Object?> _pointWithoutTrend(TrendPoint point) => <String, Object?>{
      'id': point.id,
      'at': point.at.toIso8601String(),
      'value': point.value,
    };

TrendInput _reading(String id, DateTime at, double value) =>
    TrendInput(id: id, at: at, value: value);

List<Object?> _list(Object? value) => value! as List<Object?>;

File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors'
      '${Platform.pathSeparator}$name',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Golden vector not found: $name.');
}
