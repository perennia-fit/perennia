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
