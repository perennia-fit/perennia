import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

/// The device's [LabResultsRepository] (docs/designs/lab-results.md).
final labResultsRepositoryProvider = Provider<LabResultsRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).labResults;
});

/// The Lab Tests with at least one result, each with its latest collapsed
/// result: catalogue order, then "Other" (see
/// [LabResultsRepository.watchLabTests]).
final labTestsProvider = StreamProvider<List<LabTestSummary>>((ref) {
  return ref.watch(labResultsRepositoryProvider).watchLabTests();
});

/// The collapsed results of one Lab Test, keyed by its `labTestKey`, newest
/// first (see [LabResultsRepository.watchLabResults]).
final labResultsProvider =
    StreamProvider.family<List<LabResultRecord>, String>((ref, labTestKey) {
  return ref.watch(labResultsRepositoryProvider).watchLabResults(labTestKey);
});
