import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/domain/profile/user_profile_validation.dart';

void main() {
  late AppDatabase database;
  late TrainingRepositories repositories;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<UserProfile> read() => repositories.userProfile.watch().first;

  Future<List<UserProfileSectionRow>> rows() {
    return database.select(database.userProfileSections).get();
  }

  Future<void> insertRow({
    required String id,
    required UserProfileSection section,
    required String valuesJson,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    await database.into(database.userProfileSections).insert(
          UserProfileSectionRow(
            id: id,
            section: section.wireName,
            valuesJson: valuesJson,
            syncPreviouslySynced: false,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
          ),
        );
  }

  group('saveSection', () {
    test('a save reaches watch, and the row holds the wire shape', () async {
      final emissions = repositories.userProfile.watch();
      expect((await emissions.first).sex, isNull);

      await repositories.userProfile.saveSection(
        UserProfileSection.aboutYou,
        <String, Object?>{
          'sex': 'female',
          'birth_year': 1990,
          'height':
              const ProfileHeight(value: 66, unit: HeightUnit.inch).toJson(),
        },
      );

      final profile = await read();
      expect(profile.sex, ProfileSex.female);
      expect(profile.birthYear, 1990);
      expect(
        profile.height,
        const ProfileHeight(value: 66, unit: HeightUnit.inch),
      );
      expect(await repositories.userProfile.hasAnySection(), isTrue);
      expect(jsonDecode((await rows()).single.valuesJson), <String, Object?>{
        'sex': 'female',
        'birth_year': 1990,
        'height': <String, Object?>{'value': 66, 'unit': 'in'},
      });
    });

    test('a section with no row is unset, and an empty list is none', () async {
      expect((await read()).goals, isNull);
      expect(await repositories.userProfile.hasAnySection(), isFalse);

      await repositories.userProfile.saveSection(
        UserProfileSection.trainingGoals,
        <String, Object?>{'goals': <String>[]},
      );

      expect((await read()).goals, isEmpty);
      expect(await repositories.userProfile.hasAnySection(), isTrue);
    });

    test('an absent field is kept, null clears, and a list replaces', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingSetup,
        <String, Object?>{
          'equipment': <String>['barbell', 'dumbbell'],
          'days_per_week': 4,
          'session_minutes': 60,
        },
      );

      await repositories.userProfile.saveSection(
        UserProfileSection.trainingSetup,
        <String, Object?>{
          'equipment': <String>['kettlebell'],
          'days_per_week': null,
        },
      );

      final profile = await read();
      expect(profile.equipment, <String>['kettlebell']);
      expect(profile.daysPerWeek, isNull);
      expect(profile.sessionMinutes, 60);
    });

    test('clearing every field keeps the row, with all fields unset', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'Notes'},
      );

      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': null},
      );

      final row = (await rows()).single;
      expect(row.deletedAt, isNull);
      expect((await read()).generalNotesText, isNull);
      expect(await repositories.userProfile.hasAnySection(), isTrue);
    });

    test('a save of nothing on an empty section writes no row', () async {
      for (final (section, changes)
          in <(UserProfileSection, Map<String, Object?>)>[
        (UserProfileSection.aboutYou, const <String, Object?>{}),
        (UserProfileSection.trainingGoals, const {'goals': null}),
        (UserProfileSection.healthLimitations, const {'none': false}),
        (
          UserProfileSection.healthLimitations,
          const {'text': null, 'none': null},
        ),
      ]) {
        await repositories.userProfile.saveSection(section, changes);
      }

      expect(await rows(), isEmpty);
      expect(await repositories.activityLog.listEntriesSince(DateTime(2000)),
          isEmpty);
    });

    test('a hard error throws and writes nothing, naming no value', () async {
      const secret = 'this-text-is-health-data';
      Object? thrown;
      try {
        await repositories.userProfile.saveSection(
          UserProfileSection.healthLimitations,
          <String, Object?>{'text': secret * 100},
        );
      } on UserProfileValidationException catch (error) {
        thrown = error;
      }

      expect(thrown, isA<UserProfileValidationException>());
      expect(thrown.toString(), contains('text.too_long'));
      expect(thrown.toString(), isNot(contains(secret)));
      expect(await rows(), isEmpty);

      await expectLater(
        repositories.userProfile.saveSection(
          UserProfileSection.aboutYou,
          <String, Object?>{'birth_year': DateTime.now().year + 1},
        ),
        throwsA(isA<UserProfileValidationException>()),
      );
      expect(await rows(), isEmpty);
    });

    test('a warning does not block the save', () async {
      final improbable = DateTime.now().year - 110;
      expect(
        validateUserProfileSection(
          UserProfileSection.aboutYou,
          <String, Object?>{'birth_year': improbable},
          referenceYear: DateTime.now().year,
        ).warnings,
        isNotEmpty,
      );

      await repositories.userProfile.saveSection(
        UserProfileSection.aboutYou,
        <String, Object?>{'birth_year': improbable},
      );

      expect((await read()).birthYear, improbable);
    });

    test('Health & limitations normalises in both directions', () async {
      const section = UserProfileSection.healthLimitations;
      await repositories.userProfile.saveSection(
        section,
        <String, Object?>{'text': 'Left knee'},
      );
      expect((await read()).healthText, 'Left knee');
      expect((await read()).healthNone, isFalse);

      await repositories.userProfile.saveSection(
        section,
        <String, Object?>{'none': true},
      );
      expect((await read()).healthText, isNull);
      expect((await read()).healthNone, isTrue);

      await repositories.userProfile.saveSection(
        section,
        <String, Object?>{'text': 'Right knee'},
      );
      expect((await read()).healthText, 'Right knee');
      expect((await read()).healthNone, isFalse);

      await repositories.userProfile.saveSection(
        section,
        <String, Object?>{'text': 'Both', 'none': true},
      );
      expect((await read()).healthText, isNull);
      expect((await read()).healthNone, isTrue);
      expect(
        jsonDecode((await rows()).single.valuesJson),
        <String, Object?>{'text': null, 'none': true},
      );
    });

    test('updates the newest row in place, leaving the older one', () async {
      await insertRow(
        id: 'older',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"older"}',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await insertRow(
        id: 'newer',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"newer"}',
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'edited'},
      );

      final byId = {for (final row in await rows()) row.id: row};
      expect(byId, hasLength(2));
      expect(jsonDecode(byId['older']!.valuesJson), {'text': 'older'});
      expect(jsonDecode(byId['newer']!.valuesJson), {'text': 'edited'});
    });

    test('joins the Batch it is given, with actor user', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'Notes'},
        batchId: 'onboarding-batch',
      );
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingGoals,
        <String, Object?>{
          'goals': <String>['strength']
        },
        batchId: 'onboarding-batch',
      );

      final entries =
          await repositories.activityLog.listEntriesSince(DateTime(2000));
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(entry.batchId, 'onboarding-batch');
        expect(entry.actor, 'user');
        expect(entry.entityTable, AppDatabase.userProfileSectionsTable);
        expect(entry.beforeImage, isNull);
        expect(entry.afterImage!['values'], isA<Map<String, Object?>>());
      }
    });
  });

  group('reads', () {
    test('take the newest live row per section', () async {
      await insertRow(
        id: 'a-newer',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"newer"}',
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      await insertRow(
        id: 'z-older',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"older"}',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await insertRow(
        id: 'tombstoned',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"gone"}',
        updatedAt: DateTime.utc(2026, 1, 3),
        deletedAt: DateTime.utc(2026, 1, 3),
      );
      await insertRow(
        id: 'other-section',
        section: UserProfileSection.trainingGoals,
        valuesJson: '{"goals":["strength"]}',
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final profile = await read();

      expect(profile.generalNotesText, 'newer');
      expect(profile.goals, <TrainingGoalId>[TrainingGoalId.strength]);
    });

    test('a pulled newer row wins over the local one', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'local'},
      );

      await repositories.userProfile.applySyncImage(
        image: <String, Object?>{
          'id': 'pulled',
          'section': 'general_notes',
          'values': <String, Object?>{'text': 'pulled'},
          'updated_at': DateTime.now()
              .toUtc()
              .add(const Duration(days: 1))
              .toIso8601String(),
          'deleted_at': null,
        },
        deviceId: 'device-b',
        batchId: 'pull-batch',
      );

      expect((await read()).generalNotesText, 'pulled');
      expect(await rows(), hasLength(2));
    });

    test('a tie on updated_at resolves to the greater id', () async {
      final stamp = DateTime.utc(2026, 1, 1);
      await insertRow(
        id: 'row-a',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"lesser"}',
        updatedAt: stamp,
      );
      await insertRow(
        id: 'row-b',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"greater"}',
        updatedAt: stamp,
      );

      expect((await read()).generalNotesText, 'greater');
    });

    test('a section with only tombstones reads as no row', () async {
      await insertRow(
        id: 'tombstoned',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"gone"}',
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: DateTime.utc(2026, 1, 1),
      );

      expect((await read()).generalNotes, isNull);
      expect(await repositories.userProfile.hasAnySection(), isFalse);
    });

    test('a row with bad values reads as unset and watch does not throw',
        () async {
      final stamp = DateTime.utc(2026, 1, 1);
      await insertRow(
        id: 'not-json',
        section: UserProfileSection.generalNotes,
        valuesJson: 'not json',
        updatedAt: stamp,
      );
      await insertRow(
        id: 'not-an-object',
        section: UserProfileSection.experience,
        valuesJson: '[1,2]',
        updatedAt: stamp,
      );
      await insertRow(
        id: 'wrong-types',
        section: UserProfileSection.aboutYou,
        valuesJson: '{"sex":"other","birth_year":"1990","height":5}',
        updatedAt: stamp,
      );
      await insertRow(
        id: 'wrong-entries',
        section: UserProfileSection.trainingGoals,
        valuesJson: '{"goals":["strength","unknown",7]}',
        updatedAt: stamp,
      );

      final profile = await read();

      expect(profile.generalNotesText, isNull);
      expect(profile.experienceLevels, isNull);
      expect(profile.sex, isNull);
      expect(profile.birthYear, isNull);
      expect(profile.height, isNull);
      expect(profile.goals, <TrainingGoalId>[TrainingGoalId.strength]);
    });

    test('a save over bad values drops them and keeps working', () async {
      await insertRow(
        id: 'wrong-types',
        section: UserProfileSection.aboutYou,
        valuesJson: '{"sex":"other","birth_year":"1990","height":5}',
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      await repositories.userProfile.saveSection(
        UserProfileSection.aboutYou,
        <String, Object?>{'birth_year': 1990},
      );

      expect(jsonDecode((await rows()).single.valuesJson), <String, Object?>{
        'sex': null,
        'birth_year': 1990,
        'height': null,
      });
    });

    test('ageAt uses the local calendar year at the year boundary', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.aboutYou,
        <String, Object?>{'birth_year': 1990},
      );
      final profile = await read();

      expect(profile.ageAt(DateTime(2026, 12, 31, 23, 59)), 36);
      expect(profile.ageAt(DateTime(2027, 1, 1)), 37);
      // The same instant reads through the device's local time, whichever way
      // it arrives.
      final instant = DateTime(2027, 1, 1);
      expect(profile.ageAt(instant.toUtc()), 37);
    });
  });

  group('applySyncImage', () {
    Map<String, Object?> image(Map<String, Object?> overrides) {
      return <String, Object?>{
        'id': 'pulled',
        'section': 'general_notes',
        'values': <String, Object?>{'text': 'pulled'},
        'updated_at': '2026-01-01T00:00:00.000Z',
        'deleted_at': null,
        ...overrides,
      };
    }

    test('a malformed image raises what the pull quarantines', () async {
      for (final malformed in <Map<String, Object?>>[
        image(const {'values': 'not an object'}),
        image(const {'values': null}),
        image(const {'section': 'not_a_section'}),
        image(const {'section': 7}),
        image(const {'updated_at': 'not a date'}),
      ]) {
        await expectLater(
          repositories.userProfile.applySyncImage(
            image: malformed,
            deviceId: 'device-b',
            batchId: 'pull-batch',
          ),
          throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
          reason: malformed.toString(),
        );
      }
      expect(await rows(), isEmpty);
    });

    test('re-applying the same image appends no Activity Log entry', () async {
      for (var pass = 0; pass < 2; pass += 1) {
        await repositories.userProfile.applySyncImage(
          image: image(const {}),
          deviceId: 'device-b',
          batchId: 'pull-batch',
        );
      }

      final entries = await database.select(database.activityLog).get();
      expect(entries, hasLength(1));
      expect(entries.single.syncAcknowledgedAt, isNotNull);
    });
  });

  group('undo', () {
    test('restores a section from its before-image', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingGoals,
        <String, Object?>{
          'goals': <String>['strength']
        },
      );
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingGoals,
        <String, Object?>{
          'goals': <String>['longevity', 'mobility']
        },
        batchId: 'second',
      );

      final result = await repositories.activityLog.undoBatch('second');

      expect(result.conflicts, isEmpty);
      expect((await read()).goals, <TrainingGoalId>[TrainingGoalId.strength]);
    });

    test('of a first write leaves the section as no row', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'Notes'},
        batchId: 'first',
      );

      final result = await repositories.activityLog.undoBatch('first');

      expect(result.conflicts, isEmpty);
      expect((await read()).generalNotes, isNull);
      expect(await repositories.userProfile.hasAnySection(), isFalse);
    });

    test('is refused after an intervening change', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'first'},
        batchId: 'first',
      );
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'second'},
      );

      final result = await repositories.activityLog.undoBatch('first');

      expect(result.undoBatchId, isNull);
      expect(result.conflicts, hasLength(1));
      expect(
        result.conflicts.single.reason,
        ActivityLogUndoConflictReason.stale,
      );
      expect((await read()).generalNotesText, 'second');
    });

    test('of a whole Batch is refused if one of its sections changed',
        () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.generalNotes,
        <String, Object?>{'text': 'notes'},
        batchId: 'batch',
      );
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingSetup,
        <String, Object?>{'days_per_week': 4},
        batchId: 'batch',
      );
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingSetup,
        <String, Object?>{'days_per_week': 5},
      );

      final result = await repositories.activityLog.undoBatch('batch');

      expect(result.conflicts, hasLength(1));
      expect((await read()).generalNotesText, 'notes');
      expect((await read()).daysPerWeek, 5);
    });

    test(
        'works on a pulled row whose height is an integer in JSON and whose '
        'after-image carries milliseconds', () async {
      const beforeImage = <String, Object?>{
        'id': 'pulled',
        'section': 'about_you',
        'values': <String, Object?>{
          'sex': null,
          'birth_year': null,
          'height': <String, Object?>{'value': 170, 'unit': 'cm'},
        },
        'updated_at': '2026-01-01T00:00:00.000Z',
        'deleted_at': null,
      };
      // What the device logged for what it wrote: the same height as a double.
      const afterImage = <String, Object?>{
        'id': 'pulled',
        'section': 'about_you',
        'values': <String, Object?>{
          'sex': null,
          'birth_year': null,
          'height': <String, Object?>{'value': 66.0, 'unit': 'in'},
        },
        'updated_at': '2026-01-02T00:00:00.123Z',
        'deleted_at': null,
      };
      await repositories.userProfile.applySyncImage(
        image: const <String, Object?>{
          'id': 'pulled',
          'section': 'about_you',
          'values': <String, Object?>{
            'sex': null,
            'birth_year': null,
            'height': <String, Object?>{'value': 66, 'unit': 'in'},
          },
          'updated_at': '2026-01-02T00:00:00.123Z',
          'deleted_at': null,
        },
        deviceId: 'agent:key-1',
        batchId: 'agent-batch',
        actor: 'agent:key-1',
        activityBeforeImage: beforeImage,
        activityAfterImage: afterImage,
      );

      final result = await repositories.activityLog.undoBatch('agent-batch');

      expect(result.conflicts, isEmpty);
      expect(
        (await read()).height,
        const ProfileHeight(value: 170, unit: HeightUnit.cm),
      );
    });
  });

  group('portable archive', () {
    Future<List<int>> archiveWith(
      DateTime updatedAt,
      String text,
    ) async {
      final source = AppDatabase.inMemory();
      addTearDown(source.close);
      await source.into(source.userProfileSections).insert(
            UserProfileSectionRow(
              id: 'shared',
              section: UserProfileSection.generalNotes.wireName,
              valuesJson: jsonEncode(<String, Object?>{'text': text}),
              syncPreviouslySynced: false,
              updatedAt: updatedAt,
            ),
          );
      return TrainingRepositories(source)
          .portableArchives
          .exportPortableArchive();
    }

    test('round trips into an empty database', () async {
      await repositories.userProfile.saveSection(
        UserProfileSection.trainingGoals,
        <String, Object?>{
          'goals': <String>['strength']
        },
      );
      final archive =
          await repositories.portableArchives.exportPortableArchive();

      final restored = AppDatabase.inMemory();
      addTearDown(restored.close);
      final restoredRepositories = TrainingRepositories(restored);
      final result = await restoredRepositories.portableArchives
          .importPortableArchive(archive);

      expect(
        result.changedRowsByTable[AppDatabase.userProfileSectionsTable],
        1,
      );
      expect(
        (await restoredRepositories.userProfile.watch().first).goals,
        <TrainingGoalId>[TrainingGoalId.strength],
      );
    });

    test('an import never removes a local row, and the newer row wins',
        () async {
      await insertRow(
        id: 'local-only',
        section: UserProfileSection.trainingGoals,
        valuesJson: '{"goals":["mobility"]}',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await insertRow(
        id: 'shared',
        section: UserProfileSection.generalNotes,
        valuesJson: '{"text":"local"}',
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      await repositories.portableArchives.importPortableArchive(
        await archiveWith(DateTime.utc(2026, 1, 1), 'older in archive'),
      );
      expect((await read()).generalNotesText, 'local');

      await repositories.portableArchives.importPortableArchive(
        await archiveWith(DateTime.utc(2026, 1, 3), 'newer in archive'),
      );
      expect((await read()).generalNotesText, 'newer in archive');
      expect((await read()).goals, <TrainingGoalId>[TrainingGoalId.mobility]);
      expect(await rows(), hasLength(2));
    });
  });
}
