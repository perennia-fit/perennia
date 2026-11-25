/// The Lab Result collapse (docs/designs/lab-results.md, "Result identity and
/// the collapse"). Pure; the TypeScript twin is `collapseLabResults` in
/// `apps/server/src/lab-results.ts`, and the m43 golden vectors pin both.
library;

import 'lab_result.dart';

/// One stored Lab Result, as the collapse needs it. [lab] is the decoded `lab`
/// object ([decodeLab]), null when it does not decode.
class LabReadingRef {
  const LabReadingRef({
    required this.id,
    required this.labTestKey,
    required this.lab,
    required this.atTime,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;

  /// The `labTestKey` of the reading's Metric. Identity is per Lab Test, not
  /// per Metric row, so readings of two Lab Metrics with one key share groups.
  final String labTestKey;

  final LabFields? lab;
  final DateTime atTime;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Keeps one row per Lab Result and returns them newest first.
///
/// 1. Rows with a [LabReadingRef.deletedAt] are dropped.
/// 2. A row with a null [LabReadingRef.lab] is its own group, keyed by its id.
/// 3. The rest are grouped by identity: the Lab Test key and the
///    `lab.collected` string.
/// 4. Each group keeps one row: `final` beats `interim` (and an unknown status,
///    which ranks as interim); then the later `updatedAt`; then the greater id
///    by code-unit order ([String.compareTo]).
/// 5. The kept rows are returned newest first by `atTime`; on an equal
///    `atTime`, the greater id first.
///
/// `updatedAt` is compared in whole epoch seconds, the floor of its
/// milliseconds divided by 1000, never finer. The app stores `updatedAt` to the
/// second and the server to the millisecond, so the same row can carry
/// `…:05` on one side and `…:05.731` on the other; a finer comparison would let
/// the app and an Agent keep different rows of one group. Within one second the
/// id decides, which both sides see identically. `atTime` is ordered by epoch
/// milliseconds, the precision both sides parse, for the same reason.
List<LabReadingRef> collapseLabResults(List<LabReadingRef> readings) {
  final kept = <Object, LabReadingRef>{};
  for (final reading in readings) {
    if (reading.deletedAt != null) continue;
    final lab = reading.lab;
    final Object key =
        lab == null ? (reading.id,) : (reading.labTestKey, lab.collected);
    final current = kept[key];
    if (current == null || _beats(reading, current)) {
      kept[key] = reading;
    }
  }
  return kept.values.toList()
    ..sort((a, b) {
      final byTime = b.atTime.millisecondsSinceEpoch
          .compareTo(a.atTime.millisecondsSinceEpoch);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
}

bool _beats(LabReadingRef candidate, LabReadingRef current) {
  final byStatus = _statusRank(candidate).compareTo(_statusRank(current));
  if (byStatus != 0) return byStatus > 0;
  final bySecond = _epochSecond(candidate.updatedAt)
      .compareTo(_epochSecond(current.updatedAt));
  if (bySecond != 0) return bySecond > 0;
  return candidate.id.compareTo(current.id) > 0;
}

int _statusRank(LabReadingRef reading) =>
    reading.lab!.reportStatus.isFinal ? 1 : 0;

/// Whole epoch seconds, floored, so a time before 1970 still rounds down.
int _epochSecond(DateTime value) {
  final ms = value.millisecondsSinceEpoch;
  return (ms - ms % 1000) ~/ 1000;
}
