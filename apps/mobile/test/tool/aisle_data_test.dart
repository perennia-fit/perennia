import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/food_aisle.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

import '../../tool/open_food_facts_bundle/aisle_pipeline.dart';

/// Checks that the committed Aisle data is well formed and complete
/// (docs/designs/food-aisles.md, "What CI checks"), using only committed
/// files. Nothing here judges whether a label is right, and CI has no aisle
/// input, so input hashes are not recomputed: the builder has already refused
/// stale data, and every line is treated as current.
void main() {
  late final AisleLabels labels;
  late final AisleSecondOpinions secondOpinions;
  late final List<AisleOverrideRow> overrides;
  late final List<BundleProductLine> bundle;

  setUpAll(() {
    labels = parseAisleLabels(File(aisleLabelsPath).readAsStringSync());
    secondOpinions = parseAisleSecondOpinions(
      File(aisleSecondOpinionsPath).readAsStringSync(),
    );
    overrides = parseAisleOverrides(
      File(aisleOverridesPath).readAsStringSync(),
    );
    final text = utf8.decode(
      gzip.decode(File(openFoodFactsBundleAssetPath).readAsBytesSync()),
    );
    bundle = [
      for (final line in const LineSplitter().convert(text).skip(1))
        decodeBundleProductLine(line),
    ];
  });

  test('the three data files parse and have a header', () {
    expect(labels.header, isNotNull);
    expect(labels.byCode, isNotEmpty);
    expect(secondOpinions.header, isNotNull);
    // The overrides file may hold no rows; parsing it is the check.
    expect(overrides, isA<List<AisleOverrideRow>>());
  });

  test("both headers' questionHash is the current question's", () {
    expect(labels.header!.questionHash, aisleQuestionHash());
    expect(secondOpinions.header!.questionHash, aisleQuestionHash());
  });

  test('every bundled code has a label line', () {
    final missing = [
      for (final line in bundle)
        if (!labels.byCode.containsKey(line.product.code)) line.product.code,
    ];

    expect(missing, isEmpty);
  });

  test('every label that is not confident has a second opinion line', () {
    final missing = [
      for (final line in bundle)
        if (labels.byCode[line.product.code] case final label?
            when !isConfidentLabel(label) &&
                !secondOpinions.byCode.containsKey(line.product.code))
          line.product.code,
    ];

    expect(missing, isEmpty);
  });

  test("each bundled product's Aisle is the one the committed files resolve",
      () {
    final overrideByCode = {for (final row in overrides) row.code: row};
    final differing = <String>[];
    for (final line in bundle) {
      final code = line.product.code;
      final resolved = resolveFoodAisle(
        currentLabel: labels.byCode[code],
        currentSecondOpinion: secondOpinions.byCode[code],
        override: overrideByCode[code],
      );
      if (resolved != line.aisle) {
        differing.add('$code: bundle ${line.aisle?.name}, files '
            '${resolved?.name}');
      }
    }

    expect(differing, isEmpty);
  });

  test('every Aisle has a product, and the coverage floor is met', () {
    final counts = <FoodAisle, int>{};
    for (final line in bundle) {
      if (line.aisle case final aisle?) {
        counts[aisle] = (counts[aisle] ?? 0) + 1;
      }
    }
    final withAisle = counts.values.fold(0, (sum, count) => sum + count);

    expect(
      [
        for (final aisle in FoodAisle.values)
          if ((counts[aisle] ?? 0) == 0) aisle.name,
      ],
      isEmpty,
    );
    expect(
      withAisle / bundle.length,
      greaterThanOrEqualTo(aisleCoverageFloor),
      reason: '$withAisle of ${bundle.length} bundled products have an Aisle.',
    );
  });
}
