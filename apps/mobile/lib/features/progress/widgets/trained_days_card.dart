import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_progress.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';

/// The period's Trained Days (D2, D8 card 2): a count over a calendar with
/// one column per week and one row per weekday. A Trained Day is a filled
/// cell and any other past date an outlined one, so fill against outline is
/// the signal and color carries no meaning here. Not interactive.
class TrainedDaysCard extends ConsumerWidget {
  const TrainedDaysCard({super.key});

  static const countKey = Key('progress.trainedDays.count');
  static const calendarKey = Key('progress.trainedDays.calendar');

  /// A cell's key names what it shows: `trained`, `untrained` (a past or
  /// current date without a Logged Workout) or `future`.
  static Key cellKey(TrainingDayDate date, String kind) =>
      Key('progress.trainedDays.$kind.${date.storageValue}');

  static const double maxCellSize = AppDimens.trainedDaysCell;
  static const double cellGap = AppDimens.trainedDaysCellGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = l10n.progressTrainedDaysTitle;
    final state = ref.watch(progressTrainedDaysProvider);
    final data = state.value;
    if (state.hasError || data == null) {
      return ProgressCard.pending(title: title, failed: state.hasError);
    }
    if (data.trainedDayCount == 0) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressTrainedDaysEmpty,
      );
    }
    return ProgressCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.progressTrainedDaysCount(data.trainedDayCount),
            key: countKey,
            style: context.textStyles.body.copyWith(
              color: context.colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppDimens.dense / 2),
          Semantics(
            key: calendarKey,
            container: true,
            label: l10n.progressTrainedDaysSemantics(
              data.trainedDayCount,
              data.range.period.weeks,
            ),
            child: ExcludeSemantics(child: _Calendar(data: data)),
          ),
        ],
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.data});

  final ProgressTrainedDays data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final caption = context.textStyles.caption.copyWith(
      color: colors.textSecondary,
    );
    final weeks = data.range.period.weeks;
    final from = data.range.from;
    final initialFormat = DateFormat('EEEEE', locale);
    final labelFormat = DateFormat('d MMM', locale);
    final initials = <String>[
      for (var row = 0; row < 7; row += 1)
        initialFormat.format(from.addDays(row).toLocalDateTime()),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        Size sizeOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: caption),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          )..layout();
          final size = painter.size;
          painter.dispose();
          return size;
        }

        final initialSizes = initials.map(sizeOf).toList();
        final textHeight = initialSizes.first.height;
        final gridLeft =
            initialSizes.map((size) => size.width).reduce(math.max) +
                AppDimens.dense / 2;
        const gap = TrainedDaysCard.cellGap;
        final cell =
            ((constraints.maxWidth - gridLeft - gap * (weeks - 1)) / weeks)
                .floorToDouble()
                .clamp(1.0, TrainedDaysCard.maxCellSize);
        final pitch = cell + gap;
        final gridHeight = pitch * 7 - gap;
        final gridTop = textHeight + gap;

        // A week label sits above the first date of every fourth week. When
        // the cells are too narrow for a label every four weeks, labels go
        // every eighth, twelfth... week instead, so they never overlap.
        final labels = <int, String>{
          for (var week = 0; week < weeks; week += 4)
            week: labelFormat.format(from.addDays(week * 7).toLocalDateTime()),
        };
        final labelWidths = <int, double>{
          for (final MapEntry(key: week, value: label) in labels.entries)
            week: sizeOf(label).width,
        };
        final widestLabel = labelWidths.values.fold<double>(0, math.max);
        var labelStep = 4;
        while (labelStep * pitch < widestLabel + AppDimens.dense / 2) {
          labelStep += 4;
        }
        // Likewise, with rows shorter than a line of text only every second
        // (third...) weekday is named.
        final initialStep = (textHeight / pitch).ceil();

        return SizedBox(
          height: gridTop + gridHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final MapEntry(key: week, value: label) in labels.entries)
                if (week % labelStep == 0 &&
                    gridLeft + week * pitch + labelWidths[week]! <=
                        constraints.maxWidth)
                  Positioned(
                    left: gridLeft + week * pitch,
                    top: 0,
                    child: Text(label, style: caption, softWrap: false),
                  ),
              for (var row = 0; row < 7; row += initialStep)
                Positioned(
                  left: 0,
                  top: gridTop +
                      (row * pitch + (cell - textHeight) / 2)
                          .clamp(0.0, math.max(0.0, gridHeight - textHeight)),
                  child: Text(initials[row], style: caption, softWrap: false),
                ),
              for (var week = 0; week < weeks; week += 1)
                for (var row = 0; row < 7; row += 1)
                  Positioned(
                    left: gridLeft + week * pitch,
                    top: gridTop + row * pitch,
                    // `data.days` holds one day per date from `from`, so
                    // the grid indexes it directly.
                    child: _cell(context, data.days[week * 7 + row], cell),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(BuildContext context, TrainingDay day, double size) {
    final colors = context.colors;
    final date = day.localDate;
    if (date.compareTo(data.range.today) > 0) {
      return SizedBox.square(
        key: TrainedDaysCard.cellKey(date, 'future'),
        dimension: size,
      );
    }
    final trained = data.isTrained(day);
    return SizedBox.square(
      key: TrainedDaysCard.cellKey(date, trained ? 'trained' : 'untrained'),
      dimension: size,
      child: DecoratedBox(
        decoration: trained
            ? BoxDecoration(
                color: colors.textPrimary.withValues(
                  alpha: AppDimens.trainedDaysFillOpacity,
                ),
              )
            : BoxDecoration(border: Border.all(color: colors.divider)),
      ),
    );
  }
}
