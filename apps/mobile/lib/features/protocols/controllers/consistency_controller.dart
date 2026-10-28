import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import 'protocols_day_controller.dart'
    show protocolPlanRepositoryProvider, protocolsClockProvider;

/// The Consistency view's range presets (file 41): the last 7, 30, 90 or
/// 365 days, each including today, or a custom range.
enum ConsistencyRangePreset {
  last7(7),
  last30(30),
  last90(90),
  last365(365),
  custom(null);

  const ConsistencyRangePreset(this.days);

  /// How many days the preset covers, ending today; null for [custom].
  final int? days;
}

/// The Consistency view's chosen range: [from] through [to], both inclusive,
/// and the [today] it was chosen against. In-memory only, never stored.
final class ConsistencyRangeSelection {
  const ConsistencyRangeSelection({
    required this.preset,
    required this.from,
    required this.to,
    required this.today,
  });

  /// The last [preset]'s days, ending on [today].
  factory ConsistencyRangeSelection.preset(
    ConsistencyRangePreset preset,
    ProtocolDayDate today,
  ) {
    final days = preset.days;
    if (days == null) {
      throw ArgumentError.value(preset, 'preset', 'Not a fixed-length range.');
    }
    return ConsistencyRangeSelection(
      preset: preset,
      from: today.addDays(-(days - 1)),
      to: today,
      today: today,
    );
  }

  final ConsistencyRangePreset preset;
  final ProtocolDayDate from;
  final ProtocolDayDate to;

  /// The caller's local date when the range was chosen: the repository's
  /// `today`, which decides "Pending" against "Not logged" (D6).
  final ProtocolDayDate today;

  @override
  bool operator ==(Object other) =>
      other is ConsistencyRangeSelection &&
      other.preset == preset &&
      other.from == from &&
      other.to == to &&
      other.today == today;

  @override
  int get hashCode => Object.hash(preset, from, to, today);
}

/// The Consistency view's range state: the last 30 days, including today,
/// until the user picks another (file 41). One range serves every tab of a
/// Protocol's view. Disposed with the view, so it opens on the default again.
final consistencyRangeControllerProvider = NotifierProvider.autoDispose<
    ConsistencyRangeController, ConsistencyRangeSelection>(
  ConsistencyRangeController.new,
);

/// Holds the chosen range. "Today" is read from [protocolsClockProvider],
/// the Protocols surfaces' one clock, when the view opens and on every pick.
class ConsistencyRangeController extends Notifier<ConsistencyRangeSelection> {
  @override
  ConsistencyRangeSelection build() => ConsistencyRangeSelection.preset(
        ConsistencyRangePreset.last30,
        _today(),
      );

  ProtocolDayDate _today() =>
      ProtocolDayDate.fromDateTime(ref.read(protocolsClockProvider)());

  /// Picks the last 7, 30, 90 or 365 days, ending today.
  void selectPreset(ConsistencyRangePreset preset) {
    state = ConsistencyRangeSelection.preset(preset, _today());
  }

  /// Picks [from] through [to]. The view never reads a day still to come, so
  /// an end after today is moved to today, and a range longer than
  /// [maxConsistencyRangeDays] keeps its last [maxConsistencyRangeDays] days.
  void selectCustom(ProtocolDayDate from, ProtocolDayDate to) {
    final today = _today();
    var end = to.compareTo(today) > 0 ? today : to;
    var start = from.compareTo(end) > 0 ? end : from;
    final earliest = end.addDays(-(maxConsistencyRangeDays - 1));
    if (start.compareTo(earliest) < 0) {
      start = earliest;
    }
    state = ConsistencyRangeSelection(
      preset: ConsistencyRangePreset.custom,
      from: start,
      to: end,
      today: today,
    );
  }
}

/// One Compound's Consistency over the chosen range: its PlanDays, Day
/// Statuses and Doses, re-read whenever the range or the plan or Doses
/// change. Derived on read, never stored.
final consistencyProvider =
    StreamProvider.autoDispose.family<ConsistencyRange, String>(
  (ref, compoundId) {
    final range = ref.watch(consistencyRangeControllerProvider);
    return ref.watch(protocolPlanRepositoryProvider).watchConsistency(
          compoundId,
          range.from,
          range.to,
          today: range.today,
        );
  },
);
