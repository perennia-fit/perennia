import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/nutrition/nutrition_import.dart';
import '../../../theme/theme.dart';
import '../controllers/nutrition_import_controller.dart';
import '../import/nutrition_import_consent_repository.dart';

/// The on-device nutrition file-import screen (NUTRITION.md §9). Edge-only: an
/// explicit consent toggle gates the importer, and nothing lands until it is on
/// (§2 placement rule). The user picks which provider's export they have
/// (Cronometer / MyFitnessPal / Yazio / Lifesum) — each is a parse-and-map
/// adapter against the same landing path. Color is never the sole signal —
/// every state pairs an icon and text — and tokens come from the theme, never
/// hardcoded.
class NutritionImportScreen extends ConsumerWidget {
  const NutritionImportScreen({super.key});

  static const consentToggleKey = Key('nutrition.import.consentToggle');
  static const importButtonKey = Key('nutrition.import.importButton');
  static const statusKey = Key('nutrition.import.status');
  static const providerChoiceKey = Key('nutrition.import.providerChoice');

  static Key providerChoiceKeyFor(NutritionImportProvider provider) {
    return Key('nutrition.import.provider.${provider.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consentAsync = ref.watch(nutritionImportConsentProvider);
    final importState = ref.watch(nutritionImportControllerProvider);
    final consented = consentAsync.value ?? false;
    final importBusy =
        importState.isLoading || (importState.value?.isBusy ?? false);
    final selectedProvider =
        importState.value?.provider ?? NutritionImportProvider.cronometer;

    return Scaffold(
      appBar: AppBar(title: const Text('Import nutrition')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import a food log',
                style: context.textStyles.h2.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppDimens.dense),
              Text(
                'Bring in an export from another app on this device. Imported '
                'entries are read-only and stay on your device unless you '
                'sync.',
                style: context.textStyles.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              _ProviderChooser(
                selected: selectedProvider,
                onChanged: importBusy
                    ? null
                    : (provider) => ref
                        .read(nutritionImportControllerProvider.notifier)
                        .selectProvider(provider),
              ),
              const SizedBox(height: AppDimens.base),
              _ConsentTile(
                consented: consented,
                onChanged: (value) {
                  ref
                      .read(nutritionImportConsentRepositoryProvider)
                      .setConsent(enabled: value);
                },
              ),
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: importButtonKey,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.save,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  minimumSize: const Size.fromHeight(AppDimens.rowHeight),
                ),
                onPressed: consented && !importBusy
                    ? () => ref
                        .read(nutritionImportControllerProvider.notifier)
                        .pickAndImport()
                    : null,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(
                  'Choose a ${selectedProvider.label} file',
                  style: context.textStyles.label.copyWith(
                    color: Theme.of(context).colorScheme.onSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.base),
              _StatusSection(state: importState),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderChooser extends StatelessWidget {
  const _ProviderChooser({required this.selected, required this.onChanged});

  final NutritionImportProvider selected;
  final ValueChanged<NutritionImportProvider>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: NutritionImportScreen.providerChoiceKey,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Which app is this from?',
              style: context.textStyles.label.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            for (final provider in NutritionImportProvider.values)
              _ProviderOption(
                provider: provider,
                selected: provider == selected,
                onTap: onChanged == null ? null : () => onChanged!(provider),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderOption extends StatelessWidget {
  const _ProviderOption({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final NutritionImportProvider provider;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The selection state is conveyed by BOTH an icon shape (filled vs outline)
    // and the "Selected" semantics + label, never color alone (DESIGN.md a11y).
    return Semantics(
      button: true,
      selected: selected,
      label: '${provider.label}. ${provider.description}',
      child: InkWell(
        key: NutritionImportScreen.providerChoiceKeyFor(provider),
        onTap: onTap,
        borderRadius: AppRadii.cardMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? context.colors.save
                      : context.colors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: AppDimens.dense),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.label,
                        style: context.textStyles.body.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      Text(
                        provider.description,
                        style: context.textStyles.caption.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({required this.consented, required this.onChanged});

  final bool consented;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allow nutrition imports',
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Runs only on this device. Required before importing.',
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            Semantics(
              label: 'Allow nutrition imports',
              child: Switch(
                key: NutritionImportScreen.consentToggleKey,
                value: consented,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.state});

  final AsyncValue<NutritionImportUiState> state;

  @override
  Widget build(BuildContext context) {
    final ui = state.value;
    if (state.isLoading || (ui?.isBusy ?? false)) {
      return _StatusBanner(
        icon: Icons.hourglass_top,
        color: context.colors.textSecondary,
        message: 'Importing…',
      );
    }
    if (ui == null) {
      return const SizedBox.shrink();
    }
    return switch (ui.phase) {
      NutritionImportPhase.idle ||
      NutritionImportPhase.importing =>
        const SizedBox.shrink(),
      NutritionImportPhase.error => _StatusBanner(
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          message: ui.errorMessage ?? 'Import failed.',
        ),
      NutritionImportPhase.done => _StatusBanner(
          icon: Icons.check_circle_outline,
          color: context.colors.save,
          message: _doneMessage(ui.result),
        ),
    };
  }

  String _doneMessage(NutritionImportResult? result) {
    if (result == null) {
      return 'Import finished.';
    }
    final landed = result.landedCount;
    final flagged = result.reviewFlagCount;
    final rejected = result.rejectedCount;
    final parts = <String>[
      'Imported $landed ${landed == 1 ? 'entry' : 'entries'}.',
      if (flagged > 0) '$flagged need review.',
      if (rejected > 0) '$rejected skipped (out of range).',
    ];
    return parts.join(' ');
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        key: NutritionImportScreen.statusKey,
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border.all(color: context.colors.divider),
          borderRadius: AppRadii.cardMd,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  message,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
