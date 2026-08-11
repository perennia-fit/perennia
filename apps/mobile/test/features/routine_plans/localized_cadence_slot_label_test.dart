import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/features/routine_plans/widgets/localized_cadence_slot_label.dart';
import 'package:perennia/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('localizedCadenceSlotLabel', () {
    test('localizes the first and last weekly slots', () {
      expect(
        localizedCadenceSlotLabel(
          l10n,
          kind: CadenceKind.weekly,
          slot: 1,
        ),
        'Monday',
      );
      expect(
        localizedCadenceSlotLabel(
          l10n,
          kind: CadenceKind.weekly,
          slot: 7,
        ),
        'Sunday',
      );
    });

    test('localizes a rotating slot by its position', () {
      expect(
        localizedCadenceSlotLabel(
          l10n,
          kind: CadenceKind.rotating,
          slot: 3,
        ),
        'Position 3',
      );
    });

    test('rejects weekly slots outside the one-based weekday range', () {
      for (final slot in <int>[0, 8]) {
        expect(
          () => localizedCadenceSlotLabel(
            l10n,
            kind: CadenceKind.weekly,
            slot: slot,
          ),
          throwsRangeError,
          reason: 'weekly slot $slot must not be treated as Sunday',
        );
      }
    });
  });
}
