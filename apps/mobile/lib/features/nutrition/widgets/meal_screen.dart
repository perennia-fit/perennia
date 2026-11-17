/// The Meal screen (docs/designs/meal-logging.md §6): one full-screen route
/// to log a Meal, or fix a saved one.
///
/// Widgets -> [MealScreenController] -> `NutritionRepository`. The screen
/// holds no Meal data of its own: before the first write it shows the
/// controller's pending Meal, after it the saved Meal's stream. Every action
/// is one controller call, so one repository write and one Batch.
///
/// | State | Header |
/// |---|---|
/// | New, today | `now · <proposed type>`, or `<time> · <type>` once chosen |
/// | New, past day | `Choose time`; the time sheet opens on entry |
/// | Saved, with entries | `<time> · <type>` |
/// | Saved, no entries | `<time> · <type> · add foods` |
///
/// A saved `date` Meal shows `time not recorded` in place of `<time>`.
///
/// Logging shows nutrition only: nothing here reads Dose, Protocols or
/// Workout data (§6, Privacy).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../activity/undo_conflict_message.dart';
import '../controllers/meal_screen_controller.dart';
import '../controllers/nutrition_day_controller.dart' show mealTypeListProvider;
import '../repositories/add_food_repository.dart' show FoodPickerItem;
import 'add_food_picker.dart';
import 'log_portion_screen.dart';
import 'meal_time_sheet.dart';
import 'portion_text.dart';

/// A saved Meal's time as its header and card show it: [MealRecord.clock]
/// (its time at its frozen offset) at the device's 12- or 24-hour
/// preference, or `time not recorded` for a `date` Meal, which has no clock
/// time. Never `startedAt.toLocal()`: a Meal is read where it was eaten.
String mealTimeText(BuildContext context, MealRecord meal) {
  if (meal.timePrecision == MealTimePrecision.date) {
    return context.l10n.mealTimeNotRecorded;
  }
  return formatMealClock(context, meal.clock);
}

/// A saved Meal's label in two parts, shared by the Meal screen's header
/// and the Nutrition Day's Meal card (§6): [mealTimeText], and the Meal
/// Type, followed by `add foods` while the Meal has no Food Entries. Each
/// caller joins them into `<time> · <type>[ · add foods]` and its own
/// semantic label.
({String time, String typeAndHint}) mealLabelParts(
  BuildContext context,
  NutritionDayMealRecord meal,
) {
  final l10n = context.l10n;
  final type = meal.meal.mealType;
  return (
    time: mealTimeText(context, meal.meal),
    typeAndHint: meal.entries.isEmpty
        ? l10n.mealHeaderLabel(type, l10n.mealHeaderAddFoods)
        : type,
  );
}

/// The Meal screen; see the library comment.
class MealScreen extends ConsumerStatefulWidget {
  /// A Meal not written yet, logged on [day].
  const MealScreen.newMeal({super.key, required NutritionDayDate this.day})
      : mealId = null;

  /// The saved Meal [mealId], from its card or the recent-Meal shortcut.
  const MealScreen.existing({super.key, required String this.mealId})
      : day = null;

  final NutritionDayDate? day;
  final String? mealId;

  static const headerKey = Key('nutrition.meal.header');
  static const addFoodsLaterKey = Key('nutrition.meal.addFoodsLater');
  static const yourMealsSectionKey = Key('nutrition.meal.yourMeals');
  static const recentShortcutKey = Key('nutrition.meal.recentShortcut');
  static const overflowMenuKey = Key('nutrition.meal.overflow');
  static const deleteMealKey = Key('nutrition.meal.delete');

  /// A Your meals row, by the Meal it copies.
  static Key yourMealRowKey(String lastMealId) {
    return Key('nutrition.meal.yourMeal-$lastMealId');
  }

  static Key entryRowKey(String foodEntryId) {
    return Key('nutrition.meal.entry-$foodEntryId');
  }

  static Key removeEntryKey(String foodEntryId) {
    return Key('nutrition.meal.removeEntry-$foodEntryId');
  }

  @override
  ConsumerState<MealScreen> createState() => _MealScreenState();
}

class _MealScreenState extends ConsumerState<MealScreen> {
  /// A date picked in the time sheet without a time (see
  /// [showMealTimeSheet]); kept here so it survives the sheet closing.
  final _pendingDate = ValueNotifier<NutritionDayDate?>(null);

  /// The Undo bar this screen shows, while it shows. It goes when the screen
  /// closes, so its Undo never outlives the controller it calls.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoBar;

  /// Whether [_close] ran: Delete meal and the archived Meal it then sees
  /// both close the screen, and only one may pop.
  bool _closed = false;

  late final MealScreenArgs _args = switch (widget.mealId) {
    final mealId? => MealScreenArgs.existing(mealId),
    null => MealScreenArgs.newMeal(widget.day!, instance: Object()),
  };

  MealScreenController get _notifier =>
      ref.read(mealScreenControllerProvider(_args).notifier);

  @override
  void initState() {
    super.initState();
    if (_args.isNewMeal) {
      // A new Meal on another day has no time yet: the time sheet opens by
      // itself (CUJ 5).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (!ref.read(mealScreenControllerProvider(_args)).timeChosen) {
          unawaited(_openTimeSheet());
        }
      });
    }
  }

  @override
  void dispose() {
    _pendingDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(mealScreenControllerProvider(_args));
    final mealTypes = activeMealTypes(
      ref.watch(mealTypeListProvider).value ?? const <MealTypeRecord>[],
    );
    final NutritionDayMealRecord? saved = switch (state.savedMealId) {
      final savedMealId? => ref.watch(savedMealProvider(savedMealId)).value,
      null => null,
    };
    final entries = saved?.entries ?? const <FoodEntryRecord>[];
    final header = _header(context, state, saved, mealTypes);
    final showYourMeals = !state.isSaved || (saved != null && entries.isEmpty);
    final history = showYourMeals
        ? ref.watch(mealHistoryProvider).value ?? const <MealHistoryRecord>[]
        : const <MealHistoryRecord>[];
    final shortcut = !state.isSaved && _notifier.isToday
        ? ref.watch(recentMealShortcutProvider(_args)).value
        : null;
    final canWrite = state.canPick && !state.writing;

    return _ClosesWhenArchived(
      args: _args,
      onArchived: _close,
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            _undoBar?.close();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.mealScreenTitle),
            actions: [
              if (saved != null)
                PopupMenuButton<_MealMenuAction>(
                  key: MealScreen.overflowMenuKey,
                  onSelected: (action) {
                    switch (action) {
                      case _MealMenuAction.delete:
                        unawaited(_deleteMeal());
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<_MealMenuAction>(
                      key: MealScreen.deleteMealKey,
                      value: _MealMenuAction.delete,
                      child: Text(l10n.mealDelete),
                    ),
                  ],
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimens.base,
                        AppDimens.dense,
                        AppDimens.base,
                        0,
                      ),
                      child: _HeaderButton(
                        text: header?.text,
                        semanticsLabel: header?.semanticsLabel,
                        onPressed: header == null ? null : _openTimeSheet,
                      ),
                    ),
                  ),
                  if (shortcut != null)
                    SliverToBoxAdapter(
                      child: _RecentShortcut(
                        label: l10n.mealAddToRecent(
                          mealTimeText(context, shortcut.meal),
                          shortcut.meal.mealType,
                        ),
                        onTap: state.writing
                            ? null
                            : () => _openSavedMeal(shortcut.meal.id),
                      ),
                    ),
                  if (showYourMeals && history.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeading(
                        key: MealScreen.yourMealsSectionKey,
                        text: l10n.mealYourMeals,
                      ),
                    ),
                    SliverList.list(
                      children: [
                        for (final record in history)
                          _YourMealRow(
                            key: MealScreen.yourMealRowKey(record.lastMealId),
                            record: record,
                            onTap: canWrite
                                ? () => unawaited(_logAgain(record))
                                : null,
                          ),
                      ],
                    ),
                  ],
                  if (entries.isNotEmpty)
                    SliverList.list(
                      children: [
                        for (final entry in entries)
                          _EntryRow(
                            key: MealScreen.entryRowKey(entry.id),
                            entry: entry,
                            onEdit: LogPortionScreen.canEditEntry(entry) &&
                                    !state.writing
                                ? () => unawaited(
                                      _editPortion(entry, header?.text),
                                    )
                                : null,
                            onRemove: state.writing
                                ? null
                                : () => unawaited(_removeEntry(entry)),
                          ),
                      ],
                    ),
                  SliverFillRemaining(
                    hasScrollBody: true,
                    // The picker's results area is an Expanded, so it gets the
                    // viewport's height even while the rows above push it
                    // partly out of view; the outer scroll brings it up.
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: constraints.maxHeight,
                      maxHeight: constraints.maxHeight,
                      child: _Disabled(
                        disabled: !state.canPick,
                        child: AddFoodPicker(
                          onFoodSelected: (food) {
                            unawaited(_logFood(food, header?.text));
                          },
                          onQuickEntry: (draft) {
                            return _guard(() => _notifier.logQuickEntry(draft))
                                .then((_) {});
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          bottomNavigationBar: state.isSaved
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: FilledButton(
                      key: MealScreen.addFoodsLaterKey,
                      style: FilledButton.styleFrom(
                        minimumSize:
                            const Size.fromHeight(AppDimens.touchTarget),
                      ),
                      onPressed:
                          canWrite ? () => unawaited(_addFoodsLater()) : null,
                      child: Text(
                        l10n.mealAddFoodsLater,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// The header's text and its semantic label, or null while a saved Meal
  /// loads.
  ({String text, String semanticsLabel})? _header(
    BuildContext context,
    MealScreenState state,
    NutritionDayMealRecord? saved,
    List<MealTypeRecord> mealTypes,
  ) {
    final l10n = context.l10n;
    if (state.isSaved) {
      if (saved == null) {
        return null;
      }
      final (:time, :typeAndHint) = mealLabelParts(context, saved);
      return (
        text: l10n.mealHeaderLabel(time, typeAndHint),
        semanticsLabel: l10n.mealHeaderSemantics(time, typeAndHint),
      );
    }
    if (!state.timeChosen) {
      final chooseTime = l10n.mealHeaderChooseTime;
      return (text: chooseTime, semanticsLabel: chooseTime);
    }
    final pendingStart = state.pendingStart;
    final time = pendingStart == null
        ? l10n.mealHeaderNow
        : formatMealClock(context, pendingStart);
    final type = state.pendingMealType ?? _notifier.proposedMealType(mealTypes);
    return (
      text: l10n.mealHeaderLabel(time, type),
      semanticsLabel: l10n.mealHeaderSemantics(time, type),
    );
  }

  Future<void> _openTimeSheet() {
    return showMealTimeSheet(
      context,
      args: _args,
      pendingDate: _pendingDate,
    );
  }

  /// The recent-Meal shortcut: this screen becomes that Meal's screen.
  void _openSavedMeal(String mealId) {
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MealScreen.existing(mealId: mealId),
        ),
      ),
    );
  }

  Future<void> _logAgain(MealHistoryRecord record) async {
    final result = await _guard(() => _notifier.logAgain(record));
    if (result != null && mounted) {
      _showUndoBar(
        context.l10n.mealLogged,
        result.batchId,
        announce: true,
      );
    }
  }

  Future<void> _addFoodsLater() async {
    await _guard(() => _notifier.addFoodsLater());
  }

  /// Opens Log Portion for [food]. Its Save writes into this screen's Meal
  /// target, creating the Meal on the first pick (CUJ 2).
  Future<void> _logFood(FoodPickerItem food, String? contextLabel) async {
    final state = ref.read(mealScreenControllerProvider(_args));
    if (!state.canPick) {
      return;
    }
    final notifier = _notifier;
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => _ClosesWhenArchived(
          args: _args,
          onArchived: _close,
          child: Scaffold(
            appBar: AppBar(),
            body: LogPortionScreen(
              target: state.target,
              food: food,
              contextLabel: contextLabel,
              onSave: notifier.logFoodSnapshot,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeEntry(FoodEntryRecord entry) async {
    final batchId = await _guard(() => _notifier.removeEntry(entry.id));
    if (batchId != null && mounted) {
      _showUndoBar(context.l10n.mealFoodRemoved, batchId);
    }
  }

  /// Opens Log Portion prefilled with [entry]'s Portion; its Save is one
  /// `updateFoodEntryPortion`.
  Future<void> _editPortion(FoodEntryRecord entry, String? contextLabel) async {
    final notifier = _notifier;
    LogFoodEntryResult? updated;
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => _ClosesWhenArchived(
          args: _args,
          onArchived: _close,
          child: Scaffold(
            appBar: AppBar(),
            body: LogPortionScreen.editEntry(
              entry: entry,
              contextLabel: contextLabel,
              onUpdatePortion: (portion) async {
                final result = await notifier.updatePortion(entry.id, portion);
                updated = result ?? updated;
                return result;
              },
            ),
          ),
        ),
      ),
    );
    final result = updated;
    if (result != null && mounted) {
      _showUndoBar(context.l10n.mealPortionUpdated, result.batchId);
    }
  }

  /// Delete meal: confirm, archive the Meal and its Food Entries in one
  /// Batch, then close.
  Future<void> _deleteMeal() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.mealDeleteConfirmTitle),
          content: Text(l10n.mealDeleteConfirmBody),
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
              child: Text(l10n.mealDeleteConfirmAction),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final batchId = await _guard(() => _notifier.deleteMeal());
    if (batchId != null) {
      _close();
    }
  }

  /// Closes this screen and whatever is above it (Log Portion, the time
  /// sheet), once.
  void _close() {
    if (_closed || !mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null) {
      return;
    }
    _closed = true;
    Navigator.of(context)
      ..popUntil((candidate) => candidate == route)
      ..pop();
  }

  /// The Undo bar's action. A refused undo shows the shared undo-conflict
  /// message (§7).
  Future<void> _undo(String batchId) async {
    if (!mounted) {
      return;
    }
    final l10n = context.l10n;
    final result = await _notifier.undo(batchId);
    if (result == null || !result.hasConflicts || !mounted) {
      return;
    }
    _showMessage(undoConflictMessage(l10n, result));
  }

  /// Shows [message] with Undo for [batchId] for 4 s. `persist: false` keeps
  /// that duration: a SnackBar with an action otherwise stays until it is
  /// dismissed. Android reads it out as a live region; on iOS, [announce]
  /// also sends it as an announcement.
  void _showUndoBar(String message, String batchId, {bool announce = false}) {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    final bar = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        persist: false,
        action: SnackBarAction(
          label: l10n.mealUndo,
          onPressed: () => unawaited(_undo(batchId)),
        ),
      ),
    );
    _undoBar = bar;
    unawaited(
      bar.closed.then((_) {
        if (identical(_undoBar, bar)) {
          _undoBar = null;
        }
      }),
    );
    if (announce && defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        ),
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs one write and shows a nutrient hard reject the way Log Portion
  /// does; the write then changed nothing.
  Future<T?> _guard<T>(Future<T?> Function() write) async {
    try {
      return await write();
    } on NutrientValidationException catch (error) {
      if (mounted) {
        _showMessage(
          error.errors.isEmpty ? error.message : error.errors.first.message,
        );
      }
      return null;
    }
  }
}

enum _MealMenuAction { delete }

/// The header: one full-width button, at least 48 dp, that opens the time
/// sheet. Its semantic label reads the time, the type and that both can be
/// changed.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.text,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final String? text;
  final String? semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextButton(
      key: MealScreen.headerKey,
      style: TextButton.styleFrom(
        foregroundColor: colors.textPrimary,
        minimumSize: const Size.fromHeight(AppDimens.touchTarget),
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.dense,
          vertical: AppDimens.dense,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text ?? '',
              semanticsLabel: semanticsLabel,
              style: context.textStyles.h2.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppDimens.dense),
          Icon(Icons.schedule, color: colors.textSecondary),
        ],
      ),
    );
  }
}

class _RecentShortcut extends StatelessWidget {
  const _RecentShortcut({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      key: MealScreen.recentShortcutKey,
      minTileHeight: AppDimens.touchTarget,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
      leading: Icon(Icons.add_circle_outline, color: colors.textPrimary),
      title: Text(
        label,
        style: context.textStyles.body.copyWith(color: colors.textPrimary),
      ),
      onTap: onTap,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.base,
        AppDimens.base,
        AppDimens.base,
        AppDimens.dense / 2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: context.textStyles.label.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A Your meals row: the Meal's Food names.
class _YourMealRow extends StatelessWidget {
  const _YourMealRow({super.key, required this.record, required this.onTap});

  final MealHistoryRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      minTileHeight: AppDimens.touchTarget,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
      enabled: onTap != null,
      textColor: colors.textPrimary,
      title: Text(record.foods.map((food) => food.name).join(', ')),
      onTap: onTap,
    );
  }
}

/// One Food Entry of the saved Meal: its name and amount, a tap to edit the
/// Portion where it has one, and a 48 dp remove button.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onRemove,
  });

  final FoodEntryRecord entry;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyles = context.textStyles;
    final detail = _detail(entry);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.dense),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: AppRadii.cardMd,
              onTap: onEdit,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppDimens.touchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.dense,
                    vertical: AppDimens.dense / 2,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: textStyles.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: textStyles.label.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: MealScreen.removeEntryKey(entry.id),
            tooltip: context.l10n.mealRemoveEntry(entry.name),
            constraints: const BoxConstraints(
              minWidth: AppDimens.touchTarget,
              minHeight: AppDimens.touchTarget,
            ),
            color: colors.textSecondary,
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }

  /// The Portion as entered, then the energy, where each is known.
  static String _detail(FoodEntryRecord entry) {
    final parts = <String>[];
    if (entry.portion case final portion?) {
      parts.add(formatPortionAmount(portion));
    }
    final NutrientAmount energy;
    try {
      energy = entry.resolvedNutrients[NutrientId.energy];
    } on StateError {
      return parts.join(' · ');
    }
    if (energy.value case final value? when energy.isComplete) {
      parts.add(
        '${formatNutritionNumber(value)} '
        '${nutrientUnitLabel(energy.unit)}',
      );
    }
    return parts.join(' · ');
  }
}

/// Calls [onArchived] once the Meal the screen shows is archived elsewhere (a
/// sync pull, an agent): there is nothing left to show or write into. While
/// the screen's own write is in flight it isn't decided yet: undoing the first
/// Batch archives the Meal and then gives the screen a new one.
///
/// Log Portion's route needs one too: Riverpod pauses a consumer that isn't
/// visible, so the Meal screen under it sees nothing until it shows again.
class _ClosesWhenArchived extends ConsumerWidget {
  const _ClosesWhenArchived({
    required this.args,
    required this.onArchived,
    required this.child,
  });

  final MealScreenArgs args;
  final VoidCallback onArchived;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mealScreenControllerProvider(args));
    if (state.savedMealId case final savedMealId?) {
      final meal = ref.watch(savedMealProvider(savedMealId));
      if (meal.hasValue && meal.value == null && !state.writing) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onArchived());
      }
    }
    return child;
  }
}

/// The embedded picker while picking can't write yet (a new Meal on another
/// day with no time, CUJ 5): taps and screen-reader actions are blocked, and
/// it is shown at Material's disabled-content opacity.
class _Disabled extends StatelessWidget {
  const _Disabled({required this.disabled, required this.child});

  /// Material's opacity for disabled content.
  static const double _disabledOpacity = 0.38;

  final bool disabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? _disabledOpacity : 1,
        child: child,
      ),
    );
  }
}
