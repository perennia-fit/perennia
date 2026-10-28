import 'package:flutter/material.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';

/// A status as its word, with an icon that only echoes it (D6: color is
/// never the only signal). The Planned list's row labels and the
/// Consistency view's Day Status labels share this markup, so the two read
/// alike; each decides its own word and icon.
class StatusWordLabel extends StatelessWidget {
  const StatusWordLabel({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: Icon(icon, size: 18, color: iconColor)),
        const SizedBox(width: 4),
        Text(
          label,
          style: context.textStyles.label.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

/// The text label of each Day Status (D6).
String dayStatusLabel(AppLocalizations l10n, DayStatusKind status) =>
    switch (status) {
      DayStatusKind.notPlanned => l10n.dayStatusNotPlanned,
      DayStatusKind.paused => l10n.dayStatusPaused,
      DayStatusKind.offCycle => l10n.dayStatusOffCycle,
      DayStatusKind.pending => l10n.dayStatusPending,
      DayStatusKind.logged => l10n.dayStatusLogged,
      DayStatusKind.partlyLogged => l10n.dayStatusPartlyLogged,
      DayStatusKind.notLogged => l10n.dayStatusNotLogged,
    };

/// A planned amount as entered, with its unit; empty when the plan holds
/// neither.
String plannedAmountLabel(PlanAmount amount) {
  final unit = amount.unit;
  return <String>[
    if (amount.amountEntered != null) amount.amountEntered!,
    if (unit != null) doseUnitLabel(unit),
  ].join(' ');
}

/// A stored `HH:MM` local time (a planned time, or a Dose's frozen clock)
/// as a [TimeOfDay].
TimeOfDay planTimeOfDay(String localTime) {
  final minutes = planLocalTimeMinutes(localTime);
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}
