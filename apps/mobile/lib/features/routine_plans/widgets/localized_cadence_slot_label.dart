import '../../../domain/training/routine_cadence.dart';
import '../../../l10n/app_localizations.dart';

/// Returns the user-facing label for one 1-based Cadence slot.
///
/// Keeping this in the Routine UI boundary ensures every feature uses the
/// same weekday and rotating-position terminology.
String localizedCadenceSlotLabel(
  AppLocalizations l10n, {
  required CadenceKind kind,
  required int slot,
}) {
  if (kind == CadenceKind.rotating) {
    return l10n.routinePlansRotatingSlot(slot);
  }
  return switch (slot) {
    1 => l10n.routinePlansMonday,
    2 => l10n.routinePlansTuesday,
    3 => l10n.routinePlansWednesday,
    4 => l10n.routinePlansThursday,
    5 => l10n.routinePlansFriday,
    6 => l10n.routinePlansSaturday,
    7 => l10n.routinePlansSunday,
    _ => throw RangeError.range(slot, 1, 7, 'slot'),
  };
}
