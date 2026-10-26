import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/effect/effect.dart';
import 'package:perennia/domain/protocols/protocol_plan.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/domain/protocols/protocols.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion` and its schema's constant
/// (packages/golden-vectors/vectors/README.md).
const int _schemaVersion = 1;

/// The shared golden vector for the Protocol Plan core
/// (docs/designs/protocol-schedules-and-reminders.md): the Schedule Rule and
/// Protocol Period codecs, `planDays`, `dayStatuses`, `dueUnfilled` and
/// `effectBoundsFromLocalDates`. The agent API runs the same file
/// (`apps/server/test/protocol-plan.golden.test.mjs`), so the app and an
/// Agent never disagree about what was planned or how it was logged.
void main() {
  final vector = jsonDecode(
    _vectorFile('m36-protocol-plan.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the protocol-plan vector header matches this runner', () {
    expect(vector['name'], 'm36-protocol-plan');
    expect(vector['domain'], 'protocol-plan');
    expect(vector['schemaVersion'], _schemaVersion);
    expect(vector['schema'], 'm36-protocol-plan.schema.json');
    expect(vector['cases'], isNotEmpty);
  });

  group('the Protocol Plan core matches the shared golden vectors', () {
    for (final rawCase in vector['cases']! as List<Object?>) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final name = vectorCase['name']! as String;
      final function = vectorCase['function']! as String;
      test('$function: $name', () {
        final input = vectorCase['input']! as Map<String, Object?>;
        expect(_run(function, input), vectorCase['expected'], reason: name);
      });
    }
  });
}

Object? _run(String function, Map<String, Object?> input) {
  switch (function) {
    case 'rule_codec':
      return _decodeOrRejects(
        () => ScheduleRule.fromJson(input['json']).toJson(),
      );
    case 'period_codec':
      return _decodeOrRejects(
        () => ProtocolPeriod.fromJson(input['json'])?.toJson(),
      );
    case 'plan_days':
      return planDays(
        _list(input['protocols']).map(PlanProtocol.fromJson),
        _date(input['from']),
        _date(input['to']),
      ).map((day) => day.toJson()).toList();
    case 'day_statuses':
      return dayStatuses(
        _list(input['planDays']).map(PlanDay.fromJson),
        _list(input['doses']).map(PlanDose.fromJson),
        _date(input['today']),
      ).map((status) => status.toJson()).toList();
    case 'due_unfilled':
      return dueUnfilled(
        _list(input['dayStatuses']).map(DayStatus.fromJson),
        _date(input['today']),
        input['nowLocalTime']! as String,
      ).map((dose) => dose.toJson()).toList();
    case 'effect_bounds':
      final endLocalDate = input['endLocalDate'] as String?;
      final bounds = effectBoundsFromLocalDates(
        startLocalDate: _date(input['startLocalDate']),
        endLocalDate:
            endLocalDate == null ? null : ProtocolDayDate.parse(endLocalDate),
        timezoneOffsetMinutes: input['timezoneOffsetMinutes']! as int,
      );
      return <String, Object?>{
        'startDate': bounds.startDate.toIso8601String(),
        'endDate': bounds.endDate?.toIso8601String(),
      };
  }
  throw StateError('Unknown protocol-plan function: $function.');
}

Object? _decodeOrRejects(Object? Function() decode) {
  try {
    return decode();
  } on FormatException {
    return const <String, Object?>{'rejects': true};
  }
}

List<Object?> _list(Object? value) => value! as List<Object?>;

ProtocolDayDate _date(Object? value) => ProtocolDayDate.parse(value! as String);

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
