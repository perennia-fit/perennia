import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/domain/profile/user_profile_validation.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion`, its schema's constant and the TypeScript runner's
/// (packages/golden-vectors/vectors/README.md).
const int userProfileValidationGoldenSchemaVersion = 1;

UserProfileValidationResult _validate(
  UserProfileSection section,
  Map<String, Object?> values,
) {
  return validateUserProfileSection(section, values, referenceYear: 2026);
}

void main() {
  // The server runs the same vector through validateUserProfileSection
  // (apps/server/test/agent-validation.golden.test.mjs), so the app and an agent
  // judge a section alike.
  group('m41 golden vector', () {
    final vector = jsonDecode(
      _vectorFile('m41-user-profile-validation.json').readAsStringSync(),
    ) as Map<String, Object?>;

    test('names its schema, and its limits are the constants', () {
      expect(vector['name'], 'm41-user-profile-validation');
      expect(vector['domain'], 'user-profile-validation');
      expect(vector['schemaVersion'], userProfileValidationGoldenSchemaVersion);
      expect(vector['schema'], 'm41-user-profile-validation.schema.json');
      expect(vector['limits'], <String, Object?>{
        'birthYearMaxAgeYears':
            UserProfileValidationLimits.birthYearMaxAgeYears,
        'birthYearWarnMinAgeYears':
            UserProfileValidationLimits.birthYearWarnMinAgeYears,
        'birthYearWarnMaxAgeYears':
            UserProfileValidationLimits.birthYearWarnMaxAgeYears,
        'heightMaxCentimetres':
            UserProfileValidationLimits.heightMaxCentimetres,
        'heightWarnMinCentimetres':
            UserProfileValidationLimits.heightWarnMinCentimetres,
        'heightWarnMaxCentimetres':
            UserProfileValidationLimits.heightWarnMaxCentimetres,
        'heightUnits': UserProfileValidationLimits.heightUnits,
        'cmPerInch': UserProfileValidationLimits.cmPerInch,
        'daysPerWeekMin': UserProfileValidationLimits.daysPerWeekMin,
        'daysPerWeekMax': UserProfileValidationLimits.daysPerWeekMax,
        'sessionMinutesMin': UserProfileValidationLimits.sessionMinutesMin,
        'sessionMinutesMax': UserProfileValidationLimits.sessionMinutesMax,
        'sessionMinutesWarnMax':
            UserProfileValidationLimits.sessionMinutesWarnMax,
        'equipmentIdMaxLength':
            UserProfileValidationLimits.equipmentIdMaxLength,
        'healthLimitationsTextMaxLength':
            UserProfileValidationLimits.healthLimitationsTextMaxLength,
        'generalNotesTextMaxLength':
            UserProfileValidationLimits.generalNotesTextMaxLength,
        'trainingGoalIds': UserProfileValidationLimits.trainingGoalIds,
        'sexes': UserProfileValidationLimits.sexes,
        'experienceLevels': UserProfileValidationLimits.experienceLevels,
      });
    });

    test('every case gets the expected verdict and rules', () {
      final cases = vector['cases']! as List<Object?>;
      expect(cases, isNotEmpty);
      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final name = caseData['name']! as String;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;

        final result = validateUserProfileSection(
          UserProfileSection.fromWireName(input['section'])!,
          input['values']! as Map<String, Object?>,
          referenceYear: input['referenceYear']! as int,
        );

        expect(result.accepted, expected['accepted'], reason: name);
        expect(
          [for (final error in result.errors) error.rule],
          expected['errorRules'],
          reason: name,
        );
        expect(
          [for (final warning in result.warnings) warning.rule],
          expected['warningRules'],
          reason: name,
        );
      }
    });
  });

  group('messages that carry a value', () {
    test('birth_year.improbable_age names the age', () {
      final result = _validate(
        UserProfileSection.aboutYou,
        <String, Object?>{'birth_year': 1915},
      );
      expect(
        result.warnings.single.message,
        'That makes you 111. Check the birth year.',
      );
    });

    test('height.improbable has no trailing .0', () {
      expect(
        _validate(
          UserProfileSection.aboutYou,
          <String, Object?>{
            'height': <String, Object?>{'value': 110.0, 'unit': 'cm'},
          },
        ).warnings.single.message,
        'A height of 110 cm is unusual. Check it.',
      );
      expect(
        _validate(
          UserProfileSection.aboutYou,
          <String, Object?>{
            'height': <String, Object?>{'value': 47.2, 'unit': 'in'},
          },
        ).warnings.single.message,
        'A height of 47.2 in is unusual. Check it.',
      );
    });

    test('text.too_long names the limit in plain digits', () {
      expect(
        _validate(
          UserProfileSection.healthLimitations,
          <String, Object?>{'text': 'h' * 1001, 'none': false},
        ).errors.single.message,
        'Keep this under 1000 characters.',
      );
      expect(
        _validate(
          UserProfileSection.generalNotes,
          <String, Object?>{'text': 'n' * 2001},
        ).errors.single.message,
        'Keep this under 2000 characters.',
      );
    });
  });

  test('throwIfRejected raises on a hard reject, not on a warning', () {
    expect(
      () => _validate(
        UserProfileSection.trainingSetup,
        <String, Object?>{'days_per_week': 8},
      ).throwIfRejected(),
      throwsA(isA<UserProfileValidationException>()),
    );
    _validate(
      UserProfileSection.trainingSetup,
      <String, Object?>{'session_minutes': 241},
    ).throwIfRejected();
  });

  group('mergeUserProfileSectionValues', () {
    test('a field absent from the save is unchanged', () {
      expect(
        mergeUserProfileSectionValues(
          UserProfileSection.aboutYou,
          <String, Object?>{'sex': 'male', 'birth_year': 1988},
          <String, Object?>{'birth_year': 1990},
        ),
        <String, Object?>{'sex': 'male', 'birth_year': 1990, 'height': null},
      );
    });

    test('a field given as null is cleared', () {
      expect(
        mergeUserProfileSectionValues(
          UserProfileSection.aboutYou,
          <String, Object?>{'sex': 'male', 'birth_year': 1988},
          <String, Object?>{'sex': null},
        ),
        <String, Object?>{'sex': null, 'birth_year': 1988, 'height': null},
      );
    });

    test('a list replaces the whole list', () {
      expect(
        mergeUserProfileSectionValues(
          UserProfileSection.trainingSetup,
          <String, Object?>{
            'equipment': <String>['dumbbell', 'barbell'],
            'days_per_week': 4,
          },
          <String, Object?>{
            'equipment': <String>['rope'],
          },
        ),
        <String, Object?>{
          'equipment': <String>['rope'],
          'days_per_week': 4,
          'session_minutes': null,
        },
      );
    });

    test('an empty list is kept as the none choice', () {
      final merged = mergeUserProfileSectionValues(
        UserProfileSection.trainingGoals,
        const <String, Object?>{},
        <String, Object?>{'goals': <String>[]},
      );
      expect(merged, <String, Object?>{'goals': <String>[]});
      expect(
        isUserProfileSectionUnset(UserProfileSection.trainingGoals, merged),
        isFalse,
      );
    });

    group('Health & limitations normalisation', () {
      const section = UserProfileSection.healthLimitations;

      test('setting text turns none off', () {
        expect(
          mergeUserProfileSectionValues(
            section,
            <String, Object?>{'text': null, 'none': true},
            <String, Object?>{'text': 'Left knee'},
          ),
          <String, Object?>{'text': 'Left knee', 'none': false},
        );
      });

      test('setting none clears the text', () {
        expect(
          mergeUserProfileSectionValues(
            section,
            <String, Object?>{'text': 'Left knee', 'none': false},
            <String, Object?>{'none': true},
          ),
          <String, Object?>{'text': null, 'none': true},
        );
      });

      test('none: true wins over text in the same save', () {
        expect(
          mergeUserProfileSectionValues(
            section,
            const <String, Object?>{},
            <String, Object?>{'text': 'Left knee', 'none': true},
          ),
          <String, Object?>{'text': null, 'none': true},
        );
      });

      test('an explicit none: null means false', () {
        expect(
          mergeUserProfileSectionValues(
            section,
            <String, Object?>{'text': null, 'none': true},
            <String, Object?>{'none': null},
          ),
          <String, Object?>{'text': null, 'none': false},
        );
      });

      test('clearing the text leaves none as it was', () {
        expect(
          mergeUserProfileSectionValues(
            section,
            <String, Object?>{'text': 'Left knee', 'none': false},
            <String, Object?>{'text': null},
          ),
          <String, Object?>{'text': null, 'none': false},
        );
      });
    });

    test('merges over the tolerantly read values', () {
      expect(
        mergeUserProfileSectionValues(
          UserProfileSection.aboutYou,
          <String, Object?>{'sex': 'other', 'birth_year': '1990', 'height': 12},
          <String, Object?>{'birth_year': 1990},
        ),
        <String, Object?>{'sex': null, 'birth_year': 1990, 'height': null},
      );
    });

    test('keeps a field this build does not know', () {
      expect(
        mergeUserProfileSectionValues(
          UserProfileSection.generalNotes,
          <String, Object?>{'text': 'a', 'written_by': 'a newer build'},
          <String, Object?>{'text': 'b'},
        ),
        <String, Object?>{'text': 'b', 'written_by': 'a newer build'},
      );
    });

    test('refuses a change to a field the section does not have', () {
      expect(
        () => mergeUserProfileSectionValues(
          UserProfileSection.aboutYou,
          const <String, Object?>{},
          <String, Object?>{'birthYear': 1990},
        ),
        throwsArgumentError,
      );
    });
  });

  group('isUserProfileSectionUnset', () {
    test('every field null is unset', () {
      for (final section in UserProfileSection.values) {
        expect(
          isUserProfileSectionUnset(section, <String, Object?>{
            for (final field in section.fieldNames) field: null,
          }),
          isTrue,
          reason: section.wireName,
        );
      }
    });

    test('none: false with text: null is unset, none: true is not', () {
      const section = UserProfileSection.healthLimitations;
      expect(
        isUserProfileSectionUnset(
          section,
          <String, Object?>{'none': false, 'text': null},
        ),
        isTrue,
      );
      expect(
        isUserProfileSectionUnset(
          section,
          <String, Object?>{'none': true, 'text': null},
        ),
        isFalse,
      );
    });

    test('the none lists are not unset', () {
      expect(
        isUserProfileSectionUnset(
          UserProfileSection.experience,
          <String, Object?>{'levels': <Object?>[]},
        ),
        isFalse,
      );
      expect(
        isUserProfileSectionUnset(
          UserProfileSection.trainingSetup,
          <String, Object?>{'equipment': <Object?>[]},
        ),
        isFalse,
      );
    });
  });

  group('tolerant fromJson', () {
    test('a field of the wrong JSON type reads as unset and never throws', () {
      final aboutYou = AboutYouValues.fromJson(<String, Object?>{
        'sex': 12,
        'birth_year': '1990',
        'height': <String, Object?>{'value': 'tall', 'unit': 'cm'},
      });
      expect(aboutYou.sex, isNull);
      expect(aboutYou.birthYear, isNull);
      expect(aboutYou.height, isNull);

      final setup = TrainingSetupValues.fromJson(<String, Object?>{
        'equipment': 'dumbbell',
        'days_per_week': 2.5,
        'session_minutes': true,
      });
      expect(setup.equipment, isNull);
      expect(setup.daysPerWeek, isNull);
      expect(setup.sessionMinutes, isNull);

      expect(
        TrainingGoalsValues.fromJson(<String, Object?>{'goals': 'strength'})
            .goals,
        isNull,
      );
      expect(
        ExperienceValues.fromJson(<String, Object?>{'levels': 3}).levels,
        isNull,
      );
      expect(
        GeneralNotesValues.fromJson(<String, Object?>{'text': 12}).text,
        isNull,
      );
      final health = HealthLimitationsValues.fromJson(
        <String, Object?>{'text': false, 'none': 'yes'},
      );
      expect(health.text, isNull);
      expect(health.none, isFalse);
    });

    test('an unknown enum value reads as unset', () {
      expect(
        AboutYouValues.fromJson(<String, Object?>{'sex': 'other'}).sex,
        isNull,
      );
      expect(
        ProfileHeight.fromJson(<String, Object?>{'value': 180, 'unit': 'ft'}),
        isNull,
      );
    });

    test('an unknown goal is dropped, and the others kept', () {
      expect(
        TrainingGoalsValues.fromJson(<String, Object?>{
          'goals': <Object?>['strength', 'world_domination', 3],
        }).goals,
        <TrainingGoalId>[TrainingGoalId.strength],
      );
    });

    test('an unknown level is dropped, and the others kept', () {
      expect(
        ExperienceValues.fromJson(<String, Object?>{
          'levels': <Object?>[
            <String, Object?>{'focus_id': 'a', 'level': 'elite'},
            <String, Object?>{'focus_id': 'b', 'level': 'advanced'},
            'beginner',
          ],
        }).levels,
        <ExperienceEntry>[
          const ExperienceEntry(
            focusId: 'b',
            level: ExperienceLevel.advanced,
          ),
        ],
      );
    });

    test('an unknown equipment id is kept', () {
      expect(
        TrainingSetupValues.fromJson(<String, Object?>{
          'equipment': <Object?>['rower', '', 7],
        }).equipment,
        <String>['rower'],
      );
    });

    test('an empty list reads as none, not unset', () {
      expect(
        TrainingGoalsValues.fromJson(<String, Object?>{'goals': <Object?>[]})
            .goals,
        isEmpty,
      );
    });

    test('values round-trip through the wire shape', () {
      final json = <String, Object?>{
        'sex': 'female',
        'birth_year': 1990,
        'height': <String, Object?>{'value': 66, 'unit': 'in'},
      };
      expect(AboutYouValues.fromJson(json).toJson(), json);

      final decimal = <String, Object?>{'value': 165.5, 'unit': 'cm'};
      expect(ProfileHeight.fromJson(decimal)!.toJson(), decimal);
    });

    test('inCentimetres converts at exactly 2.54', () {
      expect(
        const ProfileHeight(value: 66, unit: HeightUnit.inch).inCentimetres,
        66 * 2.54,
      );
      expect(
        const ProfileHeight(value: 180.5, unit: HeightUnit.cm).inCentimetres,
        180.5,
      );
    });
  });

  group('UserProfile getters', () {
    test('every getter is null when no section has a row', () {
      const profile = UserProfile();
      expect(profile.sex, isNull);
      expect(profile.birthYear, isNull);
      expect(profile.height, isNull);
      expect(profile.goals, isNull);
      expect(profile.experienceLevels, isNull);
      expect(profile.equipment, isNull);
      expect(profile.daysPerWeek, isNull);
      expect(profile.sessionMinutes, isNull);
      expect(profile.healthText, isNull);
      expect(profile.healthNone, isNull);
      expect(profile.generalNotesText, isNull);
    });

    test('ageAt is the local calendar year minus the birth year', () {
      const profile = UserProfile(aboutYou: AboutYouValues(birthYear: 1990));
      expect(profile.ageAt(DateTime(2026, 1, 1)), 36);
      expect(profile.ageAt(DateTime(2025, 12, 31, 23, 59)), 35);
    });

    test('ageAt reads a UTC instant in local time', () {
      const profile = UserProfile(aboutYou: AboutYouValues(birthYear: 1990));
      final instant = DateTime.utc(2026, 1, 1);
      expect(profile.ageAt(instant), instant.toLocal().year - 1990);
    });

    test('ageAt is null with no birth year', () {
      expect(const UserProfile().ageAt(DateTime(2026)), isNull);
      expect(
        const UserProfile(aboutYou: AboutYouValues()).ageAt(DateTime(2026)),
        isNull,
      );
    });
  });
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
  throw StateError('$name not found.');
}
