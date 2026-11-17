import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/template_materialize/repositories/template_materialize_feature_repository.dart';
import 'package:perennia/features/template_materialize/widgets/template_guidance_card.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

const _longNotes =
    'Sets, reps, rest periods and the final exercise alternatives need to be '
    'specified before performing this session. Skill options: supported '
    'single-leg squat to a high box or a TRX single-leg squat. Power: '
    'two-handed, non-overhead kettlebell swings with a crisp hip drive; stop '
    'before speed or technique deteriorates. Supporting pairs: feet-supported '
    'inverted row with kettlebell goblet squat; externally supported '
    'single-leg kettlebell RDL with supported single-arm kettlebell row.';

void main() {
  testWidgets(
      "shows the linked Template's notes collapsed, and expands them on "
      'request', (tester) async {
    await tester.pumpWidget(
      _testApp(
        guidance: const WorkoutTemplateGuidance(
          templateName: 'Friday — Functional Strength',
          notes: _longNotes,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(TemplateGuidanceCard.cardKey('workout-1')), findsOne);
    expect(find.text('Plan notes'), findsOneWidget);
    expect(find.text('From Friday — Functional Strength'), findsOneWidget);
    Text notesText() => tester.widget<Text>(find.text(_longNotes));
    expect(notesText().maxLines, 4);

    await tester.tap(find.byKey(TemplateGuidanceCard.toggleKey('workout-1')));
    await tester.pump();
    expect(notesText().maxLines, isNull);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.byKey(TemplateGuidanceCard.toggleKey('workout-1')));
    await tester.pump();
    expect(notesText().maxLines, 4);
  });

  testWidgets('short notes show in full with no toggle', (tester) async {
    await tester.pumpWidget(
      _testApp(
        guidance: const WorkoutTemplateGuidance(
          templateName: 'Lifting A',
          notes: 'Keep two reps in reserve.',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Keep two reps in reserve.'), findsOneWidget);
    expect(
        find.byKey(TemplateGuidanceCard.toggleKey('workout-1')), findsNothing);
  });

  testWidgets('renders nothing without linked notes', (tester) async {
    await tester.pumpWidget(_testApp(guidance: null));
    await tester.pump();

    expect(find.byKey(TemplateGuidanceCard.cardKey('workout-1')), findsNothing);
    expect(find.text('Plan notes'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'meets contrast, Android target, and label guidelines in '
        '${brightness.name}', (tester) async {
      await tester.pumpWidget(
        _testApp(
          brightness: brightness,
          guidance: const WorkoutTemplateGuidance(
            templateName: 'Friday — Functional Strength',
            notes: _longNotes,
          ),
        ),
      );
      await tester.pump();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  }
}

Widget _testApp({
  required WorkoutTemplateGuidance? guidance,
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [
      templateMaterializeFeatureRepositoryProvider.overrideWith(
        (ref) => _GuidanceOnlyRepository(guidance),
      ),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: TemplateGuidanceCard(workoutId: 'workout-1'),
        ),
      ),
    ),
  );
}

class _GuidanceOnlyRepository implements TemplateMaterializeFeatureRepository {
  const _GuidanceOnlyRepository(this._guidance);

  final WorkoutTemplateGuidance? _guidance;

  @override
  Stream<WorkoutTemplateGuidance?> watchTemplateGuidance(String workoutId) =>
      Stream<WorkoutTemplateGuidance?>.value(_guidance);

  @override
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) {
    throw UnsupportedError('The plan-notes card never starts a Template.');
  }

  @override
  Stream<Set<String>> watchEmptyTemplateIds() =>
      Stream<Set<String>>.value(const <String>{});

  @override
  Future<String?> emptyTemplateName(String workoutTemplateId) async => null;
}
