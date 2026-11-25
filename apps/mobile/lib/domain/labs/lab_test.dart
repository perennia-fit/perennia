/// The Lab Test catalogue's types (docs/designs/lab-results.md, "The Lab Test
/// catalogue"). The entries themselves are generated into
/// `lab_test_catalogue.generated.dart` from `packages/lab-catalogue`; nothing
/// here is stored or synced, and a stored Lab Metric names its Lab Test only
/// by [LabTest.key].
library;

import 'lab_test_catalogue.generated.dart';

/// An inclusive numeric range in a Lab Test's canonical unit.
class Bounds {
  const Bounds({required this.min, required this.max});

  final num min;
  final num max;

  /// Whether [value] lies within the bounds, both ends included.
  bool contains(num value) => value >= min && value <= max;
}

/// What the ranges a Lab Test's labs print are. A `riskTarget` range (the
/// lipids) is a guideline target, not a reference interval, so no result is
/// ever positioned against it and the Lab Test has no Default Range.
enum PrintedRangeKind { reference, riskTarget }

/// The sex a Default Range applies to. `any` applies whatever the profile
/// says, including when it says nothing.
enum DefaultRangeSex { female, male, any }

/// Where a Default Range was copied from, shown beside it.
class DefaultRangeSource {
  const DefaultRangeSource({
    required this.title,
    required this.url,
    required this.version,
  });

  final String title;
  final String url;

  /// The publication year.
  final String version;
}

/// A general reference interval, shown only when a result has no Printed
/// Range. Ages are inclusive whole years and a null side is unbounded; at
/// least one of [low] and [high] is set, and both are inclusive.
class DefaultRange {
  const DefaultRange({
    required this.sex,
    this.ageMin,
    this.ageMax,
    this.low,
    this.high,
    required this.source,
  });

  final DefaultRangeSex sex;
  final int? ageMin;
  final int? ageMax;
  final num? low;
  final num? high;
  final DefaultRangeSource source;
}

/// One catalogue entry: a test a lab reports, with exactly one canonical
/// [unit] and the spellings ([unitAliases]) accepted for it. Keys, names and
/// units never change once released.
class LabTest {
  const LabTest({
    required this.key,
    required this.name,
    required this.panel,
    required this.variants,
    required this.unit,
    required this.unitAliases,
    required this.hardBounds,
    this.plausibleBounds,
    required this.printedRangeKind,
    required this.defaultRanges,
  });

  /// Stable id, lower snake case. Never renamed, reused or removed.
  final String key;

  /// Display name.
  final String name;

  /// Display grouping. Never stored on a result.
  final String panel;

  /// Other names for the Lab Test, lower case with single spaces, for search.
  final List<String> variants;

  /// The canonical unit, used as the Lab Metric's unit.
  final String unit;

  /// Other spellings of [unit]. Two spellings that differ only by whitespace
  /// are never both listed: [foldUnit] already makes them equal.
  final List<String> unitAliases;

  /// Outside is a hard reject.
  final Bounds hardBounds;

  /// Outside is a soft warning. Never shown to the user as a range.
  final Bounds? plausibleBounds;

  final PrintedRangeKind printedRangeKind;

  final List<DefaultRange> defaultRanges;
}

final RegExp _whitespace = RegExp(r'\s');

/// The one unit fold every comparison uses: remove every whitespace character
/// and keep case. So `x10^9 /L` matches `x10^9/L`, but `nmol/l` matches
/// `nmol/L` only because the catalogue lists `nmol/l` as an alias. The
/// generator (`tools/generate-lab-test-catalogue.mjs`) applies the same fold.
String foldUnit(String unit) => unit.replaceAll(_whitespace, '');

/// The canonical unit of [labTest] when [enteredUnit], after [foldUnit],
/// equals its unit or one of its aliases after the same fold; otherwise null.
String? resolveLabUnit(LabTest labTest, String enteredUnit) {
  final folded = foldUnit(enteredUnit);
  if (foldUnit(labTest.unit) == folded) return labTest.unit;
  for (final alias in labTest.unitAliases) {
    if (foldUnit(alias) == folded) return labTest.unit;
  }
  return null;
}

/// The catalogue's panels, each once, in order of their first appearance in
/// [labTestCatalogue]. Both the Lab Results screen and the Lab Test picker
/// list panels in this order; derive it nowhere else. Sits beside
/// [labTestByKey] (in the generated file) as the other catalogue lookup.
final List<String> labCataloguePanels = List<String>.unmodifiable(<String>{
  for (final labTest in labTestCatalogue) labTest.panel,
});
