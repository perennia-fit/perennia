import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_progress.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/focus_time_card.dart';
import 'package:perennia/features/progress/widgets/progress_card.dart';
import 'package:perennia/features/progress/widgets/this_week_card.dart';
import 'package:perennia/features/progress/widgets/trained_days_card.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

/// A repository whose Workouts stream fails, as a failed Drift query does.
class _FailingWorkoutsRepository extends StubProgressFeatureRepository {
  const _FailingWorkoutsRepository();

  @override
  Stream<List<ProgressWorkout>> watchProgressWorkoutsBetween(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return Stream<List<ProgressWorkout>>.error(StateError('query failed'));
  }
}

void main() {
  testWidgets(
      'a failed Workouts read shows the training cards as unavailable, not '
      'loading', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressFeatureRepositoryProvider.overrideWith(
            (ref) => const _FailingWorkoutsRepository(),
          ),
          settingsRepositoryProvider.overrideWith(
            (ref) => InMemorySettingsRepository(),
          ),
          progressClockProvider.overrideWith(
            (ref) => () => DateTime(2026, 10, 30, 18),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ThisWeekCard(),
                  TrainedDaysCard(),
                  FocusTimeCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unavailable right now'), findsNWidgets(3));
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Trained days'), findsOneWidget);
    expect(find.text('Time by Focus'), findsOneWidget);
    expect(find.byKey(ThisWeekCard.daysKey), findsNothing);
    expect(find.byKey(TrainedDaysCard.countKey), findsNothing);
    // No card is left on its fixed-height loading body.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.height == ProgressCard.loadingBodyHeight,
      ),
      findsNothing,
    );
  });
}
