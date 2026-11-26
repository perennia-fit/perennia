import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/labs/lab_default_range.dart';
import '../../../domain/labs/lab_result.dart';
import '../../../domain/labs/lab_test.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/lab_test_detail_controller.dart';

/// One Lab Result on the Lab Test detail (docs/designs/lab-results.md,
/// "The display").
///
/// Dated from `lab.collected` only, never the stored instant: the date, and
/// the time only when the lab printed one. Then, in this order: the value as
/// entered with its unit; the Printed Range (`Target` for a `riskTarget` Lab
/// Test); the general range when a Default Range applies; the position
/// sentence; the lab's flag; Interim, Fasting and the lab's name; and the
/// archive action.
///
/// The position is words only, never colour and never "normal" or
/// "abnormal". The flag, the position and Interim carry explicit semantics
/// labels, and a Limit Result reads its comparator in words.
class LabResultRow extends StatelessWidget {
  const LabResultRow({
    super.key,
    required this.view,
    required this.onArchive,
    this.archiveButtonKey,
  });

  final LabResultView view;
  final VoidCallback onArchive;
  final Key? archiveButtonKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final styles = context.textStyles;
    final record = view.record;
    final lab = record.lab;
    final secondary = styles.body.copyWith(color: colors.textSecondary);

    final lines = <Widget>[
      Text(
        _collectedText(context, lab.collected),
        style: styles.label.copyWith(color: colors.textSecondary),
      ),
      Semantics(
        label: _valueSemantics(l10n, record.entered, record.enteredUnit),
        container: true,
        excludeSemantics: true,
        child: Text(
          labResultValueText(l10n, record.entered, record.enteredUnit),
          style: styles.numeralRow.copyWith(color: colors.textPrimary),
        ),
      ),
      if (lab.printedRange case final printed?)
        Text(
          view.kind == PrintedRangeKind.riskTarget
              ? l10n.labResultTarget(printed)
              : l10n.labResultLabRange(printed),
          style: secondary,
        ),
      if (view.defaultRange case final range?) ...[
        Text(_generalRangeText(l10n, range, view), style: secondary),
        // The source is a full paper title, often several lines long, so it
        // sits on one line of its own and is cut with an ellipsis; a screen
        // reader still reads all of it.
        Semantics(
          label: _sourceText(l10n, range),
          container: true,
          excludeSemantics: true,
          child: Text(
            _sourceText(l10n, range),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.label.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
      if (_positionText(l10n, view.position) case final position?)
        Semantics(
          label: position,
          container: true,
          excludeSemantics: true,
          child: Text(
            position,
            style: styles.body.copyWith(color: colors.textPrimary),
          ),
        ),
      if (lab.printedFlag case final flag?)
        Semantics(
          label: l10n.labResultFlag(flag),
          container: true,
          excludeSemantics: true,
          child: Text(
            l10n.labResultFlag(flag),
            style: styles.body.copyWith(color: colors.textPrimary),
          ),
        ),
      if (!lab.reportStatus.isFinal)
        Semantics(
          label: l10n.labResultInterimSemantics,
          container: true,
          excludeSemantics: true,
          child: Text(l10n.labResultInterim, style: secondary),
        ),
      if (lab.fasting == true) Text(l10n.labResultFasting, style: secondary),
      if (lab.labName case final labName?) Text(labName, style: secondary),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.base,
        AppDimens.dense,
        AppDimens.dense,
        AppDimens.dense,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < lines.length; index++) ...[
                  if (index > 0) const SizedBox(height: 4),
                  lines[index],
                ],
              ],
            ),
          ),
          IconButton(
            key: archiveButtonKey,
            tooltip: l10n.labResultArchive,
            constraints: const BoxConstraints(
              minWidth: AppDimens.touchTarget,
              minHeight: AppDimens.touchTarget,
            ),
            icon: const Icon(Icons.archive_outlined),
            onPressed: onArchive,
          ),
        ],
      ),
    );
  }
}

/// The collection date as the locale writes it, plus the time only when the
/// lab printed one. Built from `collected`'s own components (see the domain's
/// [collectedLocal]), never from the stored instant; a date-only value shows
/// no time, so its noon placeholder is never read.
String _collectedText(BuildContext context, String collected) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final parsed = collectedLocal(collected);
  final format = parsed.hasTime
      ? DateFormat.yMMMd(locale).add_jm()
      : DateFormat.yMMMd(locale);
  return format.format(parsed.dateTime);
}

/// The value as entered, comparator included (`< 1`), and the unit as entered.
String labResultValueText(AppLocalizations l10n, String entered, String unit) {
  final trimmedUnit = unit.trim();
  return trimmedUnit.isEmpty
      ? entered
      : l10n.labResultValue(entered, trimmedUnit);
}

/// The value for a screen reader: a Limit Result reads its comparator in
/// words ("less than 1 mg/L"), as a symbol is often skipped or misread.
String _valueSemantics(AppLocalizations l10n, String entered, String unit) {
  final parsed = parseEntered(entered.trim());
  final comparator = parsed?.comparator;
  if (parsed == null || comparator == null) {
    return labResultValueText(l10n, entered, unit);
  }
  return l10n
      .labResultLimitSemantics(
        _comparatorWords(l10n, comparator),
        parsed.number,
        unit.trim(),
      )
      .trim();
}

String _comparatorWords(AppLocalizations l10n, LabComparator comparator) =>
    switch (comparator) {
      LabComparator.lt => l10n.labResultComparatorLtWords,
      LabComparator.le => l10n.labResultComparatorLeWords,
      LabComparator.gt => l10n.labResultComparatorGtWords,
      LabComparator.ge => l10n.labResultComparatorGeWords,
    };

/// `General range {low}–{high} {unit}`, or the one-sided form when a side is
/// missing. The unit is the Lab Test's, which is the unit a Default Range is
/// written in. The source is a separate line ([_sourceText]).
String _generalRangeText(
  AppLocalizations l10n,
  DefaultRange range,
  LabResultView view,
) {
  final unit = view.labTest?.unit ?? view.record.enteredUnit;
  final low = range.low;
  final high = range.high;
  if (low != null && high != null) {
    return l10n.labResultGeneralRange(
      formatRangeNumber(low),
      formatRangeNumber(high),
      unit,
    );
  }
  if (high != null) {
    return l10n.labResultGeneralRangeBelow(
      formatRangeNumber(high),
      unit,
    );
  }
  return l10n.labResultGeneralRangeAbove(
    formatRangeNumber(low!),
    unit,
  );
}

/// `Source: {source title}, {year}`, the line under a general range.
String _sourceText(AppLocalizations l10n, DefaultRange range) =>
    l10n.labResultGeneralRangeSource(range.source.title, range.source.version);

/// [value] without a trailing `.0`: `45` rather than `45.0`, `3.5` as is.
String formatRangeNumber(num value) {
  if (value is int) return value.toString();
  if (value.isFinite && value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

String? _positionText(
  AppLocalizations l10n,
  ({RangePosition position, RangeSource source})? position,
) {
  if (position == null) return null;
  return switch ((position.position, position.source)) {
    (RangePosition.below, RangeSource.printed) =>
      l10n.labResultPositionBelowPrinted,
    (RangePosition.within, RangeSource.printed) =>
      l10n.labResultPositionWithinPrinted,
    (RangePosition.above, RangeSource.printed) =>
      l10n.labResultPositionAbovePrinted,
    (RangePosition.below, RangeSource.general) =>
      l10n.labResultPositionBelowGeneral,
    (RangePosition.within, RangeSource.general) =>
      l10n.labResultPositionWithinGeneral,
    (RangePosition.above, RangeSource.general) =>
      l10n.labResultPositionAboveGeneral,
    (RangePosition.unknown, _) => null,
  };
}
