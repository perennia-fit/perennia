import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/labs/lab_test_catalogue.generated.dart';
import 'lab_results_providers.dart';

/// One section of the Lab Results screen: a catalogue panel and its Lab Tests
/// with results, or "Other" ([panel] null) for keys this build's catalogue
/// does not know.
@immutable
class LabPanelSection {
  const LabPanelSection({required this.panel, required this.tests});

  /// The catalogue panel, or null for "Other".
  final String? panel;

  /// The Lab Tests with results, in catalogue order (for "Other", in the
  /// repository's order: stored name, then key).
  final List<LabTestSummary> tests;
}

/// The Lab Results screen's sections (docs/designs/lab-results.md,
/// "The display"): catalogue panels in order of their first appearance in
/// [labTestCatalogue], only panels with results, then one final "Other"
/// section for summaries whose `labTest` is null.
///
/// Derived on read from [labTestsProvider]; nothing here is stored.
final labResultsScreenProvider =
    Provider<AsyncValue<List<LabPanelSection>>>((ref) {
  return ref.watch(labTestsProvider).whenData(labPanelSections);
});

/// How many Lab Tests have results, for the Progress row's
/// "{N} lab tests" subtitle. Counts [LabTestSummary] entries, "Other"
/// included.
final labTestCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(labTestsProvider).whenData((tests) => tests.length);
});

/// Groups [summaries] into [LabPanelSection]s: see [labResultsScreenProvider].
List<LabPanelSection> labPanelSections(List<LabTestSummary> summaries) {
  final byPanel = <String, List<LabTestSummary>>{};
  final other = <LabTestSummary>[];
  for (final summary in summaries) {
    final labTest = summary.labTest;
    if (labTest == null) {
      other.add(summary);
    } else {
      byPanel.putIfAbsent(labTest.panel, () => <LabTestSummary>[]).add(
            summary,
          );
    }
  }
  final sections = <LabPanelSection>[
    for (final panel in _cataloguePanelOrder)
      if (byPanel[panel] case final tests?)
        LabPanelSection(
          panel: panel,
          tests: List<LabTestSummary>.unmodifiable(
            tests..sort(_byCatalogueIndex),
          ),
        ),
    if (other.isNotEmpty)
      LabPanelSection(
        panel: null,
        tests: List<LabTestSummary>.unmodifiable(other),
      ),
  ];
  return List<LabPanelSection>.unmodifiable(sections);
}

int _byCatalogueIndex(LabTestSummary a, LabTestSummary b) =>
    _catalogueIndex[a.labTestKey]!.compareTo(_catalogueIndex[b.labTestKey]!);

/// The catalogue's panels, each once, in order of first appearance.
final List<String> _cataloguePanelOrder = <String>{
  for (final labTest in labTestCatalogue) labTest.panel,
}.toList(growable: false);

final Map<String, int> _catalogueIndex = <String, int>{
  for (var index = 0; index < labTestCatalogue.length; index++)
    labTestCatalogue[index].key: index,
};
