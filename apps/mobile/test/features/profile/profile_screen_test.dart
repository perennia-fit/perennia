import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/focus/controllers/focus_providers.dart';
import 'package:perennia/features/profile/controllers/profile_controller.dart';
import 'package:perennia/features/profile/widgets/profile_screen.dart';
import 'package:perennia/features/profile/widgets/profile_section_editors.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/app_localizations_en.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

const _localOnlyLine =
    'Stored on this phone and in its backups. If you sign in, it syncs to your '
    "account, where the server's operator and any agent you connect can read "
    'it.';
const _syncedLine =
    "Synced to perennia.example.com. The server's operator and any agent you "
    'connect can read it. Change history on the server is kept for up to 180 '
    'days.';
const _agentHistoryLine =
    'Agent activity history shows that this section changed, not the text.';
const _medicationsLine = 'Medications and supplements belong in Protocols.';

final _updatedAt = DateTime.utc(2026, 1, 1);

List<FocusRecord> _focuses() {
  return <FocusRecord>[
    FocusRecord(
      id: 'focus-strength',
      name: 'Strength',
      sortOrder: 0,
      updatedAt: _updatedAt,
    ),
    FocusRecord(
      id: 'focus-running',
      name: 'Running',
      sortOrder: 1,
      updatedAt: _updatedAt,
    ),
  ];
}

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

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 12; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuthState? authState,
    UnitSystem unitSystem = UnitSystem.metric,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          authRepositoryProvider.overrideWith(
            (ref) => InMemoryAuthRepository(authState),
          ),
          settingsRepositoryProvider.overrideWith(
            (ref) => InMemorySettingsRepository(
              AppSettings.defaults.copyWith(unitSystem: unitSystem),
            ),
          ),
          activeFocusesProvider.overrideWith(
            (ref) => Stream<List<FocusRecord>>.value(_focuses()),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Disposes the screen, so its Drift streams close inside the test's clock.
  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> openEditor(
    WidgetTester tester,
    UserProfileSection section,
  ) async {
    final card = find.byKey(ProfileScreen.sectionCardKey(section));
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(card);
    await settle(tester);
  }

  Future<void> tapInEditor(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(ProfileEditorKeys.saveButton));
    await settle(tester);
  }

  Future<void> seed(
    WidgetTester tester,
    UserProfileSection section,
    Map<String, Object?> changes,
  ) async {
    await tester.runAsync(
      () => repositories.userProfile.saveSection(section, changes),
    );
  }

  /// The stored values of [section], as written, or null with no row.
  Future<Map<String, Object?>?> stored(
    WidgetTester tester,
    UserProfileSection section,
  ) async {
    final rows = await tester.runAsync(
      () => database.select(database.userProfileSections).get(),
    );
    final row = rows!.where((row) => row.section == section.wireName);
    return row.isEmpty
        ? null
        : jsonDecode(row.single.valuesJson) as Map<String, Object?>;
  }

  Future<int> activityLogCount(WidgetTester tester) async {
    final rows = await tester.runAsync(
      () => database.select(database.activityLog).get(),
    );
    return rows!.length;
  }

  group('disclosure line', () {
    testWidgets('Local-only Mode shows its exact line once, under the title', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text(_localOnlyLine), findsOneWidget);
      expect(find.text(_syncedLine), findsNothing);
      expect(
        tester.getTopLeft(find.text(_localOnlyLine)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Profile')).dy),
      );
      await disposeScreen(tester);
    });

    testWidgets('Synced Mode shows its exact line once, with the host', (
      tester,
    ) async {
      final serverUrl = Uri.parse('https://perennia.example.com');
      await pumpScreen(
        tester,
        authState: AuthState(
          serverUrl: serverUrl,
          session: AuthSession(
            provider: AuthSessionProvider.email,
            serverUrl: serverUrl,
            token: 'token-a',
            userEmail: 'qa@example.com',
            userId: 'user-a',
            userName: 'QA User',
          ),
        ),
      );

      expect(find.text(_syncedLine), findsOneWidget);
      expect(find.text(_localOnlyLine), findsNothing);
      expect(
        tester.getTopLeft(find.text(_syncedLine)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Profile')).dy),
      );
      await disposeScreen(tester);
    });

    testWidgets('a signed-out server URL is still Local-only Mode', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        authState: AuthState(
          serverUrl: Uri.parse('https://perennia.example.com'),
        ),
      );

      expect(find.text(_localOnlyLine), findsOneWidget);
      await disposeScreen(tester);
    });
  });

  group('section cards', () {
    testWidgets('an empty record shows six cards reading Not set', (
      tester,
    ) async {
      await pumpScreen(tester);

      for (final section in UserProfileSection.values) {
        final card = find.byKey(ProfileScreen.sectionCardKey(section));
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(
          find.descendant(of: card, matching: find.text('Not set')),
          findsOneWidget,
          reason: section.wireName,
        );
      }
      await disposeScreen(tester);
    });

    testWidgets(
        'cards show values and None, an unknown equipment id as the id, and '
        'hide an archived Focus', (tester) async {
      await seed(tester, UserProfileSection.aboutYou, <String, Object?>{
        'sex': 'female',
        'birth_year': 1990,
        'height': <String, Object?>{'value': 170.5, 'unit': 'cm'},
      });
      await seed(tester, UserProfileSection.trainingGoals, <String, Object?>{
        'goals': <String>[],
      });
      await seed(tester, UserProfileSection.experience, <String, Object?>{
        'levels': <Object?>[
          <String, Object?>{'focus_id': 'focus-archived', 'level': 'advanced'},
          <String, Object?>{'focus_id': 'focus-running', 'level': 'beginner'},
        ],
      });
      await seed(tester, UserProfileSection.trainingSetup, <String, Object?>{
        'equipment': <String>['barbell', 'someNewRig'],
        'days_per_week': 3,
        'session_minutes': 45,
      });
      await pumpScreen(tester);

      expect(
        find.text('Sex used for default reference ranges: Female'),
        findsOneWidget,
      );
      expect(find.text('Birth year: 1990'), findsOneWidget);
      expect(find.text('Height: 170.5 cm'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Running: Beginner'), findsOneWidget);
      expect(find.textContaining('Advanced'), findsNothing);

      final setup = find.text('Equipment: Barbell, someNewRig');
      await tester.scrollUntilVisible(
        setup,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(setup, findsOneWidget);
      expect(find.text('Days per week: 3'), findsOneWidget);
      expect(find.text('Session length: 45 min'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('a stored height reads in the user\'s unit system', (
      tester,
    ) async {
      await seed(tester, UserProfileSection.aboutYou, <String, Object?>{
        'height': <String, Object?>{'value': 66, 'unit': 'in'},
      });
      await pumpScreen(tester, unitSystem: UnitSystem.imperial);
      expect(find.text('Height: 5 ft 6 in'), findsOneWidget);
      await disposeScreen(tester);

      await pumpScreen(tester);
      expect(find.text('Height: 167.6 cm'), findsOneWidget);
      await disposeScreen(tester);
    });
  });

  group('editor lines', () {
    testWidgets('Health & limitations shows both extra lines', (tester) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.healthLimitations);

      expect(find.text(_medicationsLine), findsOneWidget);
      expect(find.text(_agentHistoryLine), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('General Notes shows the agent-history line only', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.generalNotes);

      expect(find.text(_agentHistoryLine), findsOneWidget);
      expect(find.text(_medicationsLine), findsNothing);
      await disposeScreen(tester);
    });
  });

  group('accessibility', () {
    testWidgets('the screen and every editor meet the guidelines', (
      tester,
    ) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await pumpScreen(tester, theme: theme);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        for (final section in UserProfileSection.values) {
          await openEditor(tester, section);
          await expectLater(
            tester,
            meetsGuideline(textContrastGuideline),
            reason: section.wireName,
          );
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
            reason: section.wireName,
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
            reason: section.wireName,
          );
          Navigator.of(
            tester.element(find.byKey(ProfileEditorKeys.saveButton)),
          ).pop();
          await settle(tester);
        }

        semantics.dispose();
        await disposeScreen(tester);
      }
    });

    testWidgets('the Imperial height fields meet the guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, unitSystem: UnitSystem.imperial);
      await openEditor(tester, UserProfileSection.aboutYou);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await disposeScreen(tester);
    });

    testWidgets(
        'at 200% text on a phone nothing overflows and every control can be '
        'reached', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final controls = <UserProfileSection, List<Key>>{
        UserProfileSection.aboutYou: const <Key>[
          AboutYouFields.sexKey,
          AboutYouFields.birthYearKey,
          AboutYouFields.heightFeetKey,
          AboutYouFields.heightInchesKey,
        ],
        UserProfileSection.trainingGoals: <Key>[
          for (final goal in TrainingGoalId.values)
            TrainingGoalsFields.goalKey(goal),
          TrainingGoalsFields.noneKey,
        ],
        UserProfileSection.experience: <Key>[
          for (final focus in _focuses())
            for (final level in <ExperienceLevel?>[
              ...ExperienceLevel.values,
              null,
            ])
              ExperienceFields.levelKey(focus.id, level),
          ExperienceFields.noneKey,
        ],
        UserProfileSection.trainingSetup: <Key>[
          TrainingSetupFields.equipmentKey('skiErg'),
          TrainingSetupFields.equipmentNoneKey,
          TrainingSetupFields.daysDecreaseKey,
          TrainingSetupFields.daysIncreaseKey,
          TrainingSetupFields.sessionMinutesKey,
        ],
        UserProfileSection.healthLimitations: const <Key>[
          ProfileEditorKeys.healthTextField,
          ProfileEditorKeys.healthNoneSwitch,
        ],
        UserProfileSection.generalNotes: const <Key>[
          ProfileEditorKeys.generalNotesTextField,
        ],
      };

      await pumpScreen(tester, unitSystem: UnitSystem.imperial);
      expect(tester.takeException(), isNull);

      for (final entry in controls.entries) {
        await openEditor(tester, entry.key);
        expect(tester.takeException(), isNull, reason: entry.key.wireName);
        for (final key in entry.value) {
          final control = find.byKey(key);
          await tester.ensureVisible(control);
          await tester.pump();
          expect(control.hitTestable(), findsOneWidget, reason: '$key');
        }
        final save = find.byKey(ProfileEditorKeys.saveButton);
        expect(save.hitTestable(), findsOneWidget);
        Navigator.of(tester.element(save)).pop();
        await settle(tester);
        expect(tester.takeException(), isNull, reason: entry.key.wireName);
      }
      await disposeScreen(tester);
    });

    testWidgets('the metric height field fits at 200% text too', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.aboutYou);

      expect(tester.takeException(), isNull);
      final field = find.byKey(AboutYouFields.heightCentimetresKey);
      await tester.ensureVisible(field);
      await tester.pump();
      expect(field.hitTestable(), findsOneWidget);
      await disposeScreen(tester);
    });
  });

  group('validation in the editor', () {
    testWidgets('a soft warning asks first, and Save anyway saves', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingSetup);

      final minutes = find.byKey(TrainingSetupFields.sessionMinutesKey);
      await tester.ensureVisible(minutes);
      await tester.enterText(minutes, '300');
      await tapSave(tester);

      expect(find.byKey(ProfileEditorKeys.warningDialog), findsOneWidget);
      expect(find.text('Check this value'), findsOneWidget);
      expect(
        find.text('Sessions over 4 hours are unusual. Check the length.'),
        findsOneWidget,
      );
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Save anyway'), findsOneWidget);
      expect(await stored(tester, UserProfileSection.trainingSetup), isNull);

      await tester.tap(find.byKey(ProfileEditorKeys.warningSaveAnywayButton));
      await settle(tester);

      expect(find.byKey(ProfileEditorKeys.warningDialog), findsNothing);
      expect(find.byKey(ProfileEditorKeys.saveButton), findsNothing);
      expect(
        (await stored(
            tester, UserProfileSection.trainingSetup))!['session_minutes'],
        300,
      );
      await disposeScreen(tester);
    });

    testWidgets('Edit returns to the field and saves nothing', (tester) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.aboutYou);

      await tester.enterText(
        find.byKey(AboutYouFields.heightCentimetresKey),
        '100',
      );
      await tapSave(tester);

      expect(
        find.text('A height of 100 cm is unusual. Check it.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ProfileEditorKeys.warningEditButton));
      await settle(tester);

      expect(find.byKey(ProfileEditorKeys.warningDialog), findsNothing);
      expect(
        find.byKey(AboutYouFields.heightCentimetresKey).hitTestable(),
        findsOneWidget,
      );
      expect(await stored(tester, UserProfileSection.aboutYou), isNull);
      await disposeScreen(tester);
    });

    testWidgets('a hard error stays in the sheet and saves nothing', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingSetup);

      final minutes = find.byKey(TrainingSetupFields.sessionMinutesKey);
      await tester.ensureVisible(minutes);
      await tester.enterText(minutes, '700');
      await tapSave(tester);

      expect(
        find.text('Session length must be 1 to 600 minutes.'),
        findsOneWidget,
      );
      expect(find.byKey(ProfileEditorKeys.warningDialog), findsNothing);
      expect(find.byKey(ProfileEditorKeys.saveButton), findsOneWidget);
      expect(await stored(tester, UserProfileSection.trainingSetup), isNull);
      await disposeScreen(tester);
    });

    test('every ARB validation string equals the module message', () {
      final l10n = AppLocalizationsEn();
      const referenceYear = 2026;
      Map<String, Object?> height(num value, String unit) {
        return <String, Object?>{
          'height': <String, Object?>{'value': value, 'unit': unit},
        };
      }

      final cases = <(UserProfileSection, Map<String, Object?>)>[
        (UserProfileSection.aboutYou, {'birth_year': 2030}),
        (UserProfileSection.aboutYou, {'birth_year': 1800}),
        (UserProfileSection.aboutYou, {'birth_year': 1915}),
        (UserProfileSection.aboutYou, {'birth_year': 2020}),
        (UserProfileSection.aboutYou, {'sex': 'other'}),
        (UserProfileSection.aboutYou, height(0, 'cm')),
        (UserProfileSection.aboutYou, height(301, 'cm')),
        (UserProfileSection.aboutYou, height(170, 'ft')),
        (UserProfileSection.aboutYou, height(100.5, 'cm')),
        (UserProfileSection.aboutYou, height(90, 'in')),
        (UserProfileSection.trainingSetup, {'days_per_week': 9}),
        (UserProfileSection.trainingSetup, {'session_minutes': 700}),
        (UserProfileSection.trainingSetup, {'session_minutes': 300}),
        (
          UserProfileSection.trainingSetup,
          {
            'equipment': <String>['', 'bench', 'bench'],
          }
        ),
        (
          UserProfileSection.trainingGoals,
          {
            'goals': <String>['flying', 'strength', 'strength'],
          }
        ),
        (
          UserProfileSection.experience,
          {
            'levels': <Object?>[
              <String, Object?>{'focus_id': '', 'level': 'expert'},
              <String, Object?>{'focus_id': 'a', 'level': 'beginner'},
              <String, Object?>{'focus_id': 'a', 'level': 'advanced'},
            ],
          }
        ),
        (UserProfileSection.healthLimitations, {'text': 'x' * 1001}),
        (UserProfileSection.generalNotes, {'text': 'x' * 2001}),
      ];

      final rules = <String>{};
      for (final (section, values) in cases) {
        final check = ProfileSaveCheck.validate(
          section,
          values,
          referenceYear: referenceYear,
        );
        for (final issue in [...check.errors, ...check.warnings]) {
          rules.add(issue.rule);
          expect(
            profileValidationMessage(l10n, issue, check),
            issue.message,
            reason: issue.rule,
          );
        }
      }

      expect(rules, <String>{
        'birth_year.future',
        'birth_year.too_old',
        'birth_year.improbable_age',
        'height.non_positive',
        'height.too_tall',
        'height.unit',
        'height.improbable',
        'days_per_week.range',
        'session_minutes.range',
        'session_minutes.improbable',
        'goals.unknown',
        'goals.duplicate',
        'equipment.invalid',
        'equipment.duplicate',
        'levels.unknown_level',
        'levels.invalid_focus',
        'levels.duplicate_focus',
        'text.too_long',
        'sex.unknown',
      });
    });
  });

  group('About you', () {
    testWidgets(
        'saving under Imperial without touching a stored cm height leaves it '
        'in cm', (tester) async {
      await seed(tester, UserProfileSection.aboutYou, <String, Object?>{
        'height': <String, Object?>{'value': 170.5, 'unit': 'cm'},
      });
      await pumpScreen(tester, unitSystem: UnitSystem.imperial);
      await openEditor(tester, UserProfileSection.aboutYou);

      await tester.tap(find.text('Female'));
      await tester.pump();
      await tapSave(tester);

      final values = await stored(tester, UserProfileSection.aboutYou);
      expect(values!['sex'], 'female');
      expect(values['height'], <String, Object?>{'value': 170.5, 'unit': 'cm'});
      await disposeScreen(tester);
    });

    testWidgets('the sex field is labelled for its purpose', (tester) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.aboutYou);

      const label = 'Sex used for default reference ranges';
      expect(find.text(label), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(AboutYouFields.sexKey),
          matching: find.bySemanticsLabel(label),
        ),
        findsOneWidget,
      );
      await disposeScreen(tester);
    });

    testWidgets('an Imperial entry is stored as total inches', (tester) async {
      await pumpScreen(tester, unitSystem: UnitSystem.imperial);
      await openEditor(tester, UserProfileSection.aboutYou);

      await tester.enterText(find.byKey(AboutYouFields.heightFeetKey), '5');
      await tester.enterText(find.byKey(AboutYouFields.heightInchesKey), '6');
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.aboutYou))!['height'],
        <String, Object?>{'value': 66, 'unit': 'in'},
      );
      await disposeScreen(tester);
    });

    testWidgets('a metric entry is stored in centimetres, as entered', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.aboutYou);

      await tester.enterText(
        find.byKey(AboutYouFields.heightCentimetresKey),
        '172.5',
      );
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.aboutYou))!['height'],
        <String, Object?>{'value': 172.5, 'unit': 'cm'},
      );
      await disposeScreen(tester);
    });

    testWidgets('clearing a height clears it', (tester) async {
      await seed(tester, UserProfileSection.aboutYou, <String, Object?>{
        'height': <String, Object?>{'value': 170, 'unit': 'cm'},
      });
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.aboutYou);

      await tester.enterText(
        find.byKey(AboutYouFields.heightCentimetresKey),
        '',
      );
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.aboutYou))!['height'],
        isNull,
      );
      await disposeScreen(tester);
    });

    testWidgets('the height fields follow a unit change without a save', (
      tester,
    ) async {
      var unitSystem = UnitSystem.metric;
      var changes = <String, Object?>{};
      late StateSetter setOuterState;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuterState = setState;
                return AboutYouFields(
                  initial: const AboutYouValues(
                    height: ProfileHeight(value: 66, unit: HeightUnit.inch),
                  ),
                  unitSystem: unitSystem,
                  onChanged: (next) => changes = next,
                );
              },
            ),
          ),
        ),
      );

      String textOf(Key key) =>
          tester.widget<TextField>(find.byKey(key)).controller!.text;

      expect(textOf(AboutYouFields.heightCentimetresKey), '167.6');

      setOuterState(() => unitSystem = UnitSystem.imperial);
      await tester.pump();
      expect(textOf(AboutYouFields.heightFeetKey), '5');
      expect(textOf(AboutYouFields.heightInchesKey), '6');
      expect(changes, isEmpty, reason: 'an untouched height is not a change');

      await tester.enterText(find.byKey(AboutYouFields.heightInchesKey), '10');
      expect(changes['height'], <String, Object?>{'value': 70, 'unit': 'in'});

      setOuterState(() => unitSystem = UnitSystem.metric);
      await tester.pump();
      expect(textOf(AboutYouFields.heightCentimetresKey), '177.8');
    });
  });

  group('selecting nothing and None', () {
    testWidgets('saving Training Goals with nothing selected writes no row', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingGoals);
      await tapSave(tester);

      expect(await stored(tester, UserProfileSection.trainingGoals), isNull);
      await disposeScreen(tester);
    });

    testWidgets('None writes an empty list, and deselecting all clears', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingGoals);
      await tester.tap(find.byKey(TrainingGoalsFields.noneKey));
      await tester.pump();
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.trainingGoals))!['goals'],
        isEmpty,
      );

      await openEditor(tester, UserProfileSection.trainingGoals);
      final longevity = find.byKey(
        TrainingGoalsFields.goalKey(TrainingGoalId.longevity),
      );
      await tester.tap(longevity);
      await tester.pump();
      await tester.tap(longevity);
      await tester.pump();
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.trainingGoals))!['goals'],
        isNull,
        reason: 'the row exists and its list is now unset',
      );
      await disposeScreen(tester);
    });

    testWidgets('Training setup equipment follows the same rule', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingSetup);
      await tapInEditor(
        tester,
        find.byKey(TrainingSetupFields.equipmentNoneKey),
      );
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.trainingSetup))!['equipment'],
        isEmpty,
      );
      await disposeScreen(tester);
    });

    testWidgets('Bodyweight is not offered as an equipment chip', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingSetup);

      expect(find.text('Bodyweight'), findsNothing);
      expect(find.text('Barbell'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('an unknown equipment id stays through a save', (tester) async {
      await seed(tester, UserProfileSection.trainingSetup, <String, Object?>{
        'equipment': <String>['someNewRig', 'barbell'],
      });
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.trainingSetup);

      final chip = find.byKey(TrainingSetupFields.equipmentKey('someNewRig'));
      await tester.ensureVisible(chip);
      await tester.pump();
      expect(
        find.descendant(of: chip, matching: find.text('someNewRig')),
        findsOneWidget,
      );
      expect(tester.widget<FilterChip>(chip).selected, isTrue);

      await tapInEditor(
        tester,
        find.byKey(TrainingSetupFields.equipmentKey('dumbbell')),
      );
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.trainingSetup))!['equipment'],
        <String>['someNewRig', 'barbell', 'dumbbell'],
      );
      await disposeScreen(tester);
    });
  });

  group('Experience', () {
    const archived = <String, Object?>{
      'focus_id': 'focus-archived',
      'level': 'advanced',
    };

    testWidgets('saving keeps a hidden archived-Focus entry', (tester) async {
      await seed(tester, UserProfileSection.experience, <String, Object?>{
        'levels': <Object?>[archived],
      });
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.experience);

      await tester.tap(
        find.byKey(
          ExperienceFields.levelKey(
            'focus-strength',
            ExperienceLevel.intermediate,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('One to three years.'), findsOneWidget);
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.experience))!['levels'],
        <Object?>[
          archived,
          <String, Object?>{
            'focus_id': 'focus-strength',
            'level': 'intermediate',
          },
        ],
      );
      await disposeScreen(tester);
    });

    testWidgets('Not set removes one entry and leaves the hidden one', (
      tester,
    ) async {
      await seed(tester, UserProfileSection.experience, <String, Object?>{
        'levels': <Object?>[
          archived,
          <String, Object?>{'focus_id': 'focus-running', 'level': 'beginner'},
        ],
      });
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.experience);

      await tester.tap(
        find.byKey(ExperienceFields.levelKey('focus-running', null)),
      );
      await tester.pump();
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.experience))!['levels'],
        <Object?>[archived],
      );
      await disposeScreen(tester);
    });

    testWidgets('only None writes an empty list', (tester) async {
      await seed(tester, UserProfileSection.experience, <String, Object?>{
        'levels': <Object?>[archived],
      });
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.experience);

      await tapInEditor(tester, find.byKey(ExperienceFields.noneKey));
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.experience))!['levels'],
        isEmpty,
      );
      await disposeScreen(tester);
    });

    testWidgets('Not set on the last entry clears the list, not to None', (
      tester,
    ) async {
      await seed(tester, UserProfileSection.experience, <String, Object?>{
        'levels': <Object?>[
          <String, Object?>{'focus_id': 'focus-running', 'level': 'beginner'},
        ],
      });
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.experience);

      await tester.tap(
        find.byKey(ExperienceFields.levelKey('focus-running', null)),
      );
      await tester.pump();
      await tapSave(tester);

      expect(
        (await stored(tester, UserProfileSection.experience))!['levels'],
        isNull,
      );
      await disposeScreen(tester);
    });
  });

  group('free text', () {
    testWidgets('the counter counts an astral character as 2', (tester) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.healthLimitations);

      expect(find.text('0 / 1000'), findsOneWidget);

      await tester.enterText(
        find.byKey(ProfileEditorKeys.healthTextField),
        '\u{1F4AA}',
      );
      await tester.pump();

      expect(find.text('2 / 1000'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('General Notes counts against its own cap', (tester) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.generalNotes);

      await tester.enterText(
        find.byKey(ProfileEditorKeys.generalNotesTextField),
        'abc',
      );
      await tester.pump();

      expect(find.text('3 / 2000'), findsOneWidget);
      await tapSave(tester);
      expect(
        (await stored(tester, UserProfileSection.generalNotes))!['text'],
        'abc',
      );
      await disposeScreen(tester);
    });

    testWidgets('text over the cap can be typed and is refused at Save', (
      tester,
    ) async {
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.healthLimitations);

      await tester.enterText(
        find.byKey(ProfileEditorKeys.healthTextField),
        'x' * 1001,
      );
      await tapSave(tester);

      expect(find.text('Keep this under 1000 characters.'), findsOneWidget);
      expect(
        await stored(tester, UserProfileSection.healthLimitations),
        isNull,
      );
      await disposeScreen(tester);
    });

    testWidgets('None clears the text, and typing turns None off', (
      tester,
    ) async {
      await seed(
        tester,
        UserProfileSection.healthLimitations,
        <String, Object?>{'text': 'Left knee'},
      );
      await pumpScreen(tester);
      await openEditor(tester, UserProfileSection.healthLimitations);

      final none = find.byKey(ProfileEditorKeys.healthNoneSwitch);
      final field = find.byKey(ProfileEditorKeys.healthTextField);
      await tapInEditor(tester, none);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);

      await tester.enterText(field, 'Right knee');
      await tester.pump();
      expect(tester.widget<SwitchListTile>(none).value, isFalse);

      await tapInEditor(tester, none);
      await tapSave(tester);

      expect(
        await stored(tester, UserProfileSection.healthLimitations),
        <String, Object?>{'text': null, 'none': true},
      );
      await disposeScreen(tester);
    });
  });

  testWidgets('saving an editor with no change adds no Activity Log entry', (
    tester,
  ) async {
    await seed(tester, UserProfileSection.aboutYou, <String, Object?>{
      'sex': 'male',
    });
    final before = await activityLogCount(tester);
    await pumpScreen(tester);
    await openEditor(tester, UserProfileSection.aboutYou);
    await tapSave(tester);

    expect(find.byKey(ProfileEditorKeys.saveButton), findsNothing);
    expect(await activityLogCount(tester), before);
    await disposeScreen(tester);
  });

  testWidgets('the days-per-week stepper runs from Not set to 7 and back', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openEditor(tester, UserProfileSection.trainingSetup);

    final increase = find.byKey(TrainingSetupFields.daysIncreaseKey);
    final decrease = find.byKey(TrainingSetupFields.daysDecreaseKey);
    final value = find.byKey(TrainingSetupFields.daysValueKey);
    await tester.ensureVisible(value);
    await tester.pump();

    expect(tester.widget<Text>(value).data, 'Not set');
    expect(tester.widget<IconButton>(decrease).onPressed, isNull);

    for (var day = 1; day <= 7; day += 1) {
      await tester.tap(increase);
      await tester.pump();
      expect(tester.widget<Text>(value).data, '$day');
    }
    expect(tester.widget<IconButton>(increase).onPressed, isNull);

    for (var day = 6; day >= 1; day -= 1) {
      await tester.tap(decrease);
      await tester.pump();
    }
    await tester.tap(decrease);
    await tester.pump();
    expect(tester.widget<Text>(value).data, 'Not set');
    await disposeScreen(tester);
  });
}
