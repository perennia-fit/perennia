import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/body_tracker/measurement_validation.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/protocols/dose_validation.dart';
import 'package:perennia/domain/settings/settings_validation.dart';
import 'package:perennia/domain/training/set_validation.dart';

void main() {
  test('shared validation result models expose immutable snapshots', () {
    const setIssue = SetValidationIssue(
      field: 'value',
      dimension: null,
      rule: 'set_rule',
      message: 'Set issue.',
      limit: null,
    );
    const nutrientIssue = NutrientValidationIssue(
      field: 'nutrients.energy',
      nutrient: NutrientId.energy,
      rule: 'nutrient_rule',
      message: 'Nutrient issue.',
      limit: null,
    );
    const settingsIssue = SettingsValidationIssue(
      field: 'themePreference',
      rule: 'setting_rule',
      message: 'Settings issue.',
    );
    const doseIssue = DoseValidationIssue(
      field: 'amount',
      rule: 'dose_rule',
      message: 'Dose issue.',
      limit: null,
    );
    const measurementWarning = MeasurementValidationWarning(
      code: MeasurementValidationWarningCode.suspiciouslyHigh,
      value: 5000,
      unit: 'kilogram',
      threshold: 500,
    );

    final setErrors = <SetValidationIssue>[setIssue];
    final setWarnings = <SetValidationIssue>[setIssue];
    final setResult = SetValidationResult(
      errors: setErrors,
      warnings: setWarnings,
    );
    final setException = SetValidationException(
      errors: setErrors,
      warnings: setWarnings,
    );

    final nutrientErrors = <NutrientValidationIssue>[nutrientIssue];
    final nutrientWarnings = <NutrientValidationIssue>[nutrientIssue];
    final nutrientResult = NutrientValidationResult(
      errors: nutrientErrors,
      warnings: nutrientWarnings,
    );
    final nutrientException = NutrientValidationException(
      errors: nutrientErrors,
      warnings: nutrientWarnings,
    );

    final settingsErrors = <SettingsValidationIssue>[settingsIssue];
    final settingsWarnings = <SettingsValidationIssue>[settingsIssue];
    final settingsResult = SettingsValidationResult(
      errors: settingsErrors,
      warnings: settingsWarnings,
    );
    final settingsException = SettingsValidationException(
      errors: settingsErrors,
      warnings: settingsWarnings,
    );

    final doseErrors = <DoseValidationIssue>[doseIssue];
    final doseWarnings = <DoseValidationIssue>[doseIssue];
    final doseResult = DoseValidationResult(
      errors: doseErrors,
      warnings: doseWarnings,
    );
    final doseException = DoseValidationException(
      errors: doseErrors,
      warnings: doseWarnings,
    );

    final measurementWarnings = <MeasurementValidationWarning>[
      measurementWarning,
    ];
    final measurementResult = MeasurementValueValidation(
      value: 5000,
      valueEntered: '5000',
      warnings: measurementWarnings,
    );

    setErrors.clear();
    setWarnings.clear();
    nutrientErrors.clear();
    nutrientWarnings.clear();
    settingsErrors.clear();
    settingsWarnings.clear();
    doseErrors.clear();
    doseWarnings.clear();
    measurementWarnings.clear();

    expect(setResult.errors, <SetValidationIssue>[setIssue]);
    expect(setResult.warnings, <SetValidationIssue>[setIssue]);
    expect(setException.errors, <SetValidationIssue>[setIssue]);
    expect(setException.warnings, <SetValidationIssue>[setIssue]);
    expect(nutrientResult.errors, <NutrientValidationIssue>[nutrientIssue]);
    expect(nutrientResult.warnings, <NutrientValidationIssue>[nutrientIssue]);
    expect(nutrientException.errors, <NutrientValidationIssue>[nutrientIssue]);
    expect(
      nutrientException.warnings,
      <NutrientValidationIssue>[nutrientIssue],
    );
    expect(settingsResult.errors, <SettingsValidationIssue>[settingsIssue]);
    expect(settingsResult.warnings, <SettingsValidationIssue>[settingsIssue]);
    expect(settingsException.errors, <SettingsValidationIssue>[settingsIssue]);
    expect(
      settingsException.warnings,
      <SettingsValidationIssue>[settingsIssue],
    );
    expect(doseResult.errors, <DoseValidationIssue>[doseIssue]);
    expect(doseResult.warnings, <DoseValidationIssue>[doseIssue]);
    expect(doseException.errors, <DoseValidationIssue>[doseIssue]);
    expect(doseException.warnings, <DoseValidationIssue>[doseIssue]);
    expect(
      measurementResult.warnings,
      <MeasurementValidationWarning>[measurementWarning],
    );

    expect(() => setResult.errors.clear(), throwsUnsupportedError);
    expect(() => setResult.warnings.clear(), throwsUnsupportedError);
    expect(() => setException.errors.clear(), throwsUnsupportedError);
    expect(() => setException.warnings.clear(), throwsUnsupportedError);
    expect(() => nutrientResult.errors.clear(), throwsUnsupportedError);
    expect(() => nutrientResult.warnings.clear(), throwsUnsupportedError);
    expect(() => nutrientException.errors.clear(), throwsUnsupportedError);
    expect(() => nutrientException.warnings.clear(), throwsUnsupportedError);
    expect(() => settingsResult.errors.clear(), throwsUnsupportedError);
    expect(() => settingsResult.warnings.clear(), throwsUnsupportedError);
    expect(() => settingsException.errors.clear(), throwsUnsupportedError);
    expect(() => settingsException.warnings.clear(), throwsUnsupportedError);
    expect(() => doseResult.errors.clear(), throwsUnsupportedError);
    expect(() => doseResult.warnings.clear(), throwsUnsupportedError);
    expect(() => doseException.errors.clear(), throwsUnsupportedError);
    expect(() => doseException.warnings.clear(), throwsUnsupportedError);
    expect(() => measurementResult.warnings.clear(), throwsUnsupportedError);
  });
}
