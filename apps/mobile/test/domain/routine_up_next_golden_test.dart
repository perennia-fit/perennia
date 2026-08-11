import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/domain/training/routine_up_next.dart';
import 'package:perennia/domain/training/training_day.dart';

void main() {
  group('Routine up-next derivation', () {
    test('matches the shared routine-up-next golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m34-routine-up-next.json').readAsString(),
      ) as Map<String, Object?>;
      expect(vector['domain'], 'routine-up-next');
      expect(vector['schemaVersion'], 1);
      expect(vector['schema'], 'm34-routine-up-next.schema.json');

      for (final caseObject in vector['cases']! as List<Object?>) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final cadence = _cadenceFrom(input['cadence']! as Map<String, Object?>);
        final entries = (input['entries']! as List<Object?>)
            .map((raw) => _entryFrom(raw! as Map<String, Object?>));
        final links = (input['links']! as List<Object?>)
            .map((raw) => _linkFrom(raw! as Map<String, Object?>));
        final selectedDate =
            TrainingDayDate.parse(input['selectedDate']! as String);

        final actual = deriveRoutineUpNext(
          cadence: cadence,
          entries: entries,
          links: links,
          selectedDate: selectedDate,
        );
        final reason = caseData['name']! as String;

        expect(_suggestionToJson(actual), caseData['expected'], reason: reason);
      }
    });

    test('a rotating Cadence ignores the selected Training Day entirely', () {
      const cadence = Cadence.rotating(3);
      final entries = <UpNextRoutineEntry>[
        const UpNextRoutineEntry(
          routineEntryId: 'entry-2',
          workoutTemplateId: 'template-2',
          templateName: 'Day 2',
          slot: 2,
        ),
      ];
      final links = <UpNextTemplateLinkFact>[
        const UpNextTemplateLinkFact(
          workoutTemplateId: 'template-1',
          slot: 1,
          sequence: 0,
        ),
      ];

      final onMonday = deriveRoutineUpNext(
        cadence: cadence,
        entries: entries,
        links: links,
        selectedDate: TrainingDayDate.parse('2026-07-06'),
      );
      final aMonthLater = deriveRoutineUpNext(
        cadence: cadence,
        entries: entries,
        links: links,
        selectedDate: TrainingDayDate.parse('2026-08-06'),
      );

      expect(_suggestionToJson(onMonday), _suggestionToJson(aMonthLater));
      expect(onMonday?.slot, 2);
    });

    test('a Routine with no active Entries never suggests, regardless of '
        'Cadence', () {
      expect(
        deriveRoutineUpNext(
          cadence: const Cadence.weekly(),
          entries: const <UpNextRoutineEntry>[],
          links: const <UpNextTemplateLinkFact>[],
          selectedDate: TrainingDayDate.parse('2026-07-06'),
        ),
        isNull,
      );
    });
  });
}

Cadence _cadenceFrom(Map<String, Object?> raw) {
  final kind = raw['kind']! as String;
  if (kind == 'weekly') {
    return const Cadence.weekly();
  }
  return Cadence.rotating(raw['window']! as int);
}

UpNextRoutineEntry _entryFrom(Map<String, Object?> raw) {
  return UpNextRoutineEntry(
    routineEntryId: raw['routineEntryId']! as String,
    workoutTemplateId: raw['workoutTemplateId']! as String,
    templateName: raw['templateName']! as String,
    slot: raw['slot']! as int,
  );
}

UpNextTemplateLinkFact _linkFrom(Map<String, Object?> raw) {
  final localDate = raw['workoutLocalDate'] as String?;
  return UpNextTemplateLinkFact(
    workoutTemplateId: raw['workoutTemplateId']! as String,
    slot: raw['slot']! as int,
    sequence: raw['sequence']! as int,
    workoutLocalDate:
        localDate == null ? null : TrainingDayDate.parse(localDate),
  );
}

Object? _suggestionToJson(RoutineUpNextSuggestion? suggestion) {
  if (suggestion == null) {
    return null;
  }
  return <String, Object?>{
    'slot': suggestion.slot,
    'cards': suggestion.cards
        .map(
          (card) => <String, Object?>{
            'routineEntryId': card.routineEntryId,
            'workoutTemplateId': card.workoutTemplateId,
            'templateName': card.templateName,
            'slot': card.slot,
            'isDone': card.isDone,
          },
        )
        .toList(growable: false),
  };
}

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
