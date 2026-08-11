import '../nutrition/nutrition.dart';
import 'training_dimensions.dart';

class SetValidationLimits {
  const SetValidationLimits._();

  static const numericMin = 0.0;
  static const maxDecimalPlaces = 5;
  static const loadMaxKilograms = 1000.0;
  static const loadMaxDecimalPlaces = 2;
  static const addedLoadWarnKilograms = 350.0;
  static const assistedLoadWarnKilograms = 150.0;
  static const repsMax = 10000.0;
  static const repsWarnAbove = 200.0;
  static const durationMaxSeconds = 24 * 60 * 60.0;
  static const durationWarnAboveSeconds = 4 * 60 * 60.0;
  static const distanceMaxKilometers = 1000.0;
  static const distanceWarnAboveKilometers = 250.0;
  static const rpeMin = 0.0;
  static const rpeMax = 10.0;
  static const rpeStep = 0.5;
  static const speedWarnAboveKilometersPerHour = 50.0;
  static const allowedSides = <String>['left', 'right'];
}

class SetValidationResult {
  SetValidationResult({
    required Iterable<SetValidationIssue> errors,
    required Iterable<SetValidationIssue> warnings,
  })  : errors = List<SetValidationIssue>.unmodifiable(errors),
        warnings = List<SetValidationIssue>.unmodifiable(warnings);

  final List<SetValidationIssue> errors;
  final List<SetValidationIssue> warnings;

  bool get accepted => errors.isEmpty;

  void throwIfRejected() {
    if (errors.isEmpty) {
      return;
    }
    throw SetValidationException(errors: errors, warnings: warnings);
  }
}

class SetValidationIssue {
  const SetValidationIssue({
    required this.field,
    required this.dimension,
    required this.rule,
    required this.message,
    required this.limit,
  });

  final String field;
  final DimensionId? dimension;
  final String rule;
  final String message;
  final Object? limit;
}

class SetValidationException implements Exception {
  SetValidationException({
    required Iterable<SetValidationIssue> errors,
    Iterable<SetValidationIssue> warnings = const <SetValidationIssue>[],
  })  : errors = List<SetValidationIssue>.unmodifiable(errors),
        warnings = List<SetValidationIssue>.unmodifiable(warnings);

  final List<SetValidationIssue> errors;
  final List<SetValidationIssue> warnings;

  String get message => 'Set failed hard validation.';

  @override
  String toString() {
    final rules = errors.map((error) => error.rule).join(', ');
    return 'SetValidationException: $message ($rules)';
  }
}

class NutrientValidationLimits {
  const NutrientValidationLimits._();

  static const numericMin = 0.0;
  static const energyMaxKilocalories = 10000.0;
  static const macroMaxGrams = 2000.0;
  static const portionWarnBaseQuantity = 2000.0;
  static const atwaterMismatchTolerance = 0.25;
}

class NutrientValidationResult {
  NutrientValidationResult({
    required Iterable<NutrientValidationIssue> errors,
    required Iterable<NutrientValidationIssue> warnings,
  })  : errors = List<NutrientValidationIssue>.unmodifiable(errors),
        warnings = List<NutrientValidationIssue>.unmodifiable(warnings);

  final List<NutrientValidationIssue> errors;
  final List<NutrientValidationIssue> warnings;

  bool get accepted => errors.isEmpty;

  void throwIfRejected() {
    if (errors.isEmpty) {
      return;
    }
    throw NutrientValidationException(errors: errors, warnings: warnings);
  }
}

class NutrientValidationException implements Exception {
  NutrientValidationException({
    required Iterable<NutrientValidationIssue> errors,
    Iterable<NutrientValidationIssue> warnings =
        const <NutrientValidationIssue>[],
  })  : errors = List<NutrientValidationIssue>.unmodifiable(errors),
        warnings = List<NutrientValidationIssue>.unmodifiable(warnings);

  final List<NutrientValidationIssue> errors;
  final List<NutrientValidationIssue> warnings;

  String get message => 'Food Entry failed hard nutrient validation.';

  @override
  String toString() {
    final rules = errors.map((error) => error.rule).join(', ');
    return 'NutrientValidationException: $message ($rules)';
  }
}

NutrientValidationResult validateFoodEntryNutrition({
  required NutrientVector nutrients,
  double? resolvedBaseQuantity,
}) {
  final errors = <NutrientValidationIssue>[];
  final warnings = <NutrientValidationIssue>[];
  final parsed = <NutrientId, double>{};

  for (final id in NutrientId.values) {
    final amount = nutrients[id];
    if (!amount.isComplete) {
      continue;
    }
    _validateNutrientAmount(
      id: id,
      value: amount.value!,
      errors: errors,
      parsed: parsed,
    );
  }

  _validatePortionSize(resolvedBaseQuantity, warnings);
  _validateAtwater(parsed, warnings);

  return NutrientValidationResult(
    errors: List<NutrientValidationIssue>.unmodifiable(errors),
    warnings: List<NutrientValidationIssue>.unmodifiable(warnings),
  );
}

/// Validates a set of nutrition `Goal` targets through the **same** shared
/// two-tier nutrient validator that guards `Food Entry`s (NUTRITION.md §6): a
/// negative or impossible-cap target (energy > 10000 kcal, a macro > 2000 g) is
/// hard-rejected by [_validateNutrientAmount], with no parallel nutrition-only
/// check. Goals carry no Portion and no Atwater relationship, so only the
/// per-nutrient hard-reject rules apply; there are no soft warnings.
NutrientValidationResult validateNutritionGoalTargets(
  Iterable<NutritionGoalTarget> targets,
) {
  final errors = <NutrientValidationIssue>[];
  final parsed = <NutrientId, double>{};

  for (final target in targets) {
    _validateNutrientAmount(
      id: target.nutrient,
      value: target.value,
      errors: errors,
      parsed: parsed,
    );
  }

  return NutrientValidationResult(
    errors: List<NutrientValidationIssue>.unmodifiable(errors),
    warnings: const <NutrientValidationIssue>[],
  );
}

SetValidationResult validateLoggedSet({
  required ExerciseType type,
  required ExerciseLoadMode loadMode,
  required LoggedSet values,
  Object? rpe,
  String? side,
}) {
  return validateSetValues(
    type: type,
    loadMode: loadMode,
    values: values.values.values,
    rpe: rpe,
    side: side,
  );
}

SetValidationResult validateSetValues({
  required ExerciseType type,
  required ExerciseLoadMode loadMode,
  required Iterable<SetDimensionValue> values,
  Object? rpe,
  String? side,
}) {
  final errors = <SetValidationIssue>[];
  final warnings = <SetValidationIssue>[];
  final parsed = <DimensionId, _ParsedDimension>{};
  final valuesByDimension = <DimensionId, SetDimensionValue>{
    for (final value in values) value.dimension: value,
  };

  for (final dimension in DimensionId.values) {
    _validateDimensionValue(
      dimension: dimension,
      value: valuesByDimension[dimension],
      loadMode: loadMode,
      errors: errors,
      warnings: warnings,
      parsed: parsed,
    );
  }

  _validateRpe(rpe, errors);
  _validateSide(side, errors);
  _validateCrossField(type, parsed, warnings);

  return SetValidationResult(
    errors: List<SetValidationIssue>.unmodifiable(errors),
    warnings: List<SetValidationIssue>.unmodifiable(warnings),
  );
}

void _validateNutrientAmount({
  required NutrientId id,
  required double value,
  required List<NutrientValidationIssue> errors,
  required Map<NutrientId, double> parsed,
}) {
  final field = 'nutrients.${id.storageKey}.value';
  if (!value.isFinite) {
    errors.add(
      NutrientValidationIssue(
        field: field,
        nutrient: id,
        rule: 'numeric_finite',
        message: 'Nutrient value must be finite.',
        limit: 'finite',
      ),
    );
    return;
  }
  if (value < NutrientValidationLimits.numericMin) {
    errors.add(
      NutrientValidationIssue(
        field: field,
        nutrient: id,
        rule: 'nutrient_non_negative',
        message: 'Nutrient value must be non-negative.',
        limit: NutrientValidationLimits.numericMin,
      ),
    );
    return;
  }
  if (id == NutrientId.energy &&
      value > NutrientValidationLimits.energyMaxKilocalories) {
    errors.add(
      const NutrientValidationIssue(
        field: 'nutrients.energy.value',
        nutrient: NutrientId.energy,
        rule: 'nutrient_energy_max_kilocalories',
        message: 'Energy must be no more than 10000 kcal per Food Entry.',
        limit: NutrientValidationLimits.energyMaxKilocalories,
      ),
    );
    return;
  }
  if (_isMacroNutrient(id) && value > NutrientValidationLimits.macroMaxGrams) {
    errors.add(
      NutrientValidationIssue(
        field: field,
        nutrient: id,
        rule: 'nutrient_macro_max_grams',
        message: 'Macro nutrients must be no more than 2000 g per Food Entry.',
        limit: NutrientValidationLimits.macroMaxGrams,
      ),
    );
    return;
  }

  parsed[id] = value;
}

void _validatePortionSize(
  double? resolvedBaseQuantity,
  List<NutrientValidationIssue> warnings,
) {
  if (resolvedBaseQuantity == null ||
      !resolvedBaseQuantity.isFinite ||
      resolvedBaseQuantity <=
          NutrientValidationLimits.portionWarnBaseQuantity) {
    return;
  }

  warnings.add(
    const NutrientValidationIssue(
      field: 'portion.resolvedBaseQuantity',
      nutrient: null,
      rule: 'portion_size_improbable',
      message: 'Portion above 2000 g/ml is improbable.',
      limit: NutrientValidationLimits.portionWarnBaseQuantity,
    ),
  );
}

void _validateAtwater(
  Map<NutrientId, double> parsed,
  List<NutrientValidationIssue> warnings,
) {
  final energy = parsed[NutrientId.energy];
  final protein = parsed[NutrientId.protein];
  final carbohydrate = parsed[NutrientId.carbohydrate];
  final fat = parsed[NutrientId.fat];
  if (energy == null ||
      protein == null ||
      carbohydrate == null ||
      fat == null) {
    return;
  }

  final estimatedEnergy = (4 * protein) + (4 * carbohydrate) + (9 * fat);
  final denominator = <double>[energy.abs(), estimatedEnergy.abs(), 1]
      .reduce((left, right) => left > right ? left : right);
  final relativeDifference = (energy - estimatedEnergy).abs() / denominator;
  if (relativeDifference > NutrientValidationLimits.atwaterMismatchTolerance) {
    warnings.add(
      const NutrientValidationIssue(
        field: 'nutrients.energy.value',
        nutrient: NutrientId.energy,
        rule: 'energy_atwater_mismatch',
        message:
            'Energy is far from the Atwater estimate from protein, carbohydrate, and fat.',
        limit: NutrientValidationLimits.atwaterMismatchTolerance,
      ),
    );
  }
}

bool _isMacroNutrient(NutrientId id) {
  return id == NutrientId.protein ||
      id == NutrientId.carbohydrate ||
      id == NutrientId.fat;
}

void _validateDimensionValue({
  required DimensionId dimension,
  required SetDimensionValue? value,
  required ExerciseLoadMode loadMode,
  required List<SetValidationIssue> errors,
  required List<SetValidationIssue> warnings,
  required Map<DimensionId, _ParsedDimension> parsed,
}) {
  if (value == null) {
    return;
  }

  final field = 'values.${dimension.name}.entered';
  final unitField = 'values.${dimension.name}.unit';
  final unitError = _validateUnit(dimension, value.unit, unitField);
  if (unitError != null) {
    errors.add(unitError);
  }

  final numericValue = _parseFiniteNonNegativeNumber(
    rawValue: value.entered,
    field: field,
    dimension: dimension,
    errors: errors,
  );
  if (numericValue == null || unitError != null) {
    return;
  }

  final decimalLimit = dimension == DimensionId.load
      ? SetValidationLimits.loadMaxDecimalPlaces
      : SetValidationLimits.maxDecimalPlaces;
  if (_decimalPlaces(value.entered) > decimalLimit) {
    errors.add(
      SetValidationIssue(
        field: field,
        dimension: dimension,
        rule: dimension == DimensionId.load
            ? 'load_max_two_decimal_places'
            : 'numeric_max_five_decimal_places',
        message: dimension == DimensionId.load
            ? 'Load must use no more than 2 decimal places.'
            : 'Numeric values must use no more than 5 decimal places.',
        limit: decimalLimit,
      ),
    );
    return;
  }

  final errorsBeforeDimensionRules = errors.length;
  switch (dimension) {
    case DimensionId.load:
      _validateLoad(numericValue, value.unit, loadMode, errors, warnings);
      if (errors.length == errorsBeforeDimensionRules) {
        parsed[dimension] = _ParsedDimension(
          dimension: dimension,
          field: field,
          metricValue: _convertLoadToKilograms(numericValue, value.unit),
        );
      }
    case DimensionId.reps:
      _validateReps(numericValue, errors, warnings);
      if (errors.length == errorsBeforeDimensionRules) {
        parsed[dimension] = _ParsedDimension(
          dimension: dimension,
          field: field,
          metricValue: numericValue,
        );
      }
    case DimensionId.duration:
      _validateDuration(numericValue, errors, warnings);
      if (errors.length == errorsBeforeDimensionRules) {
        parsed[dimension] = _ParsedDimension(
          dimension: dimension,
          field: field,
          metricValue: numericValue,
        );
      }
    case DimensionId.distance:
      _validateDistance(numericValue, value.unit, errors, warnings);
      if (errors.length == errorsBeforeDimensionRules) {
        parsed[dimension] = _ParsedDimension(
          dimension: dimension,
          field: field,
          metricValue: _convertDistanceToKilometers(numericValue, value.unit),
        );
      }
  }
}

void _validateLoad(
  double enteredValue,
  TrainingUnit unit,
  ExerciseLoadMode loadMode,
  List<SetValidationIssue> errors,
  List<SetValidationIssue> warnings,
) {
  final kilograms = _convertLoadToKilograms(enteredValue, unit);
  if (kilograms > SetValidationLimits.loadMaxKilograms) {
    errors.add(
      const SetValidationIssue(
        field: 'values.load.entered',
        dimension: DimensionId.load,
        rule: 'load_max_kilograms',
        message: 'Load must be no more than 1000 kg.',
        limit: SetValidationLimits.loadMaxKilograms,
      ),
    );
    return;
  }

  final warningLimit = loadMode == ExerciseLoadMode.assisted
      ? SetValidationLimits.assistedLoadWarnKilograms
      : SetValidationLimits.addedLoadWarnKilograms;
  if (kilograms > warningLimit) {
    warnings.add(
      SetValidationIssue(
        field: 'values.load.entered',
        dimension: DimensionId.load,
        rule: loadMode == ExerciseLoadMode.assisted
            ? 'assisted_load_improbable'
            : 'added_load_improbable',
        message: loadMode == ExerciseLoadMode.assisted
            ? 'Assisted load above 150 kg is improbable.'
            : 'Added load above 350 kg is improbable.',
        limit: warningLimit,
      ),
    );
  }
}

void _validateReps(
  double reps,
  List<SetValidationIssue> errors,
  List<SetValidationIssue> warnings,
) {
  if (reps.truncateToDouble() != reps) {
    errors.add(
      const SetValidationIssue(
        field: 'values.reps.entered',
        dimension: DimensionId.reps,
        rule: 'reps_integer',
        message: 'Reps must be an integer.',
        limit: 'integer',
      ),
    );
    return;
  }
  if (reps > SetValidationLimits.repsMax) {
    errors.add(
      const SetValidationIssue(
        field: 'values.reps.entered',
        dimension: DimensionId.reps,
        rule: 'reps_max',
        message: 'Reps must be no more than 10000.',
        limit: SetValidationLimits.repsMax,
      ),
    );
    return;
  }
  if (reps > SetValidationLimits.repsWarnAbove) {
    warnings.add(
      const SetValidationIssue(
        field: 'values.reps.entered',
        dimension: DimensionId.reps,
        rule: 'reps_improbable',
        message: 'Reps above 200 are improbable.',
        limit: SetValidationLimits.repsWarnAbove,
      ),
    );
  }
}

void _validateDuration(
  double seconds,
  List<SetValidationIssue> errors,
  List<SetValidationIssue> warnings,
) {
  if (seconds > SetValidationLimits.durationMaxSeconds) {
    errors.add(
      const SetValidationIssue(
        field: 'values.duration.entered',
        dimension: DimensionId.duration,
        rule: 'duration_max_seconds',
        message: 'Duration must be no more than 24 hours per set.',
        limit: SetValidationLimits.durationMaxSeconds,
      ),
    );
    return;
  }
  if (seconds > SetValidationLimits.durationWarnAboveSeconds) {
    warnings.add(
      const SetValidationIssue(
        field: 'values.duration.entered',
        dimension: DimensionId.duration,
        rule: 'duration_improbable',
        message: 'Duration above 4 hours is improbable.',
        limit: SetValidationLimits.durationWarnAboveSeconds,
      ),
    );
  }
}

void _validateDistance(
  double enteredValue,
  TrainingUnit unit,
  List<SetValidationIssue> errors,
  List<SetValidationIssue> warnings,
) {
  final kilometers = _convertDistanceToKilometers(enteredValue, unit);
  if (kilometers > SetValidationLimits.distanceMaxKilometers) {
    errors.add(
      const SetValidationIssue(
        field: 'values.distance.entered',
        dimension: DimensionId.distance,
        rule: 'distance_max_kilometers',
        message: 'Distance must be no more than 1000 km per set.',
        limit: SetValidationLimits.distanceMaxKilometers,
      ),
    );
    return;
  }
  if (kilometers > SetValidationLimits.distanceWarnAboveKilometers) {
    warnings.add(
      const SetValidationIssue(
        field: 'values.distance.entered',
        dimension: DimensionId.distance,
        rule: 'distance_improbable',
        message: 'Distance above 250 km is improbable.',
        limit: SetValidationLimits.distanceWarnAboveKilometers,
      ),
    );
  }
}

void _validateRpe(
  Object? rawValue,
  List<SetValidationIssue> errors,
) {
  if (rawValue == null) {
    return;
  }
  final value = _parseFiniteNonNegativeNumber(
    rawValue: rawValue,
    field: 'rpe',
    dimension: null,
    errors: errors,
  );
  if (value == null) {
    return;
  }
  if (_decimalPlaces(rawValue) > SetValidationLimits.maxDecimalPlaces) {
    errors.add(
      const SetValidationIssue(
        field: 'rpe',
        dimension: null,
        rule: 'numeric_max_five_decimal_places',
        message: 'Numeric values must use no more than 5 decimal places.',
        limit: SetValidationLimits.maxDecimalPlaces,
      ),
    );
    return;
  }
  if (value > SetValidationLimits.rpeMax) {
    errors.add(
      const SetValidationIssue(
        field: 'rpe',
        dimension: null,
        rule: 'rpe_range',
        message: 'RPE must be between 0 and 10.',
        limit: '0-10',
      ),
    );
    return;
  }
  if (!_isHalfStep(value)) {
    errors.add(
      const SetValidationIssue(
        field: 'rpe',
        dimension: null,
        rule: 'rpe_half_step',
        message: 'RPE must be a half-step value.',
        limit: SetValidationLimits.rpeStep,
      ),
    );
  }
}

void _validateSide(
  String? side,
  List<SetValidationIssue> errors,
) {
  if (side != null && !SetValidationLimits.allowedSides.contains(side)) {
    errors.add(
      const SetValidationIssue(
        field: 'side',
        dimension: null,
        rule: 'side_allowed',
        message: 'Side must be left or right.',
        limit: 'left|right',
      ),
    );
  }
}

void _validateCrossField(
  ExerciseType type,
  Map<DimensionId, _ParsedDimension> parsed,
  List<SetValidationIssue> warnings,
) {
  if (type.dimensions.length > 1 &&
      type.dimensions.every(
        (dimension) => parsed[dimension]?.metricValue == 0,
      )) {
    warnings.add(
      const SetValidationIssue(
        field: 'values',
        dimension: null,
        rule: 'all_zero_multi_dimension_set',
        message: 'All-zero sets on multi-dimension exercises are improbable.',
        limit: 'not all dimensions zero',
      ),
    );
  }

  final distance = parsed[DimensionId.distance]?.metricValue;
  final duration = parsed[DimensionId.duration]?.metricValue;
  if (distance != null && duration != null && distance > 0) {
    final speed =
        duration == 0 ? double.infinity : distance / (duration / 3600);
    if (speed > SetValidationLimits.speedWarnAboveKilometersPerHour) {
      warnings.add(
        const SetValidationIssue(
          field: 'values.distance',
          dimension: null,
          rule: 'implied_speed_improbable',
          message: 'Implied speed above 50 km/h is improbable.',
          limit: SetValidationLimits.speedWarnAboveKilometersPerHour,
        ),
      );
    }
  }
}

double? _parseFiniteNonNegativeNumber({
  required Object rawValue,
  required String field,
  required DimensionId? dimension,
  required List<SetValidationIssue> errors,
}) {
  final parsed = switch (rawValue) {
    final num value => value.toDouble(),
    final String value when value.trim().isNotEmpty =>
      double.tryParse(value.trim()),
    _ => null,
  };

  if (parsed == null || !parsed.isFinite) {
    errors.add(
      SetValidationIssue(
        field: field,
        dimension: dimension,
        rule: 'numeric_finite',
        message: 'Numeric value must be finite.',
        limit: 'finite',
      ),
    );
    return null;
  }
  if (parsed < SetValidationLimits.numericMin) {
    errors.add(
      SetValidationIssue(
        field: field,
        dimension: dimension,
        rule: 'numeric_non_negative',
        message: 'Numeric value must be non-negative.',
        limit: SetValidationLimits.numericMin,
      ),
    );
    return null;
  }

  return parsed;
}

SetValidationIssue? _validateUnit(
  DimensionId dimension,
  TrainingUnit unit,
  String field,
) {
  if (DimensionRegistry.byId(dimension).allowsUnit(unit)) {
    return null;
  }

  return SetValidationIssue(
    field: field,
    dimension: dimension,
    rule: 'unit_allowed_for_dimension',
    message: 'Unit is not valid for ${dimension.name}.',
    limit: DimensionRegistry.byId(dimension)
        .units
        .map((unit) => unit.name)
        .join('|'),
  );
}

double _convertLoadToKilograms(double value, TrainingUnit unit) {
  return unit == TrainingUnit.pound ? value * 0.45359237 : value;
}

double _convertDistanceToKilometers(double value, TrainingUnit unit) {
  return unit == TrainingUnit.mile ? value * 1.609344 : value;
}

int _decimalPlaces(Object rawValue) {
  final text = rawValue.toString().trim().toLowerCase();
  final exponentParts = text.split('e');
  final coefficient = exponentParts.first;
  final decimalPoint = coefficient.indexOf('.');
  final fractionalLength =
      decimalPoint == -1 ? 0 : coefficient.length - decimalPoint - 1;
  if (exponentParts.length == 1) {
    return fractionalLength;
  }

  final exponent = int.tryParse(exponentParts[1]);
  if (exponent == null) {
    return fractionalLength;
  }

  final places = fractionalLength - exponent;
  return places < 0 ? 0 : places;
}

bool _isHalfStep(double value) {
  return (value * 2).truncateToDouble() == value * 2;
}

class _ParsedDimension {
  const _ParsedDimension({
    required this.dimension,
    required this.field,
    required this.metricValue,
  });

  final DimensionId dimension;
  final String field;
  final double metricValue;
}
