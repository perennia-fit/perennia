import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/common/local_clock.dart';

/// `localDateAtOffset`, the single rule that writes `meals.local_date`
/// (docs/designs/meal-logging.md §1). Every device-zone assertion computes its
/// expectation from `DateTime.toLocal()`, so the tests hold in whatever zone
/// they run in.
void main() {
  group('localDateAtOffset with an explicit offset', () {
    test('+840 moves an instant forward a day', () {
      expect(
        localDateAtOffset(DateTime.utc(2026, 3, 10, 10, 30), 840),
        (year: 2026, month: 3, day: 11),
      );
    });

    test('-720 moves an instant back a day', () {
      expect(
        localDateAtOffset(DateTime.utc(2026, 3, 10, 11, 30), -720),
        (year: 2026, month: 3, day: 9),
      );
    });

    test('0 reads the UTC date either side of midnight', () {
      expect(
        localDateAtOffset(DateTime.utc(2026, 3, 10, 23, 59, 59), 0),
        (year: 2026, month: 3, day: 10),
      );
      expect(
        localDateAtOffset(DateTime.utc(2026, 3, 11), 0),
        (year: 2026, month: 3, day: 11),
      );
    });

    test('crosses a month and a year boundary', () {
      expect(
        localDateAtOffset(DateTime.utc(2026, 12, 31, 20), 300),
        (year: 2027, month: 1, day: 1),
      );
      expect(
        localDateAtOffset(DateTime.utc(2026, 3, 1, 2), -180),
        (year: 2026, month: 2, day: 28),
      );
    });

    test('does not depend on whether the instant is UTC or local', () {
      final utc = DateTime.utc(2026, 3, 10, 10, 30);
      expect(
        localDateAtOffset(utc.toLocal(), 840),
        localDateAtOffset(utc, 840),
      );
    });

    test('is the date of clockAtOffset', () {
      final instant = DateTime.utc(2026, 6, 1, 22, 15);
      final clock = clockAtOffset(instant, 120);
      expect(clock.isUtc, isTrue);
      expect(clock.hour, 0);
      expect(
        localDateAtOffset(instant, 120),
        (year: clock.year, month: clock.month, day: clock.day),
      );
    });
  });

  group('localDateAtOffset with a null offset', () {
    test('uses the device zone', () {
      for (final instant in <DateTime>[
        DateTime.utc(2026, 1, 15, 0, 30),
        DateTime.utc(2026, 1, 15, 23, 30),
        DateTime.utc(2026, 7, 15, 0, 30),
        DateTime.utc(2026, 7, 15, 23, 30),
      ]) {
        final local = instant.toLocal();
        expect(
          localDateAtOffset(instant, null),
          (year: local.year, month: local.month, day: local.day),
          reason: instant.toIso8601String(),
        );
      }
    });
  });

  group('the frozen offset across a daylight-saving change', () {
    // The frozen offset is the device zone's offset at the Meal's own
    // instant, not at the moment of logging: a summer Meal back-filled in
    // winter keeps the summer offset and stays on its own day.
    int frozenOffsetMinutes(DateTime startedAt) =>
        startedAt.toLocal().timeZoneOffset.inMinutes;

    test('a summer instant read in winter keeps its own offset and day', () {
      // Just after local midnight in July: if the winter offset were used
      // in a zone whose clocks go back for winter, the Meal would fall on
      // the previous day.
      final summer = DateTime(2026, 7, 16, 0, 30);
      final winterNow = DateTime(2026, 1, 15, 12);

      final offset = frozenOffsetMinutes(summer);
      expect(offset, summer.timeZoneOffset.inMinutes);
      final winterOffset = winterNow.toLocal().timeZoneOffset.inMinutes;
      if (winterOffset != summer.timeZoneOffset.inMinutes) {
        expect(offset, isNot(winterOffset));
      }

      expect(
        localDateAtOffset(summer, offset),
        (year: 2026, month: 7, day: 16),
      );
      expect(
        localDateAtOffset(summer.toUtc(), offset),
        (year: summer.year, month: summer.month, day: summer.day),
      );
    });

    test('a winter instant read in summer keeps its own offset and day', () {
      final winter = DateTime(2026, 1, 16, 0, 30);
      final summerNow = DateTime(2026, 7, 15, 12);

      final offset = frozenOffsetMinutes(winter);
      expect(offset, winter.timeZoneOffset.inMinutes);
      final summerOffset = summerNow.toLocal().timeZoneOffset.inMinutes;
      if (summerOffset != winter.timeZoneOffset.inMinutes) {
        expect(offset, isNot(summerOffset));
      }

      expect(
        localDateAtOffset(winter.toUtc(), offset),
        (year: 2026, month: 1, day: 16),
      );
    });
  });
}
