import 'package:flutter/material.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../../../theme/theme.dart';

const openFoodFactsSourceUrl = 'https://world.openfoodfacts.org/';
const openFoodFactsOdblUrl = 'https://opendatacommons.org/licenses/odbl/1-0/';
const usdaFoodDataCentralUrl = 'https://fdc.nal.usda.gov/';
const usdaCc0Url = 'https://creativecommons.org/publicdomain/zero/1.0/';

class NutritionAttributionKeys {
  NutritionAttributionKeys._();

  static const openFoodFactsNotice =
      Key('nutrition.attribution.openFoodFacts.notice');
  static const openFoodFactsSourceLink =
      Key('nutrition.attribution.openFoodFacts.source');
  static const openFoodFactsOdblLink =
      Key('nutrition.attribution.openFoodFacts.odbl');
  static const usdaSourceLink = Key('nutrition.attribution.usda.source');
  static const usdaCc0Link = Key('nutrition.attribution.usda.cc0');

  static Key foodSourceBadge(FoodSource source) {
    return Key('nutrition.foodSourceBadge.${source.name}');
  }
}

class FoodSourceBadge extends StatelessWidget {
  const FoodSourceBadge({
    super.key,
    required this.source,
    this.showLicense = false,
    this.providerLabel,
  });

  final FoodSource source;
  final bool showLicense;

  /// The **preserved provider string** for a generic [FoodSource.imported]
  /// entry, surfaced in place of the bare "Imported" label so the user can see
  /// exactly where the data came from (NUTRITION.md §9; INTEGRATIONS.md §6).
  /// Ignored for recognised sources (the enum value already names them).
  final String? providerLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final preserved = providerLabel?.trim();
    final label = source == FoodSource.imported &&
            preserved != null &&
            preserved.isNotEmpty
        ? 'Imported - $preserved'
        : _sourceLabel(source);
    final license = source == FoodSource.openFoodFacts ? 'ODbL' : null;
    final visibleLabel =
        showLicense && license != null ? '$label - $license' : label;

    return Semantics(
      label: license == null
          ? 'Food Source: $label'
          : 'Food Source: $label, attributed under $license',
      child: DecoratedBox(
        key: NutritionAttributionKeys.foodSourceBadge(source),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border.all(
            color: source == FoodSource.openFoodFacts
                ? colorScheme.primary
                : context.colors.divider,
          ),
          borderRadius: AppRadii.chipFull,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.dense,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _sourceIcon(source),
                size: 16,
                color: source == FoodSource.openFoodFacts
                    ? colorScheme.primary
                    : context.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                visibleLabel,
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OpenFoodFactsAttributionNotice extends StatelessWidget {
  const OpenFoodFactsAttributionNotice({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Open Food Facts attribution. Source: $openFoodFactsSourceUrl. ODbL: $openFoodFactsOdblUrl.',
      child: DecoratedBox(
        key: NutritionAttributionKeys.openFoodFactsNotice,
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
                compact
                    ? 'Open Food Facts branded data is live-query and cached on this device.'
                    : 'Open Food Facts branded and barcode data is provided by Open Food Facts.',
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppDimens.dense),
              Wrap(
                spacing: AppDimens.dense,
                runSpacing: AppDimens.dense,
                children: const [
                  AttributionLinkButton(
                    key: NutritionAttributionKeys.openFoodFactsSourceLink,
                    label: 'Open Food Facts source',
                    url: openFoodFactsSourceUrl,
                  ),
                  AttributionLinkButton(
                    key: NutritionAttributionKeys.openFoodFactsOdblLink,
                    label: 'ODbL',
                    url: openFoodFactsOdblUrl,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AttributionLinkButton extends StatelessWidget {
  const AttributionLinkButton({
    super.key,
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimens.touchTarget,
      child: TextButton.icon(
        onPressed: () => _showAttributionUrl(context),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: context.colors.textPrimary,
          minimumSize: const Size(0, AppDimens.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.dense),
        ),
      ),
    );
  }

  void _showAttributionUrl(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(label),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

String _sourceLabel(FoodSource source) {
  return switch (source) {
    FoodSource.usda => 'USDA',
    FoodSource.openFoodFacts => 'Open Food Facts',
    FoodSource.user => 'Your Food',
    FoodSource.cronometer => 'Cronometer',
    FoodSource.myFitnessPal => 'MyFitnessPal',
    FoodSource.yazio => 'Yazio',
    FoodSource.lifesum => 'Lifesum',
    FoodSource.imported => 'Imported',
  };
}

IconData _sourceIcon(FoodSource source) {
  return switch (source) {
    FoodSource.usda => Icons.public,
    FoodSource.openFoodFacts => Icons.qr_code_scanner,
    FoodSource.user => Icons.person_outline,
    FoodSource.cronometer => Icons.file_download_outlined,
    FoodSource.myFitnessPal => Icons.file_download_outlined,
    FoodSource.yazio => Icons.file_download_outlined,
    FoodSource.lifesum => Icons.file_download_outlined,
    FoodSource.imported => Icons.file_download_outlined,
  };
}
