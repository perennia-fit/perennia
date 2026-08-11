import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/energy_balance.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

/// A complete energy-in total derived over `Food Entry`s for a day.
NutrientTotal _energyIn(double value, {bool isComplete = true}) {
  return NutrientTotal(
    id: NutrientId.energy,
    value: value,
    unit: NutrientUnit.kilocalorie,
    isComplete: isComplete,
  );
}

void main() {
  group('EnergyBalance.derive', () {
    test('computes the net on demand as energy-in minus energy-out', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        energyIn: _energyIn(2100),
        energyOut: 2600,
      );

      // The two sides are read from independent sources; the net is computed
      // here, never stored.
      expect(balance.status, EnergyBalanceStatus.computed);
      expect(balance.energyInValue, 2100);
      expect(balance.energyOutValue, 2600);
      expect(balance.net, 2100 - 2600);
      expect(balance.isDeficit, isTrue);
      expect(balance.isSurplus, isFalse);
      expect(balance.isIndeterminate, isFalse);
    });

    test('reports a surplus when energy-in exceeds energy-out', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        energyIn: _energyIn(3000),
        energyOut: 2200,
      );

      expect(balance.net, 800);
      expect(balance.isSurplus, isTrue);
      expect(balance.isDeficit, isFalse);
    });

    test('a complete zero energy-in is a known value, never treated as '
        'unknown (0 ≠ unknown)', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        energyIn: _energyIn(0),
        energyOut: 2600,
      );

      expect(balance.status, EnergyBalanceStatus.computed);
      expect(balance.energyInValue, 0);
      expect(balance.net, -2600);
      expect(balance.isIndeterminate, isFalse);
    });

    test('is indeterminate when the in-side is incomplete — never an implicit '
        'zero in the subtraction', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        // A contributing Food Entry lacked an energy value.
        energyIn: _energyIn(1800, isComplete: false),
        energyOut: 2600,
      );

      expect(balance.status, EnergyBalanceStatus.indeterminate);
      expect(balance.isIndeterminate, isTrue);
      // No net is fabricated and the incomplete in-value is withheld.
      expect(balance.net, isNull);
      expect(balance.energyInValue, isNull);
      // The known out-side is still surfaced.
      expect(balance.energyOutValue, 2600);
      expect(balance.energyInKnown, isFalse);
      expect(balance.energyOutKnown, isTrue);
    });

    test('is indeterminate when the out-side is missing — a day with no '
        'calories-burned Reading is unknown, not an implicit zero', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        energyIn: _energyIn(2100),
        energyOut: null,
      );

      expect(balance.status, EnergyBalanceStatus.indeterminate);
      expect(balance.isIndeterminate, isTrue);
      expect(balance.net, isNull);
      // The known in-side is still surfaced for legibility.
      expect(balance.energyInValue, 2100);
      expect(balance.energyOutValue, isNull);
      expect(balance.energyInKnown, isTrue);
      expect(balance.energyOutKnown, isFalse);
    });

    test('is indeterminate when both sides are unknown', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        energyIn: _energyIn(0, isComplete: false),
        energyOut: null,
      );

      expect(balance.status, EnergyBalanceStatus.indeterminate);
      expect(balance.net, isNull);
      expect(balance.energyInKnown, isFalse);
      expect(balance.energyOutKnown, isFalse);
    });

    test('carries the energy units of both sides so the read is legible', () {
      final balance = EnergyBalance.derive(
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
        energyIn: _energyIn(2100),
        energyOut: 2600,
      );

      // Both sides are energy (kcal); the net shares the unit.
      expect(balance.unit, NutrientUnit.kilocalorie);
    });

    test('preserves the local date the two sides were aligned on', () {
      const date = NutritionDayDate(year: 2026, month: 6, day: 26);
      final balance = EnergyBalance.derive(
        localDate: date,
        energyIn: _energyIn(2100),
        energyOut: 2600,
      );

      expect(balance.localDate, date);
    });
  });
}
