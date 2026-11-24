import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/labs/lab_default_range.dart';
import '../../../domain/labs/lab_result.dart';
import '../../../domain/labs/lab_test.dart';
import '../../../domain/labs/lab_test_catalogue.generated.dart';
import '../../../domain/profile/user_profile.dart';
import '../../profile/controllers/profile_controller.dart';
import 'lab_results_providers.dart';

/// One collapsed Lab Result as the Lab Test detail shows it.
@immutable
class LabResultView {
  const LabResultView({
    required this.record,
    required this.labTest,
    required this.kind,
    required this.defaultRange,
    required this.position,
  });

  final LabResultRecord record;

  /// The catalogue entry, or null for "Other".
  final LabTest? labTest;

  /// How the result's Printed Range reads: the catalogue's kind, or
  /// `reference` for "Other".
  final PrintedRangeKind kind;

  /// The Default Range that applies, or null (always null for "Other" and
  /// whenever the result has a Printed Range).
  final DefaultRange? defaultRange;

  /// The position the result shows, and which range it came from, or null.
  final ({RangePosition position, RangeSource source})? position;
}

/// The collapsed results of one Lab Test, newest first (the repository's
/// order), each with its Printed Range kind, Default Range and position.
///
/// All of it is computed on read, per docs/designs/lab-results.md
/// "Default Ranges", and never stored: the Default Range from
/// [defaultRangeFor] with the profile's sex and the age at the `collected`
/// date at local midnight, and the position from [resultPosition]. A key this
/// build's catalogue lacks ("Other") parses its Printed Range as `reference`
/// and has no Default Range. Recomputed whenever the results or the User
/// Profile change, so saving sex and birth year in Profile shows the general
/// range straight away.
final labTestDetailProvider = Provider.autoDispose
    .family<AsyncValue<List<LabResultView>>, String>((ref, labTestKey) {
  final results = ref.watch(labResultsProvider(labTestKey));
  final profileState = ref.watch(profileControllerProvider);
  // A profile that failed to load reads as an empty one: the results still
  // show, without a Default Range, rather than not at all.
  final UserProfile? profile =
      profileState.hasError ? const UserProfile() : profileState.value;
  if (results.hasError) {
    return AsyncValue<List<LabResultView>>.error(
      results.error!,
      results.stackTrace ?? StackTrace.current,
    );
  }
  final records = results.value;
  if (records == null || profile == null) {
    return const AsyncValue<List<LabResultView>>.loading();
  }
  final labTest = labTestByKey(labTestKey);
  return AsyncValue<List<LabResultView>>.data(
    List<LabResultView>.unmodifiable(<LabResultView>[
      for (final record in records) labResultView(record, labTest, profile),
    ]),
  );
});

/// The [LabResultView] of [record] for [labTest] (null for "Other") and
/// [profile]: see [labTestDetailProvider].
LabResultView labResultView(
  LabResultRecord record,
  LabTest? labTest,
  UserProfile profile,
) {
  final lab = record.lab;
  final kind = labTest?.printedRangeKind ?? PrintedRangeKind.reference;
  final collected = collectedLocal(lab.collected).dateTime;
  final defaultRange = labTest == null
      ? null
      : defaultRangeFor(
          labTest,
          lab.printedRange,
          profile.sex,
          profile
              .ageAt(DateTime(collected.year, collected.month, collected.day)),
        );
  final limit = lab.limit;
  final scalar = record.scalarValue;
  final LabValue? value = limit != null
      ? LabLimitValue(limit)
      : scalar != null
          ? LabNumber(scalar)
          : null;
  return LabResultView(
    record: record,
    labTest: labTest,
    kind: kind,
    defaultRange: defaultRange,
    position: value == null
        ? null
        : resultPosition(
            value: value,
            printedRange: lab.printedRange,
            kind: kind,
            defaultRange: defaultRange,
          ),
  );
}
