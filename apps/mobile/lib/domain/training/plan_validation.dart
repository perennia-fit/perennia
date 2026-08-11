/// Validation for the authored plan layer (`Workout Template` prescriptions
/// `Template Group`s, and Routine Cadences).
///
/// Fixed prescription values use [validateSetValues] verbatim. Plan-specific
/// structure adds repeat and rest-after rules. The TypeScript twin lives in
/// `apps/server/src/agent-validation.ts`; both consume the shared
/// `m33-plan-validation.json` golden vector.
library;

import 'set_validation.dart';
import 'training_dimensions.dart';

class PrescriptionValidationLimits {
  const PrescriptionValidationLimits._();

  static const int repeatMin = 1;
  static const int repeatWarnAbove = 100;
  static const int restAfterSecondsMin = 0;
}

class TemplateGroupValidationLimits {
  const TemplateGroupValidationLimits._();

  static const int roundsMin = 1;
  static const int membersMin = 2;
  static const String colorHexFormat = '#RRGGBB';
}

class RoutineCadenceValidationLimits {
  const RoutineCadenceValidationLimits._();

  static const List<String> cadenceKinds = <String>['weekly', 'rotating'];
  static const int rotatingWindowMin = 1;
  static const int rotatingWindowWarnAbove = 31;
  static const int weeklySlotMin = 1;
  static const int weeklySlotMax = 7;
  static const int routineEntrySlotMin = 1;
}

SetValidationResult validatePrescription({
  required String mode,
  required Iterable<DimensionId> dimensions,
  required ExerciseLoadMode loadMode,
  required num repeat,
  required num? restAfterSeconds,
  required Iterable<SetDimensionValue> values,
}) {
  final errors = <SetValidationIssue>[];
  final warnings = <SetValidationIssue>[];
  final dimensionList = List<DimensionId>.unmodifiable(dimensions);
  final repeatValue = repeat.toDouble();
  final repeatIsInteger =
      repeatValue.isFinite && repeatValue.truncateToDouble() == repeatValue;

  if (dimensionList.toSet().length != dimensionList.length) {
    errors.add(
      const SetValidationIssue(
        field: 'dimensions',
        dimension: null,
        rule: 'prescription_dimensions_duplicate',
        message: 'Prescription dimensions must be unique.',
        limit: 'unique',
      ),
    );
  }

  if (mode != 'fixed' && mode != 'copyPrevious') {
    errors.add(
      const SetValidationIssue(
        field: 'mode',
        dimension: null,
        rule: 'prescription_mode_invalid',
        message: 'Mode must be fixed or copyPrevious.',
        limit: 'fixed|copyPrevious',
      ),
    );
  }

  if (!repeatIsInteger) {
    if (repeatValue < PrescriptionValidationLimits.repeatMin) {
      errors.add(_repeatMinIssue());
    } else {
      errors.add(
        const SetValidationIssue(
          field: 'repeat',
          dimension: null,
          rule: 'prescription_repeat_integer',
          message: 'Repeat must be an integer.',
          limit: 'integer',
        ),
      );
    }
  } else if (repeatValue < PrescriptionValidationLimits.repeatMin) {
    errors.add(_repeatMinIssue());
  } else if (repeatValue > PrescriptionValidationLimits.repeatWarnAbove) {
    warnings.add(
      const SetValidationIssue(
        field: 'repeat',
        dimension: null,
        rule: 'prescription_repeat_improbable',
        message: 'Repeat above 100 is improbable.',
        limit: PrescriptionValidationLimits.repeatWarnAbove,
      ),
    );
  }

  if (restAfterSeconds != null) {
    final restAfterValue = restAfterSeconds.toDouble();
    if (!restAfterValue.isFinite) {
      errors.add(
        const SetValidationIssue(
          field: 'restAfterSeconds',
          dimension: null,
          rule: 'prescription_rest_after_finite',
          message: 'Rest after must be finite.',
          limit: 'finite',
        ),
      );
    } else if (restAfterValue <
        PrescriptionValidationLimits.restAfterSecondsMin) {
      errors.add(
        const SetValidationIssue(
          field: 'restAfterSeconds',
          dimension: null,
          rule: 'prescription_rest_after_non_negative',
          message: 'Rest after must not be negative.',
          limit: PrescriptionValidationLimits.restAfterSecondsMin,
        ),
      );
    }
  }

  if (mode == 'fixed') {
    final valueResult = validateSetValues(
      // ExerciseType itself rejects duplicates. Build it from the stable unique
      // projection so validation returns the deterministic issue above instead
      // of throwing before Dart and TypeScript can produce the same verdict.
      type: ExerciseType(dimensionList.toSet()),
      loadMode: loadMode,
      values: values,
    );
    errors.addAll(valueResult.errors);
    warnings.addAll(valueResult.warnings);
  }

  return SetValidationResult(
    errors: List<SetValidationIssue>.unmodifiable(errors),
    warnings: List<SetValidationIssue>.unmodifiable(warnings),
  );
}

SetValidationIssue _repeatMinIssue() {
  return const SetValidationIssue(
    field: 'repeat',
    dimension: null,
    rule: 'prescription_repeat_min',
    message: 'Repeat must be at least 1.',
    limit: PrescriptionValidationLimits.repeatMin,
  );
}

/// Validates the portable value-shape of one authored `Template Group`.
///
/// Relationship checks that require storage (the members exist, belong to the
/// same Workout Template, and are not already grouped) remain repository
/// invariants. This shared validator covers the fields that Dart and
/// TypeScript can judge identically before either layer writes anything.
SetValidationResult validateTemplateGroup({
  required String name,
  required String colorHex,
  required num rounds,
  required Iterable<String> memberIds,
}) {
  final errors = <SetValidationIssue>[];
  final normalizedMemberIds =
      memberIds.map((memberId) => memberId.trim()).toList(growable: false);

  if (name.trim().isEmpty) {
    errors.add(
      const SetValidationIssue(
        field: 'name',
        dimension: null,
        rule: 'template_group_name_required',
        message: 'Template Group name is required.',
        limit: 'non-empty',
      ),
    );
  }

  if (!_templateGroupColorHexPattern.hasMatch(colorHex.trim())) {
    errors.add(
      const SetValidationIssue(
        field: 'colorHex',
        dimension: null,
        rule: 'template_group_color_hex',
        message: 'Template Group color must use #RRGGBB.',
        limit: TemplateGroupValidationLimits.colorHexFormat,
      ),
    );
  }

  final roundsValue = rounds.toDouble();
  if (!roundsValue.isFinite) {
    errors.add(
      const SetValidationIssue(
        field: 'rounds',
        dimension: null,
        rule: 'template_group_rounds_finite',
        message: 'Rounds must be finite.',
        limit: 'finite',
      ),
    );
  } else if (roundsValue < TemplateGroupValidationLimits.roundsMin) {
    errors.add(_templateGroupRoundsMinIssue());
  } else if (roundsValue.truncateToDouble() != roundsValue) {
    errors.add(
      const SetValidationIssue(
        field: 'rounds',
        dimension: null,
        rule: 'template_group_rounds_integer',
        message: 'Rounds must be an integer.',
        limit: 'integer',
      ),
    );
  }

  final nonEmptyMemberIds = normalizedMemberIds
      .where((memberId) => memberId.isNotEmpty)
      .toList(growable: false);
  if (nonEmptyMemberIds.length != normalizedMemberIds.length) {
    errors.add(
      const SetValidationIssue(
        field: 'memberIds',
        dimension: null,
        rule: 'template_group_member_id_required',
        message: 'Template Group member IDs must not be empty.',
        limit: 'non-empty',
      ),
    );
  }

  if (nonEmptyMemberIds.toSet().length != nonEmptyMemberIds.length) {
    errors.add(
      const SetValidationIssue(
        field: 'memberIds',
        dimension: null,
        rule: 'template_group_members_unique',
        message: 'Template Group members must be unique.',
        limit: 'unique',
      ),
    );
  }

  if (normalizedMemberIds.length < TemplateGroupValidationLimits.membersMin) {
    errors.add(
      const SetValidationIssue(
        field: 'memberIds',
        dimension: null,
        rule: 'template_group_members_min',
        message: 'Template Group must contain at least 2 members.',
        limit: TemplateGroupValidationLimits.membersMin,
      ),
    );
  }

  return SetValidationResult(
    errors: List<SetValidationIssue>.unmodifiable(errors),
    warnings: const <SetValidationIssue>[],
  );
}

SetValidationIssue _templateGroupRoundsMinIssue() {
  return const SetValidationIssue(
    field: 'rounds',
    dimension: null,
    rule: 'template_group_rounds_min',
    message: 'Rounds must be at least 1.',
    limit: TemplateGroupValidationLimits.roundsMin,
  );
}

final RegExp _templateGroupColorHexPattern = RegExp(
  r'^#[0-9a-fA-F]{6}$',
);

/// Validates a Routine's optional Cadence together with its active Entry slots.
///
/// A null [cadenceKind] is the canonical no-Cadence representation. Duplicate
/// slots are valid because several Workout Templates may share one slot.
SetValidationResult validateRoutineCadence({
  required String? cadenceKind,
  required num? cadenceWindow,
  required Iterable<num?> slots,
}) {
  final errors = <SetValidationIssue>[];
  final warnings = <SetValidationIssue>[];
  final slotList = slots.toList(growable: false);

  void addError(SetValidationIssue issue) {
    if (!errors.any((existing) => existing.rule == issue.rule)) {
      errors.add(issue);
    }
  }

  final kindIsValid = cadenceKind == null ||
      RoutineCadenceValidationLimits.cadenceKinds.contains(cadenceKind);
  if (!kindIsValid) {
    addError(
      const SetValidationIssue(
        field: 'cadenceKind',
        dimension: null,
        rule: 'cadence_kind_invalid',
        message: 'Cadence must be weekly, rotating, or absent.',
        limit: 'weekly|rotating|null',
      ),
    );
  }

  if (cadenceKind == null) {
    if (cadenceWindow != null) {
      addError(_cadenceWindowForbiddenIssue());
    }
    if (slotList.any((slot) => slot != null)) {
      addError(
        const SetValidationIssue(
          field: 'slots',
          dimension: null,
          rule: 'routine_entry_slot_requires_cadence',
          message: 'Routine Entry slots require a Cadence.',
          limit: 'cadence-required',
        ),
      );
    }
  } else if (kindIsValid) {
    double? validRotatingWindow;
    if (cadenceKind == 'weekly') {
      if (cadenceWindow != null) {
        addError(_cadenceWindowForbiddenIssue());
      }
    } else {
      if (cadenceWindow == null) {
        addError(
          const SetValidationIssue(
            field: 'cadenceWindow',
            dimension: null,
            rule: 'cadence_window_required',
            message: 'A rotating Cadence requires a window.',
            limit: 'required',
          ),
        );
      } else {
        final value = cadenceWindow.toDouble();
        if (!value.isFinite) {
          addError(
            const SetValidationIssue(
              field: 'cadenceWindow',
              dimension: null,
              rule: 'cadence_window_finite',
              message: 'Cadence window must be finite.',
              limit: 'finite',
            ),
          );
        } else if (value < RoutineCadenceValidationLimits.rotatingWindowMin) {
          addError(
            const SetValidationIssue(
              field: 'cadenceWindow',
              dimension: null,
              rule: 'cadence_window_min',
              message: 'Cadence window must be at least 1.',
              limit: RoutineCadenceValidationLimits.rotatingWindowMin,
            ),
          );
        } else if (value.truncateToDouble() != value) {
          addError(
            const SetValidationIssue(
              field: 'cadenceWindow',
              dimension: null,
              rule: 'cadence_window_integer',
              message: 'Cadence window must be an integer.',
              limit: 'integer',
            ),
          );
        } else {
          validRotatingWindow = value;
          if (value > RoutineCadenceValidationLimits.rotatingWindowWarnAbove) {
            warnings.add(
              const SetValidationIssue(
                field: 'cadenceWindow',
                dimension: null,
                rule: 'cadence_window_improbable',
                message: 'A rotating Cadence above 31 slots is improbable.',
                limit: RoutineCadenceValidationLimits.rotatingWindowWarnAbove,
              ),
            );
          }
        }
      }
    }

    for (final slot in slotList) {
      if (slot == null) {
        addError(
          const SetValidationIssue(
            field: 'slots',
            dimension: null,
            rule: 'routine_entry_slot_required',
            message: 'Every Routine Entry requires a slot under a Cadence.',
            limit: 'required',
          ),
        );
        continue;
      }
      final value = slot.toDouble();
      if (!value.isFinite) {
        addError(
          const SetValidationIssue(
            field: 'slots',
            dimension: null,
            rule: 'routine_entry_slot_finite',
            message: 'Routine Entry slots must be finite.',
            limit: 'finite',
          ),
        );
        continue;
      }
      if (value.truncateToDouble() != value) {
        addError(
          const SetValidationIssue(
            field: 'slots',
            dimension: null,
            rule: 'routine_entry_slot_integer',
            message: 'Routine Entry slots must be integers.',
            limit: 'integer',
          ),
        );
        continue;
      }
      final max = cadenceKind == 'weekly'
          ? RoutineCadenceValidationLimits.weeklySlotMax.toDouble()
          : validRotatingWindow;
      final min = cadenceKind == 'weekly'
          ? RoutineCadenceValidationLimits.weeklySlotMin
          : RoutineCadenceValidationLimits.routineEntrySlotMin;
      if (value < min || (max != null && value > max)) {
        addError(
          SetValidationIssue(
            field: 'slots',
            dimension: null,
            rule: 'routine_entry_slot_range',
            message: 'Routine Entry slot is outside the Cadence window.',
            limit: max == null ? 'valid-window' : '1..${max.toInt()}',
          ),
        );
      }
    }
  }

  return SetValidationResult(
    errors: List<SetValidationIssue>.unmodifiable(errors),
    warnings: List<SetValidationIssue>.unmodifiable(warnings),
  );
}

SetValidationIssue _cadenceWindowForbiddenIssue() {
  return const SetValidationIssue(
    field: 'cadenceWindow',
    dimension: null,
    rule: 'cadence_window_forbidden',
    message: 'Only a rotating Cadence may have a window.',
    limit: 'null',
  );
}
