import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_progress.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/focus_time_card.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets(
      'a long Focus name wraps in the legend instead of overflowing the card',
      (tester) async {
    // A narrow phone at a large text scale, the tightest the legend gets.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const name = 'Upper body hypertrophy and conditioning block';
    final startedAt = DateTime(2026, 10, 30, 7);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressFeatureRepositoryProvider.overrideWith(
            (ref) => StubProgressFeatureRepository(
              workouts: <ProgressWorkout>[
                ProgressWorkout(
                  workoutId: 'w-1',
                  localDate:
                      const TrainingDayDate(year: 2026, month: 10, day: 30),
                  startedAt: startedAt,
                  endedAt:
                      startedAt.add(const Duration(hours: 12, minutes: 40)),
                  focusId: 'focus-long',
                  linkedTemplateId: null,
                  performedSetCount: 1,
                ),
              ],
              focusesById: <String, FocusRecord>{
                'focus-long': FocusRecord(
                  id: 'focus-long',
                  name: name,
                  sortOrder: 0,
                  updatedAt: DateTime.utc(2026),
                ),
              },
            ),
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
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(AppDimens.base),
                child: FocusTimeCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(name), findsOneWidget);
  });
}
