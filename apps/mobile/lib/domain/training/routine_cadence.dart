/// The authored rhythm of a Routine.
enum CadenceKind { weekly, rotating }

/// A structurally valid optional Routine rhythm.
///
/// Construction is deliberately limited to the two supported shapes: weekly
/// never carries a window, while rotating always carries a non-null window.
/// Numeric range validation remains in the shared plan validator.
final class Cadence {
  const Cadence._({required this.kind, required this.window});

  const Cadence.weekly()
      : this._(
          kind: CadenceKind.weekly,
          window: null,
        );

  const Cadence.rotating(int window)
      : this._(
          kind: CadenceKind.rotating,
          window: window,
        );

  final CadenceKind kind;
  final int? window;

  int get slotCount => switch (kind) {
        CadenceKind.weekly => 7,
        CadenceKind.rotating => window!,
      };
}

/// Whether [left] and [right] describe the same rhythm. Two null Cadences
/// are equal.
bool cadencesEqual(Cadence? left, Cadence? right) {
  return left?.kind == right?.kind && left?.window == right?.window;
}

/// The Cadence slot a Routine Entry at [position] gets by default: entries
/// fill slots 1..slotCount in order and wrap around. Null when the Routine
/// has no Cadence.
int? defaultRoutineEntrySlot(int position, Cadence? cadence) {
  if (cadence == null) {
    return null;
  }
  final slotCount = cadence.slotCount;
  if (slotCount < 1) {
    throw StateError('Cadence must have at least one slot.');
  }
  return (position % slotCount) + 1;
}

/// Keeps an authored [slot] that still fits [cadence], and otherwise falls
/// back to [defaultRoutineEntrySlot] for [position]. Null when the Routine
/// has no Cadence.
int? reconciledRoutineEntrySlot(
  int? slot, {
  required int position,
  required Cadence? cadence,
}) {
  if (cadence == null) {
    return null;
  }
  if (slot != null && slot >= 1 && slot <= cadence.slotCount) {
    return slot;
  }
  return defaultRoutineEntrySlot(position, cadence);
}
