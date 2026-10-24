import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';

void main() {
  const weekly = Cadence.weekly();
  const rotating3 = Cadence.rotating(3);

  test('cadencesEqual compares kind and window, null included', () {
    expect(cadencesEqual(null, null), isTrue);
    expect(cadencesEqual(weekly, const Cadence.weekly()), isTrue);
    expect(cadencesEqual(rotating3, const Cadence.rotating(3)), isTrue);
    expect(cadencesEqual(rotating3, const Cadence.rotating(4)), isFalse);
    expect(cadencesEqual(weekly, const Cadence.rotating(7)), isFalse);
    expect(cadencesEqual(weekly, null), isFalse);
  });

  test('defaultRoutineEntrySlot fills slots in order and wraps', () {
    expect(
      <int?>[
        for (var p = 0; p < 5; p += 1) defaultRoutineEntrySlot(p, rotating3)
      ],
      <int?>[1, 2, 3, 1, 2],
    );
    expect(defaultRoutineEntrySlot(6, weekly), 7);
    expect(defaultRoutineEntrySlot(7, weekly), 1);
    expect(defaultRoutineEntrySlot(4, null), isNull);
  });

  test('defaultRoutineEntrySlot rejects a Cadence with no slots', () {
    expect(
      () => defaultRoutineEntrySlot(0, const Cadence.rotating(0)),
      throwsStateError,
    );
  });

  test('reconciledRoutineEntrySlot keeps a slot that still fits', () {
    expect(
      reconciledRoutineEntrySlot(3, position: 0, cadence: rotating3),
      3,
    );
    expect(reconciledRoutineEntrySlot(1, position: 5, cadence: weekly), 1);
  });

  test('reconciledRoutineEntrySlot falls back to the default slot', () {
    expect(
      reconciledRoutineEntrySlot(4, position: 4, cadence: rotating3),
      2,
    );
    expect(
      reconciledRoutineEntrySlot(0, position: 0, cadence: rotating3),
      1,
    );
    expect(
      reconciledRoutineEntrySlot(null, position: 2, cadence: weekly),
      3,
    );
    expect(reconciledRoutineEntrySlot(2, position: 0, cadence: null), isNull);
  });
}
