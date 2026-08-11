class MeasurementValueValidation {
  MeasurementValueValidation({
    required this.value,
    required this.valueEntered,
    required Iterable<MeasurementValidationWarning> warnings,
  }) : warnings = List<MeasurementValidationWarning>.unmodifiable(warnings);

  final double value;
  final String valueEntered;
  final List<MeasurementValidationWarning> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

class MeasurementValidationWarning {
  const MeasurementValidationWarning({
    required this.code,
    required this.value,
    required this.unit,
    required this.threshold,
  });

  final MeasurementValidationWarningCode code;
  final double value;
  final String unit;
  final double threshold;
}

enum MeasurementValidationWarningCode {
  suspiciouslyHigh,
}

class MeasurementValueException implements Exception {
  const MeasurementValueException(this.message);

  final String message;

  @override
  String toString() => 'MeasurementValueException: $message';
}

MeasurementValueValidation validateMeasurementValue({
  required String entered,
  required String unit,
}) {
  final trimmed = entered.trim();
  if (trimmed.isEmpty) {
    throw const MeasurementValueException('Measurement value is required.');
  }
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(trimmed)) {
    throw const MeasurementValueException(
      'Measurement value must be a non-negative finite number.',
    );
  }
  final decimalPoint = trimmed.indexOf('.');
  if (decimalPoint != -1 && trimmed.length - decimalPoint - 1 > 5) {
    throw const MeasurementValueException(
      'Measurement value can have at most 5 decimal places.',
    );
  }
  final value = double.tryParse(trimmed);
  if (value == null || !value.isFinite || value < 0) {
    throw const MeasurementValueException(
      'Measurement value must be a non-negative finite number.',
    );
  }

  return MeasurementValueValidation(
    value: value,
    valueEntered: trimmed,
    warnings: List<MeasurementValidationWarning>.unmodifiable(
      _warningsFor(value: value, unit: unit),
    ),
  );
}

double? validateMeasurementTargetValue({
  required String goalType,
  required double? targetValue,
}) {
  if (goalType != 'target') {
    return null;
  }
  if (targetValue == null) {
    throw const MeasurementValueException(
      'Measurement target value is required for target goals.',
    );
  }
  if (!targetValue.isFinite || targetValue < 0) {
    throw const MeasurementValueException(
      'Measurement target value must be a non-negative finite number.',
    );
  }
  return targetValue;
}

Iterable<MeasurementValidationWarning> _warningsFor({
  required double value,
  required String unit,
}) sync* {
  final threshold = _suspiciousHighThresholdsByUnit[unit];
  if (threshold != null && value > threshold) {
    yield MeasurementValidationWarning(
      code: MeasurementValidationWarningCode.suspiciouslyHigh,
      value: value,
      unit: unit,
      threshold: threshold,
    );
  }
}

const _suspiciousHighThresholdsByUnit = <String, double>{
  'kilogram': 500,
  'pound': 1100,
  'centimeter': 300,
  'inch': 120,
  'percent': 100,
};
