import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/widgets/protocol_screen.dart';
import 'package:perennia/l10n/l10n.dart';

/// One row of the D5 summary table, with what it reads in each time format.
class _Row {
  const _Row(this.description, this.input, this.at12Hour, this.at24Hour);

  final String description;
  final ScheduleSummaryInput input;
  final String at12Hour;
  final String at24Hour;
}

const _timed = ProtocolScheduleRuleChoice.timed;
const _untimed = ProtocolScheduleRuleChoice.untimed;
const _weekdays = ProtocolScheduleDaysChoice.weekdays;
const _everyN = ProtocolScheduleDaysChoice.everyNDays;

const _table = <_Row>[
  _Row(
    'at set times, every day',
    ScheduleSummaryInput(
      choice: _timed,
      times: <String>['09:00'],
      amount: '5',
      unit: DoseUnit.gram,
    ),
    'Every day · 9:00 AM · 5 g',
    'Every day · 09:00 · 5 g',
  ),
  _Row(
    'at set times, on weekdays, twice',
    ScheduleSummaryInput(
      choice: _timed,
      daysChoice: _weekdays,
      weekdays: <int>[1, 3, 5],
      times: <String>['08:00', '20:00'],
      amount: '2',
      unit: DoseUnit.capsule,
    ),
    'Mon, Wed, Fri · 8:00 AM, 8:00 PM · 2 capsules',
    'Mon, Wed, Fri · 08:00, 20:00 · 2 capsules',
  ),
  _Row(
    'at set times, every 3 days',
    ScheduleSummaryInput(
      choice: _timed,
      daysChoice: _everyN,
      everyN: 3,
      times: <String>['09:00'],
      amount: '250',
      unit: DoseUnit.microgram,
    ),
    'Every 3 days · 9:00 AM · 250 mcg',
    'Every 3 days · 09:00 · 250 mcg',
  ),
  _Row(
    'any time, every day',
    ScheduleSummaryInput(
      choice: _untimed,
      countPerDay: 2,
      amount: '5',
      unit: DoseUnit.gram,
    ),
    'Every day · 2 a day · 5 g',
    'Every day · 2 a day · 5 g',
  ),
  _Row(
    'any time, on weekdays',
    ScheduleSummaryInput(
      choice: _untimed,
      daysChoice: _weekdays,
      weekdays: <int>[1, 3],
      countPerDay: 2,
      amount: '5',
      unit: DoseUnit.gram,
    ),
    'Mon, Wed · 2 a day · 5 g',
    'Mon, Wed · 2 a day · 5 g',
  ),
  _Row(
    'as needed, given an amount',
    ScheduleSummaryInput(
      choice: ProtocolScheduleRuleChoice.asNeeded,
      amount: '5',
      unit: DoseUnit.gram,
    ),
    'As needed · 5 g',
    'As needed · 5 g',
  ),
  _Row(
    'as needed, as the form holds it',
    ScheduleSummaryInput(choice: ProtocolScheduleRuleChoice.asNeeded),
    'As needed',
    'As needed',
  ),
  _Row(
    'no schedule',
    ScheduleSummaryInput(choice: ProtocolScheduleRuleChoice.none),
    'No schedule',
    'No schedule',
  ),
  _Row(
    'at set times, with no amount yet',
    ScheduleSummaryInput(
      choice: _timed,
      times: <String>['09:00'],
      unit: DoseUnit.gram,
    ),
    'Every day · 9:00 AM · Add an amount',
    'Every day · 09:00 · Add an amount',
  ),
  _Row(
    'any time, with no amount yet',
    ScheduleSummaryInput(
      choice: _untimed,
      countPerDay: 1,
      unit: DoseUnit.gram,
    ),
    'Every day · 1 a day · Add an amount',
    'Every day · 1 a day · Add an amount',
  ),
];

void main() {
  late AppLocalizations l10n;
  late MaterialLocalizations material;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const locale = Locale('en');
    l10n = await AppLocalizations.delegate.load(locale);
    material = await GlobalMaterialLocalizations.delegate.load(locale);
  });

  String summary(ScheduleSummaryInput input, {bool use24Hour = false}) {
    return protocolScheduleSummary(
      l10n,
      input,
      material: material,
      localeName: 'en',
      alwaysUse24HourFormat: use24Hour,
    );
  }

  group('the D5 table', () {
    for (final row in _table) {
      test('${row.description}, in a 12-hour format', () {
        expect(summary(row.input), row.at12Hour);
      });
      test('${row.description}, in a 24-hour format', () {
        expect(summary(row.input, use24Hour: true), row.at24Hour);
      });
    }
  });

  group('countable units', () {
    const plurals = <DoseUnit, (String, String)>{
      DoseUnit.tablet: ('tablet', 'tablets'),
      DoseUnit.capsule: ('capsule', 'capsules'),
      DoseUnit.drop: ('drop', 'drops'),
      DoseUnit.spray: ('spray', 'sprays'),
      DoseUnit.puff: ('puff', 'puffs'),
      DoseUnit.patch: ('patch', 'patches'),
      DoseUnit.unit: ('unit', 'units'),
    };

    String amountOf(String amount, DoseUnit unit) {
      return summary(
        ScheduleSummaryInput(
          choice: ProtocolScheduleRuleChoice.asNeeded,
          amount: amount,
          unit: unit,
        ),
      ).replaceFirst('As needed · ', '');
    }

    for (final MapEntry(key: unit, value: (one, many)) in plurals.entries) {
      test('${unit.name} agrees with its amount, shown as entered', () {
        expect(amountOf('1', unit), '1 $one');
        expect(amountOf('2', unit), '2 $many');
        expect(amountOf('1.5', unit), '1.5 $many');
        expect(amountOf('0.5', unit), '0.5 $many');
      });
    }

    test('mass and volume units keep their label at any amount', () {
      expect(amountOf('1', DoseUnit.milligram), '1 mg');
      expect(amountOf('2', DoseUnit.milligram), '2 mg');
      expect(amountOf('2', DoseUnit.internationalUnit), '2 IU');
      expect(amountOf('2', DoseUnit.milliliter), '2 mL');
    });
  });

  group('counts are plurals', () {
    test('one dose a day', () {
      expect(
        summary(
          const ScheduleSummaryInput(
            choice: _untimed,
            countPerDay: 1,
            amount: '5',
            unit: DoseUnit.gram,
          ),
        ),
        'Every day · 1 a day · 5 g',
      );
    });
  });

  group('an unfinished editor still reads', () {
    test('every N with no number yet names the kind of days', () {
      expect(
        summary(
          const ScheduleSummaryInput(
            choice: _timed,
            daysChoice: _everyN,
            times: <String>['09:00'],
            amount: '5',
            unit: DoseUnit.gram,
          ),
        ),
        'Every N days · 9:00 AM · 5 g',
      );
    });

    test('weekdays with none chosen names the kind of days', () {
      expect(
        summary(
          const ScheduleSummaryInput(
            choice: _timed,
            daysChoice: _weekdays,
            times: <String>['09:00'],
            amount: '5',
            unit: DoseUnit.gram,
          ),
        ),
        'Weekdays · 9:00 AM · 5 g',
      );
    });

    test('no times or count leaves that part out', () {
      expect(
        summary(
          const ScheduleSummaryInput(
            choice: _timed,
            amount: '5',
            unit: DoseUnit.gram,
          ),
        ),
        'Every day · 5 g',
      );
      expect(
        summary(
          const ScheduleSummaryInput(
            choice: _untimed,
            amount: '5',
            unit: DoseUnit.gram,
          ),
        ),
        'Every day · 5 g',
      );
    });
  });
}
