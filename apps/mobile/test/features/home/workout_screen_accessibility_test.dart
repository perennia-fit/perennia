import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/template_materialize/repositories/template_materialize_feature_repository.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

const _workoutId = 'workout-1';

void main() {
  for (final isOpen in <bool>[true, false]) {
    final state = isOpen ? 'open' : 'finished';
    final actionKey = isOpen
        ? WorkoutScreen.finishButtonKey(_workoutId)
        : WorkoutScreen.resumeButtonKey(_workoutId);

    testWidgets('$state Workout meets accessibility guidelines in both themes',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_workoutApp(theme: theme, isOpen: isOpen));
        await tester.pumpAndSettle();

        // Both outlined buttons on screen, so the guideline sees them.
        expect(find.byKey(actionKey).hitTestable(), findsOneWidget);
        expect(
          find.byKey(WorkoutScreen.notesButtonKey(_workoutId)).hitTestable(),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('$state Workout header fits a 360 dp screen at text scale 2.0',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _workoutApp(
          theme: AppTheme.light(),
          isOpen: isOpen,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(actionKey), findsOneWidget);
    });
  }
}

Widget _workoutApp({
  required ThemeData theme,
  required bool isOpen,
  TextScaler? textScaler,
}) {
  // A long Workout, so the finished header's duration is at its widest.
  final startedAt = DateTime.utc(2026, 7, 11, 8);
  final workout = HomeWorkoutSummary(
    id: _workoutId,
    startedAt: startedAt,
    endedAt:
        isOpen ? null : startedAt.add(const Duration(hours: 1, minutes: 47)),
  );
  return ProviderScope(
    overrides: [
      homeRepositoryProvider.overrideWithValue(_WorkoutHomeRepository(workout)),
      // The plan-notes card would otherwise open the on-disk database.
      templateMaterializeFeatureRepositoryProvider.overrideWithValue(
        const _NoGuidanceRepository(),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
      home: const WorkoutScreen(workoutId: _workoutId),
    ),
  );
}

class _WorkoutHomeRepository extends StubHomeRepository {
  _WorkoutHomeRepository(this.workout);

  final HomeWorkoutSummary workout;

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(workout);
  }
}

class _NoGuidanceRepository implements TemplateMaterializeFeatureRepository {
  const _NoGuidanceRepository();

  @override
  Stream<WorkoutTemplateGuidance?> watchTemplateGuidance(String workoutId) =>
      Stream<WorkoutTemplateGuidance?>.value(null);

  @override
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) {
    throw UnsupportedError('The Workout screen never starts a Template.');
  }

  @override
  Stream<Set<String>> watchEmptyTemplateIds() =>
      Stream<Set<String>>.value(const <String>{});

  @override
  Future<String?> emptyTemplateName(String workoutTemplateId) async => null;
}
