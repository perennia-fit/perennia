/// The Meal time sheet (docs/designs/meal-logging.md §6): the date and time
/// pickers, the time-shift buttons, the Meal Type list and the future-time
/// confirmation, opened from the Meal screen's header.
///
/// It reuses the Dose edit pattern (`protocols_day_view.dart`: `_pickDate`,
/// `_pickTime`, `_clock`, `_instant`): a saved Meal's clock is read and set
/// at its frozen UTC offset, so a Meal logged in another zone is corrected
/// where it was eaten; a new Meal (and a Meal written before offsets were
/// recorded) reads in the device's zone.
///
/// Every choice applies at once. On a new Meal it changes the controller's
/// pending Meal, which nothing writes until the first pick; on a saved Meal
/// each change is one `updateMealTime` or `updateMealType` call, so one
/// Batch.
///
/// Like the Meal screen, it reads no Dose, Protocols or Workout data (§6).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/common/local_clock.dart';
import '../../../domain/nutrition/meal_type_proposal.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/meal_screen_controller.dart';
import '../controllers/nutrition_day_controller.dart' show mealTypeListProvider;

/// [clock] as a time of day at the device's 12- or 24-hour preference. The
/// fields of [clock] are read as they are: pass a Meal's `clock` (its time
/// at its frozen offset), never `startedAt.toLocal()`.
String formatMealClock(BuildContext context, DateTime clock) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(clock),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// The active Meal Types in list order: by sort order, then id.
List<MealTypeRecord> activeMealTypes(List<MealTypeRecord> mealTypes) {
  return mealTypes.where((type) => type.deletedAt == null).toList()
    ..sort((a, b) {
      final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
      return bySortOrder != 0 ? bySortOrder : a.id.compareTo(b.id);
    });
}

/// Opens the time sheet for the Meal screen keyed by [args].
///
/// [pendingDate] holds a date picked without a time: on a new Meal on
/// another day before a time is chosen, and on a saved `date`-precision Meal.
/// Picking only a date moves the sheet's day but chooses no time (CUJ 5); the
/// time picker then sets both. The Meal screen owns it, so the date survives
/// the sheet closing and opening again.
Future<void> showMealTimeSheet(
  BuildContext context, {
  required MealScreenArgs args,
  required ValueNotifier<NutritionDayDate?> pendingDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => MealTimeSheet(args: args, pendingDate: pendingDate),
  );
}

/// The time sheet's body; see [showMealTimeSheet].
class MealTimeSheet extends ConsumerStatefulWidget {
  const MealTimeSheet({
    super.key,
    required this.args,
    required this.pendingDate,
  });

  final MealScreenArgs args;
  final ValueNotifier<NutritionDayDate?> pendingDate;

  static const dateHeaderKey = Key('nutrition.mealTime.dateHeader');
  static const dateRowKey = Key('nutrition.mealTime.date');
  static const timeRowKey = Key('nutrition.mealTime.time');

  /// The `−15 min`, `−30 min` and `−1 h` buttons, by their minutes.
  static Key shiftButtonKey(int minutes) {
    return Key('nutrition.mealTime.shift-$minutes');
  }

  static Key mealTypeKey(String name) {
    return Key('nutrition.mealTime.type-$name');
  }

  @override
  ConsumerState<MealTimeSheet> createState() => _MealTimeSheetState();
}

class _MealTimeSheetState extends ConsumerState<MealTimeSheet> {
  /// The day the sheet compares its chosen date with: the day a new Meal
  /// screen opened for, or the saved Meal's day when the sheet opened. The
  /// header shows the chosen date only when it differs (§6).
  NutritionDayDate? _openedFor;

  MealScreenArgs get _args => widget.args;

  MealScreenController get _notifier =>
      ref.read(mealScreenControllerProvider(_args).notifier);

  DateTime _now() => ref.read(mealScreenClockProvider)();

  @override
  void initState() {
    super.initState();
    widget.pendingDate.addListener(_onPendingDateChanged);
  }

  @override
  void dispose() {
    widget.pendingDate.removeListener(_onPendingDateChanged);
    super.dispose();
  }

  void _onPendingDateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mealScreenControllerProvider(_args));
    final mealTypes = activeMealTypes(
      ref.watch(mealTypeListProvider).value ?? const <MealTypeRecord>[],
    );
    final savedMealId = state.savedMealId;
    MealRecord? meal;
    if (state.isSaved && savedMealId != null) {
      meal = ref.watch(savedMealProvider(savedMealId)).value?.meal;
      if (meal == null) {
        return const SizedBox.shrink();
      }
    }
    final view = _SheetView.of(
      state: state,
      meal: meal,
      pendingDate: widget.pendingDate.value,
      now: _now(),
      mealTypes: mealTypes,
    );
    _openedFor ??= state.day ?? view.chosenDate;

    final l10n = context.l10n;
    final colors = context.colors;
    final textStyles = context.textStyles;
    final enabled = !state.writing;

    final String timeValue;
    if (view.chosenClock case final clock?) {
      timeValue = formatMealClock(context, clock);
    } else if (view.isNow) {
      timeValue = l10n.mealHeaderNow;
    } else if (meal != null) {
      timeValue = l10n.mealTimeNotRecorded;
    } else {
      timeValue = l10n.mealHeaderChooseTime;
    }
    final materialL10n = MaterialLocalizations.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppDimens.base,
        right: AppDimens.base,
        top: AppDimens.base,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (view.chosenDate != _openedFor) ...[
            Text(
              materialL10n.formatFullDate(view.chosenDate.toLocalDateTime()),
              key: MealTimeSheet.dateHeaderKey,
              style: textStyles.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDimens.dense),
          ],
          _SheetRow(
            rowKey: MealTimeSheet.dateRowKey,
            icon: Icons.calendar_today_outlined,
            label: l10n.mealTimeSheetDate,
            value: materialL10n.formatMediumDate(
              view.chosenDate.toLocalDateTime(),
            ),
            onTap: enabled ? () => unawaited(_pickDate(view)) : null,
          ),
          _SheetRow(
            rowKey: MealTimeSheet.timeRowKey,
            icon: Icons.access_time,
            label: l10n.mealTimeSheetTime,
            value: timeValue,
            onTap: enabled ? () => unawaited(_pickTime(view)) : null,
          ),
          if (view.chosenDate == view.today) ...[
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final shift in <(int, String, String)>[
                  (15, l10n.mealTimeShift15, l10n.mealTimeShift15Semantics),
                  (30, l10n.mealTimeShift30, l10n.mealTimeShift30Semantics),
                  (60, l10n.mealTimeShift60, l10n.mealTimeShift60Semantics),
                ])
                  OutlinedButton(
                    key: MealTimeSheet.shiftButtonKey(shift.$1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      minimumSize: const Size(
                        AppDimens.touchTarget,
                        AppDimens.touchTarget,
                      ),
                    ),
                    onPressed: enabled
                        ? () => unawaited(
                              _shift(view, Duration(minutes: shift.$1)),
                            )
                        : null,
                    child: Text(shift.$2, semanticsLabel: shift.$3),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppDimens.base),
          Text(
            l10n.mealTimeSheetType,
            style: textStyles.label.copyWith(color: colors.textSecondary),
          ),
          for (final type in mealTypes)
            ListTile(
              key: MealTimeSheet.mealTypeKey(type.name),
              contentPadding: EdgeInsets.zero,
              minTileHeight: AppDimens.touchTarget,
              enabled: enabled,
              selected: type.name == view.markedType,
              selectedColor: colors.textPrimary,
              textColor: colors.textPrimary,
              title: Text(type.name),
              trailing: type.name == view.markedType
                  ? Icon(Icons.check, color: colors.textPrimary)
                  : null,
              onTap: () => unawaited(_pickType(type.name)),
            ),
        ],
      ),
    );
  }

  /// Moves the Meal to another date, keeping its time of day. The picker
  /// ends at today read at the Meal's offset (the device zone for a new
  /// Meal), or at the chosen date when that is later, so it never offers a
  /// day that hasn't happened.
  ///
  /// Without a chosen time (a new Meal on another day, or a saved `date`
  /// Meal) the date only moves the sheet's day: a time counts as chosen only
  /// once the time picker is confirmed (CUJ 5).
  Future<void> _pickDate(_SheetView view) async {
    final current = view.chosenDate.toLocalDateTime();
    final today = view.today.toLocalDateTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: current.isAfter(today) ? current : today,
    );
    if (picked == null || !mounted) {
      return;
    }
    final day = NutritionDayDate(
      year: picked.year,
      month: picked.month,
      day: picked.day,
    );
    final timeOfDay = view.chosenClock ?? (view.isNow ? view.todayClock : null);
    if (timeOfDay == null) {
      widget.pendingDate.value = day;
      return;
    }
    if (view.isNow && day == view.today) {
      // Still now: nothing to change.
      return;
    }
    await _applyClock(
      view,
      day: day,
      hour: timeOfDay.hour,
      minute: timeOfDay.minute,
    );
  }

  Future<void> _pickTime(_SheetView view) async {
    final initial = view.chosenClock ?? view.todayClock;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) {
      return;
    }
    await _applyClock(
      view,
      day: view.chosenDate,
      hour: picked.hour,
      minute: picked.minute,
    );
  }

  /// A time-shift button: now minus [amount], replacing any earlier choice
  /// (§6). A result before midnight moves the Meal to the previous day.
  Future<void> _shift(_SheetView view, Duration amount) async {
    final instant = _now().subtract(amount);
    if (!await _confirmTime(view, instant)) {
      return;
    }
    widget.pendingDate.value = null;
    if (view.meal == null) {
      _notifier.shiftTime(amount);
    } else {
      await _notifier.changeTime(instant);
    }
  }

  /// Applies the clock [day] [hour]:[minute], read at the Meal's offset: the
  /// pending time of a new Meal, or one `updateMealTime` on a saved one.
  Future<void> _applyClock(
    _SheetView view, {
    required NutritionDayDate day,
    required int hour,
    required int minute,
  }) async {
    final instant = _instant(view.offsetMinutes, day, hour, minute);
    if (!await _confirmTime(view, instant)) {
      return;
    }
    widget.pendingDate.value = null;
    if (view.meal == null) {
      _notifier.setPendingTime(instant);
    } else {
      await _notifier.changeTime(instant);
    }
  }

  /// The moment the clock [day] [hour]:[minute] names at [offsetMinutes],
  /// or in the device's zone for a null offset (a new Meal, or one written
  /// before offsets were recorded): the Dose edit's `_clock` and `_instant`.
  DateTime _instant(
    int? offsetMinutes,
    NutritionDayDate day,
    int hour,
    int minute,
  ) {
    if (offsetMinutes == null) {
      return DateTime(day.year, day.month, day.day, hour, minute);
    }
    return DateTime.utc(day.year, day.month, day.day, hour, minute)
        .subtract(Duration(minutes: offsetMinutes));
  }

  /// Runs the shared Meal-time validator on [instant] before it applies.
  /// When it warns (more than 5 minutes ahead, §8) the user confirms; Cancel
  /// applies nothing.
  Future<bool> _confirmTime(_SheetView view, DateTime instant) async {
    final type = view.meal?.mealType ??
        view.pendingMealType ??
        proposeMealType(
          clockAtOffset(instant, view.offsetMinutes),
          view.mealTypes,
        );
    final result = validateMealTime(
      MealTimeInput(startedAt: instant, mealType: type),
      now: _now(),
    );
    if (result.warnings.isEmpty) {
      return true;
    }
    final l10n = context.l10n;
    final timeText = formatMealClock(
      context,
      clockAtOffset(instant, view.offsetMinutes),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.mealFutureTimeTitle),
          content: Text(l10n.mealFutureTimeBody(timeText)),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.mealFutureTimeConfirm),
            ),
          ],
        );
      },
    );
    return confirmed == true && mounted;
  }

  Future<void> _pickType(String name) async {
    final state = ref.read(mealScreenControllerProvider(_args));
    if (state.isSaved) {
      await _notifier.changeType(name);
    } else {
      _notifier.setPendingMealType(name);
    }
  }
}

/// What the sheet shows, worked out once per build from the controller's
/// state and the saved Meal.
final class _SheetView {
  const _SheetView({
    required this.meal,
    required this.offsetMinutes,
    required this.todayClock,
    required this.today,
    required this.chosenClock,
    required this.chosenDate,
    required this.isNow,
    required this.pendingMealType,
    required this.markedType,
    required this.mealTypes,
  });

  factory _SheetView.of({
    required MealScreenState state,
    required MealRecord? meal,
    required NutritionDayDate? pendingDate,
    required DateTime now,
    required List<MealTypeRecord> mealTypes,
  }) {
    final offset = meal?.timezoneOffsetMinutes;
    final todayClock = clockAtOffset(now, offset);
    final today = _dayOf(todayClock);
    if (meal != null) {
      final chosenClock =
          meal.timePrecision == MealTimePrecision.instant ? meal.clock : null;
      return _SheetView(
        meal: meal,
        offsetMinutes: offset,
        todayClock: todayClock,
        today: today,
        chosenClock: chosenClock,
        chosenDate: chosenClock == null
            ? pendingDate ?? meal.localDate
            : _dayOf(chosenClock),
        isNow: false,
        pendingMealType: null,
        markedType: meal.mealType,
        mealTypes: mealTypes,
      );
    }
    final pendingStart = state.pendingStart;
    final chosenClock =
        pendingStart == null ? null : clockAtOffset(pendingStart, null);
    final isNow = state.timeChosen && pendingStart == null;
    final proposal = state.timeChosen
        ? proposeMealType(chosenClock ?? todayClock, mealTypes)
        : null;
    return _SheetView(
      meal: null,
      offsetMinutes: null,
      todayClock: todayClock,
      today: today,
      chosenClock: chosenClock,
      chosenDate: chosenClock != null
          ? _dayOf(chosenClock)
          : isNow
              ? today
              : pendingDate ?? state.day!,
      isNow: isNow,
      pendingMealType: state.pendingMealType,
      markedType: state.pendingMealType ?? proposal,
      mealTypes: mealTypes,
    );
  }

  /// The saved Meal; null on a new one.
  final MealRecord? meal;

  /// The offset the Meal's clock reads at: the saved Meal's frozen offset,
  /// or null (the device zone) for a new Meal.
  final int? offsetMinutes;

  /// Now, read at [offsetMinutes].
  final DateTime todayClock;
  final NutritionDayDate today;

  /// The chosen clock time, read at [offsetMinutes]; null for `now`, for a
  /// new Meal whose time isn't chosen, and for a saved `date` Meal.
  final DateTime? chosenClock;
  final NutritionDayDate chosenDate;

  /// A new Meal on today with no chosen time: it is logged at the write.
  final bool isNow;
  final String? pendingMealType;

  /// The Meal Type the list marks: the saved one, the hand-picked one, or
  /// the proposal once the new Meal has a time.
  final String? markedType;
  final List<MealTypeRecord> mealTypes;

  /// The date fields of a clock reading, as they are: [clock] may be a UTC
  /// `DateTime` holding a clock at a frozen offset, which
  /// `NutritionDayDate.fromDateTime` would move to the device zone.
  static NutritionDayDate _dayOf(DateTime clock) {
    return NutritionDayDate(
      year: clock.year,
      month: clock.month,
      day: clock.day,
    );
  }
}

/// A full-width date or time row, at least 48 dp tall: the Dose edit
/// sheet's `_MomentField`.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.rowKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      key: rowKey,
      borderRadius: AppRadii.cardMd,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          children: [
            Icon(icon, color: colors.textSecondary),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: Text(
                label,
                style: context.textStyles.body.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: context.textStyles.body.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
