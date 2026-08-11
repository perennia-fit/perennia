import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/nutrition_day_controller.dart'
    show nutritionRepositoryProvider;
import '../import/cronometer_csv_import_adapter.dart';
import '../import/lifesum_import_adapter.dart';
import '../import/myfitnesspal_csv_import_adapter.dart';
import '../import/nutrition_import.dart';
import '../import/nutrition_import_consent_repository.dart';
import '../import/yazio_import_adapter.dart';

/// The on-device file-import providers the user can choose between. Each is a
/// pure parse-and-map [NutritionImportAdapter] against the SAME landing path;
/// adding a provider here is the whole extension point (mirroring the
/// "writing an Acquisition adapter against a stable contract" extensibility of
/// INTEGRATIONS.md §14).
enum NutritionImportProvider {
  cronometer('Cronometer', 'Cronometer CSV export', '.csv'),
  myFitnessPal('MyFitnessPal', 'MyFitnessPal CSV export (premium)', '.csv'),
  yazio('Yazio', 'Yazio GDPR export', '.json'),
  lifesum('Lifesum', 'Lifesum GDPR export', '.csv / .json');

  const NutritionImportProvider(this.label, this.description, this.fileHint);

  final String label;
  final String description;
  final String fileHint;

  NutritionImportAdapter get adapter => switch (this) {
        NutritionImportProvider.cronometer =>
          const CronometerCsvImportAdapter(),
        NutritionImportProvider.myFitnessPal =>
          const MyFitnessPalCsvImportAdapter(),
        NutritionImportProvider.yazio => const YazioImportAdapter(),
        NutritionImportProvider.lifesum => const LifesumImportAdapter(),
      };
}

/// Default file picker provider. Overridden in tests and on platforms with a
/// real picker; null here so the screen surfaces a clear "no picker" path
/// rather than crashing, keeping the parse + land logic plugin-free.
final nutritionImportFilePickerProvider =
    Provider<NutritionImportFilePicker?>((ref) => null);

final nutritionImportParserProvider = Provider<NutritionImportParser>((ref) {
  return const IsolateNutritionImportParser();
});

/// Parses a selected nutrition export into the provider-neutral import batch.
/// Implementations keep parsing outside the synchronous logging/navigation path.
abstract interface class NutritionImportParser {
  Future<NutritionImportBatch> parse({
    required NutritionImportProvider provider,
    required String content,
  });
}

/// Default parser: adapters are pure CPU work, so large exports run in a short
/// lived isolate before the controller lands the result through repositories.
final class IsolateNutritionImportParser implements NutritionImportParser {
  const IsolateNutritionImportParser();

  @override
  Future<NutritionImportBatch> parse({
    required NutritionImportProvider provider,
    required String content,
  }) {
    return Isolate.run(() => provider.adapter.parse(content));
  }
}

final nutritionImportControllerProvider =
    AsyncNotifierProvider<NutritionImportController, NutritionImportUiState>(
  NutritionImportController.new,
);

/// What the import screen is doing right now.
enum NutritionImportPhase { idle, importing, done, error }

class NutritionImportUiState {
  const NutritionImportUiState({
    this.provider = NutritionImportProvider.cronometer,
    this.phase = NutritionImportPhase.idle,
    this.result,
    this.errorMessage,
  });

  final NutritionImportProvider provider;
  final NutritionImportPhase phase;
  final NutritionImportResult? result;
  final String? errorMessage;

  bool get isBusy => phase == NutritionImportPhase.importing;

  NutritionImportUiState copyWith({
    NutritionImportProvider? provider,
    NutritionImportPhase? phase,
    NutritionImportResult? result,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return NutritionImportUiState(
      provider: provider ?? this.provider,
      phase: phase ?? this.phase,
      result: clearResult ? null : result ?? this.result,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Drives the on-device nutrition file import: pick → parse (the selected
/// provider's adapter) → land (repository, consent-gated). The controller never
/// touches Drift directly — the repository is the only storage layer
/// (architecture rule) — and every adapter parse is pure, so the whole flow is
/// testable without the native picker plugin. Each provider reuses the SAME
/// landing path; only the parser differs (INTEGRATIONS.md §14).
class NutritionImportController extends AsyncNotifier<NutritionImportUiState> {
  @override
  Future<NutritionImportUiState> build() async {
    return const NutritionImportUiState();
  }

  NutritionImportProvider get _selectedProvider =>
      state.value?.provider ?? NutritionImportProvider.cronometer;

  /// Selects the provider whose export the user is about to pick. Resets any
  /// prior result/error so the status section reflects the new choice.
  void selectProvider(NutritionImportProvider provider) {
    state = AsyncData(
      NutritionImportUiState(provider: provider),
    );
  }

  /// Lands [content] (already-decoded file text) through the consent-gated edge
  /// landing path using the currently-selected provider. Exposed
  /// directly so tests and callers that already hold the file text need no
  /// picker.
  Future<NutritionImportResult?> landFileText(String content) async {
    final provider = _selectedProvider;
    final adapter = provider.adapter;
    state = AsyncData(
      NutritionImportUiState(
        provider: provider,
        phase: NutritionImportPhase.importing,
      ),
    );
    final consentRepository =
        ref.read(nutritionImportConsentRepositoryProvider);
    final parser = ref.read(nutritionImportParserProvider);
    final repository = ref.read(nutritionRepositoryProvider);
    try {
      final batch = await parser.parse(provider: provider, content: content);
      final result = await repository.importNutritionBatch(
        batch: batch,
        provider: adapter.provider,
        consentCheck: consentRepository.hasConsent,
      );
      state = AsyncData(
        NutritionImportUiState(
          provider: provider,
          phase: NutritionImportPhase.done,
          result: result,
        ),
      );
      return result;
    } on NutritionImportConsentRequiredException {
      state = AsyncData(
        NutritionImportUiState(
          provider: provider,
          phase: NutritionImportPhase.error,
          errorMessage:
              'Turn on nutrition imports to bring in a ${provider.label} file.',
        ),
      );
      return null;
    } on NutritionImportFormatException catch (error) {
      state = AsyncData(
        NutritionImportUiState(
          provider: provider,
          phase: NutritionImportPhase.error,
          errorMessage: error.message,
        ),
      );
      return null;
    }
  }

  /// Picks a file via the injected picker, then imports it with the selected
  /// provider's adapter. A no-op (returns null) if no picker is wired or the
  /// user cancelled.
  Future<NutritionImportResult?> pickAndImport() async {
    final picker = ref.read(nutritionImportFilePickerProvider);
    final provider = _selectedProvider;
    if (picker == null) {
      state = AsyncData(
        NutritionImportUiState(
          provider: provider,
          phase: NutritionImportPhase.error,
          errorMessage: 'No file picker is available on this device.',
        ),
      );
      return null;
    }
    final content = await picker.pickTextFile();
    if (content == null) {
      return null;
    }
    return landFileText(content);
  }
}
