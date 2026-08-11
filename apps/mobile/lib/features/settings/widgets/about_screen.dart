import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../nutrition/widgets/nutrition_attribution.dart';
import 'settings_shared.dart';

const _wgerExerciseSourceUrl = 'https://github.com/wger-project/wger';
const _workoutCoolSourceUrl = 'https://github.com/Snouzy/workout-cool';
const _ccBySa4Url = 'https://creativecommons.org/licenses/by-sa/4.0/';

/// Settings → About: bundled-data attributions and license obligations
/// (CC-BY-SA, ODbL) — read-once content with a permanent, predictable home.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const exerciseCreditsKey = Key('settings.exerciseCredits');
  static const nutritionCreditsKey = Key('settings.nutritionCredits');

  @override
  Widget build(BuildContext context) {
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

class _NutritionCredits extends StatelessWidget {
  const _NutritionCredits();

  @override
  Widget build(BuildContext context) {
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
              'Open Food Facts branded and barcode data is queried live and cached on this device. Attribution: Open Food Facts.',
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
              'USDA logging works fully offline. Open Food Facts branded/barcode lookups need network once, then use this device cache. Quick Entry stays available.',
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
