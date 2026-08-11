import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/analytics/models/lttb_downsampler.dart';

void main() {
  group('lttbDownsample', () {
    test('snapshots caller points when no downsampling is needed', () {
      final source = <int>[1, 2, 3];

      final sampled = lttbDownsample<int>(
        source,
        3,
        xValue: _asDouble,
        yValue: _asDouble,
      );
      source[0] = 99;

      expect(sampled, <int>[1, 2, 3]);
      expect(() => sampled.clear(), throwsUnsupportedError);
      expect(() => sampled[0] = 99, throwsUnsupportedError);
    });

    test('returns immutable snapshots for early-return samples', () {
      final source = <int>[1, 2, 3];

      final empty = lttbDownsample<int>(
        source,
        0,
        xValue: _asDouble,
        yValue: _asDouble,
      );
      final onePoint = lttbDownsample<int>(
        source,
        1,
        xValue: _asDouble,
        yValue: _asDouble,
      );
      final twoPoints = lttbDownsample<int>(
        source,
        2,
        xValue: _asDouble,
        yValue: _asDouble,
      );

      expect(empty, isEmpty);
      expect(onePoint, <int>[1]);
      expect(twoPoints, <int>[1, 3]);
      expect(() => empty.add(1), throwsUnsupportedError);
      expect(() => onePoint[0] = 99, throwsUnsupportedError);
      expect(() => twoPoints[0] = 99, throwsUnsupportedError);
    });

    test('returns an immutable sampled list after downsampling', () {
      final sampled = lttbDownsample<int>(
        <int>[0, 1, 10, 1, 0],
        3,
        xValue: _asDouble,
        yValue: _asDouble,
      );

      expect(sampled, hasLength(3));
      expect(() => sampled.clear(), throwsUnsupportedError);
      expect(() => sampled[0] = 99, throwsUnsupportedError);
    });
  });
}

double _asDouble(int value) => value.toDouble();
