import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/open_food_facts_repository.dart';
import '../../../domain/nutrition/open_food_facts.dart';
import '../../../theme/theme.dart';
import '../../nutrition/widgets/nutrition_attribution.dart';
import 'settings_shared.dart';

const _wgerExerciseSourceUrl = 'https://github.com/wger-project/wger';
const _workoutCoolSourceUrl = 'https://github.com/Snouzy/workout-cool';
const _ccBySa4Url = 'https://creativecommons.org/licenses/by-sa/4.0/';

/// Settings → About: bundled-data attributions and license obligations
/// (CC-BY-SA, ODbL) — read-once content with a permanent, predictable home.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const exerciseCreditsKey = Key('settings.exerciseCredits');
  static const nutritionCreditsKey = Key('settings.nutritionCredits');
  static const openFoodFactsParagraphKey =
      Key('settings.nutritionCredits.openFoodFacts');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SettingsSubScreen(
      title: 'About',
      children: [
        SettingsSection(
          title: 'Exercise data',
          children: [
            _ExerciseCredits(),
          ],
        ),
        SizedBox(height: AppDimens.base),
        SettingsSection(
          title: 'Nutrition data',
          children: [
            _NutritionCredits(),
          ],
        ),
      ],
    );
  }
}

class _ExerciseCredits extends StatelessWidget {
  const _ExerciseCredits();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Exercise data credits',
      child: Padding(
        key: AboutScreen.exerciseCreditsKey,
        padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The bundled Platform Library data pack is adapted from wger English exercise fixtures and enriched by comparing Workout.cool exercise names and structured attributes. It is distributed under CC-BY-SA 4.0; no images, videos, thumbnails, generated descriptions, or UI assets are bundled.',
              style: context.textStyles.body,
            ),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: const [
                AttributionLinkButton(
                  label: 'wger source',
                  url: _wgerExerciseSourceUrl,
                ),
                AttributionLinkButton(
                  label: 'Workout.cool source',
                  url: _workoutCoolSourceUrl,
                ),
                AttributionLinkButton(
                  label: 'CC-BY-SA 4.0',
                  url: _ccBySa4Url,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NutritionCredits extends ConsumerWidget {
  const _NutritionCredits();

  /// The dataset parenthesis is left out while the header loads, and when it
  /// cannot be read.
  static String openFoodFactsParagraph(BundleHeader? header) {
    final dataset = header == null
        ? ''
        : ' (dataset version ${header.datasetVersion}, '
            '${header.productCount} products)';
    return 'Branded foods come from Open Food Facts, a database built by its '
        'contributors, made available under the Open Database License (ODbL) '
        '1.0. This app includes a list of common products from Australia, the '
        'United States, the United Kingdom, Canada and New Zealand$dataset. '
        'The list and its licence file are in the Perennia repository under '
        'apps/mobile/assets/seeds/, and the tool that builds it is '
        'apps/mobile/tool/open_food_facts_bundle/build_bundle.dart. '
        '$openFoodFactsDisclaimer Searching online sends your search text or '
        'barcode to Open Food Facts; you can turn this off under Settings > '
        'Food data.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(bundleHeaderProvider).value;
    return Semantics(
      container: true,
      label: 'Nutrition data credits',
      child: Padding(
        key: AboutScreen.nutritionCreditsKey,
        padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              openFoodFactsParagraph(header),
              key: AboutScreen.openFoodFactsParagraphKey,
              style: context.textStyles.body,
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
                AttributionLinkButton(
                  key: NutritionAttributionKeys.openFoodFactsDbclLink,
                  label: 'DbCL',
                  url: openFoodFactsDbclUrl,
                ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            Text(
              'USDA FoodData Central provides the bundled generic-food floor. Courtesy attribution: USDA FoodData Central.',
              style: context.textStyles.body,
            ),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: const [
                AttributionLinkButton(
                  key: NutritionAttributionKeys.usdaSourceLink,
                  label: 'USDA FoodData Central',
                  url: usdaFoodDataCentralUrl,
                ),
                AttributionLinkButton(
                  key: NutritionAttributionKeys.usdaCc0Link,
                  label: 'CC0',
                  url: usdaCc0Url,
                ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            Text(
              'USDA foods and the offline Open Food Facts list work with no '
              'network. Searching Open Food Facts online needs a connection, '
              'and products you open or scan stay on this device. Quick Entry '
              'stays available.',
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
