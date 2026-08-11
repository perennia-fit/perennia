import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/template_divergence/widgets/template_update_prompt_dialog.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Template update prompt accessibility', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'meets contrast, Android target, and label guidelines in '
        '${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);

          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              home: Scaffold(
                body: TemplateUpdatePromptDialog(
                  summary: TemplateDivergenceSummary(
                    workoutId: 'workout-1',
                    workoutTemplateId: 'template-1',
                    templateName: 'Push A',
                    divergence: const TemplateDivergenceResult(
                      addedExercises: <TemplateDivergenceExerciseRef>[
                        TemplateDivergenceExerciseRef(
                          exerciseId: 'exercise-dips',
                          exerciseName: 'Dips',
                        ),
                      ],
                      removedExercises: <TemplateDivergenceExerciseRef>[
                        TemplateDivergenceExerciseRef(
                          exerciseId: 'exercise-incline',
                          exerciseName: 'Incline Press',
                        ),
                      ],
                      changedExercises: <TemplateDivergenceExerciseRef>[],
                      groupsChanged: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Update "Push A"?'), findsOneWidget);
          expect(find.textContaining('Dips'), findsOneWidget);
          expect(
            find.byKey(
              TemplateUpdatePromptDialog.confirmButtonKey('workout-1'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              TemplateUpdatePromptDialog.dismissButtonKey('workout-1'),
            ),
            findsOneWidget,
          );

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );
    }

    testWidgets('dismiss and confirm resolve the expected boolean',
        (tester) async {
      await _setLargePhone(tester);

      const summary = TemplateDivergenceSummary(
        workoutId: 'workout-2',
        workoutTemplateId: 'template-2',
        templateName: 'Pull A',
        divergence: TemplateDivergenceResult(
          addedExercises: <TemplateDivergenceExerciseRef>[],
          removedExercises: <TemplateDivergenceExerciseRef>[],
          changedExercises: <TemplateDivergenceExerciseRef>[],
          groupsChanged: false,
        ),
      );
      bool? result;

      await tester.pumpWidget(
        _testApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showTemplateUpdatePromptDialog(
                      context,
                      summary: summary,
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('No changes to update'), findsOneWidget);

      await tester.tap(
        find.byKey(TemplateUpdatePromptDialog.dismissButtonKey('workout-2')),
      );
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(TemplateUpdatePromptDialog.confirmButtonKey('workout-2')),
      );
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}

Future<void> _setLargePhone(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _testApp({
  required Widget home,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
