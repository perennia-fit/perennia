import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// The Open Food Facts product mapping, its bundle line format and its search
/// expression (docs/designs/open-food-facts.md, "The product mapping" and
/// "Where nutrient values are read from").
void main() {
  group('mapOpenFoodFactsProduct', () {
    test('maps a full legacy product', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'brands': 'Chobani',
        'serving_quantity': 170,
        'serving_quantity_unit': 'g',
        'product_quantity': 907,
        'product_quantity_unit': 'g',
        'unique_scans_n': 412,
        'nutriments': <String, Object?>{
          'energy-kcal_100g': 53,
          'proteins_100g': 10,
          'carbohydrates_100g': 3.6,
          'sugars_100g': 3.2,
          'fat_100g': 0,
          'saturated-fat_100g': 0,
          'monounsaturated-fat_100g': 0.1,
          'polyunsaturated-fat_100g': 0.2,
          'fiber_100g': 0.5,
          'sodium_100g': 0.036,
          'cholesterol_100g': 0.005,
          'caffeine_100g': 0,
        },
      });

      expect(product.code, '0818290014313');
      expect(product.name, 'Greek Yogurt Plain Nonfat');
      expect(product.brand, 'Chobani');
      expect(product.isLiquid, isFalse);
      expect(product.servingLabel, 'serving');
      expect(product.servingSize, 170);
      expect(product.packageSize, 907);
      expect(
        product.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1745020800000, isUtc: true),
      );
      expect(product.scans, 412);
      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.energy: '53',
        NutrientId.protein: '10',
        NutrientId.carbohydrate: '3.6',
        NutrientId.sugar: '3.2',
        NutrientId.fat: '0',
        NutrientId.saturatedFat: '0',
        NutrientId.monounsaturatedFat: '0.1',
        NutrientId.polyunsaturatedFat: '0.2',
        NutrientId.fiber: '0.5',
        NutrientId.sodium: '36',
        NutrientId.cholesterol: '5',
        NutrientId.caffeine: '0',
      });
    });

    test('maps a product with only the four core nutrients', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutriments': _coreNutriments,
      });

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.energy: '53',
        NutrientId.protein: '10',
        NutrientId.carbohydrate: '3.6',
        NutrientId.fat: '0',
      });
      expect(product.brand, isNull);
      expect(product.scans, isNull);
    });

    test('ignores energy-kcal_value without energy-kcal_100g', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{
          'energy-kcal_value': 120,
          'proteins_100g': 10,
        },
      });

      expect(product.nutrientText.containsKey(NutrientId.energy), isFalse);
      expect(product.nutrientText[NutrientId.protein], '10');
    });

    test('treats a negative value as unknown', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{'proteins_100g': -1, 'fat_100g': 2},
      });

      expect(product.nutrientText, <NutrientId, String>{NutrientId.fat: '2'});
    });

    test('converts legacy sodium, cholesterol and caffeine to milligrams', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{
          'sodium_100g': 0.5,
          'cholesterol_100g': 0.012,
          'caffeine_100g': 0.032,
        },
      });

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.sodium: '500',
        NutrientId.cholesterol: '12',
        NutrientId.caffeine: '32',
      });
    });

    test('reads the trimmed dump example from nutrition.aggregated_set', () {
      // Verbatim from the spec, "Where nutrient values are read from".
      final example = jsonDecode('''
{
  "nutrition": {
    "aggregated_set": {
      "per": "100g",
      "preparation": "as_sold",
      "nutrients": {
        "energy-kcal": { "value": 243, "unit": "kcal", "source": "packaging", "source_index": 0, "source_per": "100g" },
        "carbohydrates": { "value": 47.7, "unit": "g", "source": "packaging", "source_index": 0, "source_per": "100g" },
        "calcium": { "value": 0.038424589, "unit": "g", "source": "estimate", "modifier": "~", "source_index": 2, "source_per": "100g" }
      }
    },
    "input_sets": []
  },
  "nutriments": {}
}
''') as Map<String, Object?>;
      final product = _mapped(<String, Object?>{..._base, ...example});

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.energy: '243',
        NutrientId.carbohydrate: '47.7',
      });
    });

    test('reads an aggregated set per 100 ml', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(
          <String, Object?>{'energy-kcal': _entry(42, 'kcal')},
          per: '100ml',
        ),
      });

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.energy: '42',
      });
    });

    test('converts aggregated units into each default unit', () {
      String? read(String key, Object? value, String? unit) {
        final product = _mapped(<String, Object?>{
          ..._base,
          'nutrition': _aggregated(<String, Object?>{
            key: <String, Object?>{
              'value': value,
              if (unit != null) 'unit': unit,
              'source': 'packaging',
            },
          }),
        });
        return product.nutrientText.values.singleOrNull;
      }

      expect(read('sodium', 0.5, 'g'), '500');
      expect(read('proteins', 500, 'mg'), '0.5');
      expect(read('caffeine', 40000, 'µg'), '40');
      expect(read('caffeine', 40000, 'μg'), '40');
      expect(read('cholesterol', 20, 'mcg'), '0.02');
      expect(read('proteins', 5, ' g '), '5');
      expect(read('proteins', 5, 'G'), isNull);
      expect(read('proteins', 5, ''), isNull);
      expect(read('proteins', 5, null), isNull);
      expect(read('energy-kcal', 1000, 'kJ'), isNull);
    });

    test('parses aggregated values as nutriments values are parsed', () {
      String? read(Object? value, {bool include = true}) {
        final product = _mapped(<String, Object?>{
          ..._base,
          'nutrition': _aggregated(<String, Object?>{
            'carbohydrates': <String, Object?>{
              if (include) 'value': value,
              'unit': 'g',
              'source': 'packaging',
            },
          }),
        });
        return product.nutrientText[NutrientId.carbohydrate];
      }

      expect(read('47,7'), '47.7');
      expect(read('plenty'), isNull);
      expect(read(null, include: false), isNull);
    });

    test('treats a negative aggregated value as unknown', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'fat': _entry(-0.5, 'g'),
          'proteins': _entry(3, 'g'),
        }),
      });

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.protein: '3',
      });
    });

    test('skips estimates and keeps entries with no source', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'fiber': _entry(2.1, 'g', source: 'estimate'),
          'proteins': _entry(7.9, 'g'),
          'fat': <String, Object?>{'value': 1.8, 'unit': 'g'},
        }),
      });

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.protein: '7.9',
        NutrientId.fat: '1.8',
      });
    });

    test('checks plausibility only on the values the mapping chose', () {
      final estimatedEnergy = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'energy-kcal': _entry(950, 'kcal', source: 'estimate'),
          'proteins': _entry(3, 'g'),
        }),
      });
      expect(estimatedEnergy, isA<MappedOpenFoodFactsProduct>());
      expect(
        (estimatedEnergy as MappedOpenFoodFactsProduct)
            .nutrientText
            .containsKey(NutrientId.energy),
        isFalse,
      );

      final fatInMilligrams = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'fat': _entry(100100, 'mg'),
        }),
      });
      expect(_reason(fatInMilligrams), OpenFoodFactsExclusion.implausible);
    });

    test('reads only the aggregated set when both structures are present', () {
      final both = _mapped(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'proteins': _entry(4, 'g'),
        }),
        'nutriments': _coreNutriments,
      });
      expect(both.nutrientText, <NutrientId, String>{
        NutrientId.protein: '4',
      });

      final noCoreKeys = _mapped(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'sugars': _entry(1, 'g'),
        }),
        'nutriments': _coreNutriments,
      });
      expect(noCoreKeys.nutrientText, <NutrientId, String>{
        NutrientId.sugar: '1',
      });

      final onlyEstimates = _mapped(<String, Object?>{
        ..._base,
        'nutrition': _aggregated(<String, Object?>{
          'proteins': _entry(4, 'g', source: 'estimate'),
          'fat': _entry(2, 'g', source: 'estimate'),
        }),
        'nutriments': _coreNutriments,
      });
      expect(onlyEstimates.nutrientText, isEmpty);
    });

    test('reads nutriments when the aggregated set does not qualify', () {
      for (final nutrition in <Map<String, Object?>>[
        _aggregated(
          <String, Object?>{'proteins': _entry(4, 'g')},
          preparation: 'prepared',
        ),
        _aggregated(
          <String, Object?>{'proteins': _entry(4, 'g')},
          per: 'serving',
        ),
      ]) {
        final product = _mapped(<String, Object?>{
          ..._base,
          'nutrition': nutrition,
          'nutriments': _coreNutriments,
        });
        expect(product.nutrientText[NutrientId.protein], '10');
      }
    });

    test('reads nutriments when there is no nutrition', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutriments': _coreNutriments,
      });

      expect(product.nutrientText[NutrientId.energy], '53');
    });

    test('uses product_name_en when product_name is absent', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'product_name': '  ',
        'product_name_en': 'Rolled Oats',
      });

      expect(product.name, 'Rolled Oats');
    });

    test('excludes a product with no name', () {
      final result = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'product_name': null,
      });

      expect(_reason(result), OpenFoodFactsExclusion.missingName);
    });

    test('excludes a product with no change date', () {
      final result = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'last_modified_t': null,
      });

      expect(_reason(result), OpenFoodFactsExclusion.missingChangeDate);
    });

    test('excludes implausible energy and fat per 100 g', () {
      final energy = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{'energy-kcal_100g': 901},
      });
      final fat = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{'fat_100g': 100.1},
      });
      final atLimit = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{
          'energy-kcal_100g': 900,
          'fat_100g': 100,
        },
      });

      expect(_reason(energy), OpenFoodFactsExclusion.implausible);
      expect(_reason(fat), OpenFoodFactsExclusion.implausible);
      expect(atLimit, isA<MappedOpenFoodFactsProduct>());
    });

    test('takes the first of several brands', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'brands': ' Sanitarium , Weet-Bix,Kellogg',
      });

      expect(product.brand, 'Sanitarium');
    });

    test('parses serving and package from numbers or from text', () {
      final numbers = _mapped(<String, Object?>{
        ..._base,
        'serving_quantity': '30',
        'serving_quantity_unit': 'g',
        'product_quantity': 1.2,
        'product_quantity_unit': 'kg',
      });
      expect(numbers.servingSize, 30);
      expect(numbers.packageSize, 1200);

      final text = _mapped(<String, Object?>{
        ..._base,
        'serving_size': '33 g',
        'quantity': '500g',
      });
      expect(text.servingLabel, 'serving');
      expect(text.servingSize, 33);
      expect(text.packageSize, 500);
    });

    test('marks a product in millilitres as liquid', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'serving_quantity': 250,
        'serving_quantity_unit': 'ml',
        'quantity': '1 l',
      });

      expect(product.isLiquid, isTrue);
      expect(product.servingSize, 250);
      expect(product.packageSize, 1000);
    });

    test('removes trailing zeros from nutrient text', () {
      final product = _mapped(<String, Object?>{
        ..._base,
        'nutriments': <String, Object?>{
          'proteins_100g': 10.50,
          'fat_100g': 3.0,
          'sugars_100g': 0.1234567,
        },
      });

      expect(product.nutrientText, <NutrientId, String>{
        NutrientId.protein: '10.5',
        NutrientId.fat: '3',
        NutrientId.sugar: '0.123457',
      });
    });

    test('uses fallbackCode when code is absent', () {
      final product = _mapped(
        <String, Object?>{..._base, 'code': null},
        fallbackCode: '9300633603427',
      );
      final missing = mapOpenFoodFactsProduct(<String, Object?>{
        ..._base,
        'code': null,
      });

      expect(product.code, '9300633603427');
      expect(_reason(missing), OpenFoodFactsExclusion.missingCode);
    });
  });

  group('openFoodFactsNutrientStructure', () {
    test('returns nutrition only when every condition holds', () {
      OpenFoodFactsNutrientStructure structure(Object? nutrition) =>
          openFoodFactsNutrientStructure(<String, Object?>{
            'nutrition': nutrition,
          });

      expect(
        structure(_aggregated(const <String, Object?>{})),
        OpenFoodFactsNutrientStructure.nutrition,
      );
      expect(
        structure(_aggregated(const <String, Object?>{}, per: '100ml')),
        OpenFoodFactsNutrientStructure.nutrition,
      );
      expect(structure('nutrition'), OpenFoodFactsNutrientStructure.nutriments);
      expect(
        structure(<String, Object?>{'input_sets': <Object?>[]}),
        OpenFoodFactsNutrientStructure.nutriments,
      );
      expect(
        structure(_aggregated(const <String, Object?>{}, per: 'serving')),
        OpenFoodFactsNutrientStructure.nutriments,
      );
      expect(
        structure(_aggregated(const <String, Object?>{}, per: 100)),
        OpenFoodFactsNutrientStructure.nutriments,
      );
      expect(
        structure(
          _aggregated(const <String, Object?>{}, preparation: 'prepared'),
        ),
        OpenFoodFactsNutrientStructure.nutriments,
      );
      expect(
        openFoodFactsNutrientStructure(const <String, Object?>{}),
        OpenFoodFactsNutrientStructure.nutriments,
      );
    });
  });

  group('bundle product line', () {
    final product = MappedOpenFoodFactsProduct(
      code: '0818290014313',
      name: 'Greek Yogurt Plain Nonfat',
      brand: 'Chobani',
      isLiquid: false,
      servingLabel: 'serving',
      servingSize: 170,
      packageSize: 907.18474,
      nutrientText: const <NutrientId, String>{
        NutrientId.fat: '0',
        NutrientId.energy: '53',
        NutrientId.saturatedFat: '0',
      },
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        1745020800000,
        isUtc: true,
      ),
      scans: 412,
    );

    test('writes every key in order, with no extra whitespace', () {
      expect(
        encodeBundleProductLine(product),
        '{"code":"0818290014313","name":"Greek Yogurt Plain Nonfat",'
        '"brand":"Chobani","isLiquid":false,"servingLabel":"serving",'
        '"servingSize":170,"packageSize":907.18474,'
        '"nutrients":{"energy":"53","fat":"0","saturated_fat":"0"},'
        '"modifiedAt":1745020800,"scans":412}',
      );
    });

    test('writes unknown optional fields as null', () {
      final line = encodeBundleProductLine(
        MappedOpenFoodFactsProduct(
          code: '12345678',
          name: 'Water',
          brand: null,
          isLiquid: true,
          servingLabel: null,
          servingSize: null,
          packageSize: null,
          nutrientText: const <NutrientId, String>{},
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          scans: 1,
        ),
      );

      expect(
        line,
        '{"code":"12345678","name":"Water","brand":null,"isLiquid":true,'
        '"servingLabel":null,"servingSize":null,"packageSize":null,'
        '"nutrients":{},"modifiedAt":0,"scans":1}',
      );
    });

    test('decodes what it encodes', () {
      final line = encodeBundleProductLine(product);

      // The exact line in the test above pins every field, so an identical
      // re-encoding means every field survived the decode.
      expect(encodeBundleProductLine(decodeBundleProductLine(line)), line);
    });

    test('round-trips the header', () {
      const header = BundleHeader(
        format: bundleFormat,
        formatVersion: bundleFormatVersion,
        datasetVersion: '2026-10-26',
        contentHash: 'abc',
        sourceName: 'Open Food Facts',
        sourceUrl: 'https://world.openfoodfacts.org/',
        licenseName: 'Open Database License (ODbL) 1.0',
        licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
        contentsLicenseUrl: 'https://opendatacommons.org/licenses/dbcl/1-0/',
        attributionText: 'Contains information from Open Food Facts.',
        countries: <String>['au', 'us'],
        perCountryLimit: 10000,
        productCount: 2,
      );

      expect(
        BundleHeader.fromJsonLine(header.toJsonLine()).toJsonLine(),
        header.toJsonLine(),
      );
    });
  });

  group('buildFoodSearchMatch', () {
    test('lower-cases and quotes each part as a prefix term', () {
      expect(buildFoodSearchMatch('Chobani GR'), '"chobani"* "gr"*');
    });

    test('splits on punctuation', () {
      expect(
        buildFoodSearchMatch("Ben & Jerry's: cookie-dough"),
        '"ben"* "jerry"* "s"* "cookie"* "dough"*',
      );
    });

    test('keeps letters and digits from any script', () {
      expect(buildFoodSearchMatch('Crème 2%'), '"crème"* "2"*');
    });

    test('keeps the first 8 parts', () {
      expect(
        buildFoodSearchMatch('a b c d e f g h i j'),
        '"a"* "b"* "c"* "d"* "e"* "f"* "g"* "h"*',
      );
    });

    test('searches typed FTS5 operators as text', () {
      expect(
        buildFoodSearchMatch('milk AND NEAR oat* name:x'),
        '"milk"* "and"* "near"* "oat"* "name"* "x"*',
      );
    });

    test('returns null for an empty or punctuation-only query', () {
      expect(buildFoodSearchMatch(''), isNull);
      expect(buildFoodSearchMatch('  '), isNull);
      expect(buildFoodSearchMatch('*:-"'), isNull);
    });
  });

  group('nutrient text and vectors', () {
    test('nutrientTextFromVector inverts nutrientVectorFromText', () {
      const text = <NutrientId, String>{
        NutrientId.energy: '53',
        NutrientId.protein: '10.5',
        NutrientId.sodium: '36',
      };
      final vector = nutrientVectorFromText(text);

      expect(vector[NutrientId.protein].value, 10.5);
      expect(vector[NutrientId.protein].entered, '10.5');
      expect(vector[NutrientId.fat].status, NutrientValueStatus.unknown);
      expect(nutrientTextFromVector(vector), text);
    });

    test('toPlatformFoodRecord carries the Open Food Facts fields', () {
      final record = toPlatformFoodRecord(
        _mapped(<String, Object?>{
          ..._base,
          'brands': 'Chobani',
          'unique_scans_n': 7,
          'nutriments': _coreNutriments,
        }),
      );

      expect(record.id, '0818290014313');
      expect(record.foodSource, FoodSource.openFoodFacts);
      expect(record.brand, 'Chobani');
      expect(record.scans, 7);
      expect(
        record.sourceModifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1745020800000, isUtc: true),
      );
      expect(record.nutrientsPer100[NutrientId.energy].entered, '53');
    });
  });

  group('barcodeCandidates', () {
    test('adds a leading zero to a 12-digit code', () {
      expect(
        barcodeCandidates('818290014313'),
        <String>['818290014313', '0818290014313'],
      );
    });
  });

  test('openFoodFactsProductUrl links the product page', () {
    expect(
      openFoodFactsProductUrl('0818290014313'),
      'https://world.openfoodfacts.org/product/0818290014313',
    );
  });
}

const _base = <String, Object?>{
  'code': '0818290014313',
  'product_name': 'Greek Yogurt Plain Nonfat',
  'last_modified_t': 1745020800,
};

const _coreNutriments = <String, Object?>{
  'energy-kcal_100g': 53,
  'proteins_100g': 10,
  'carbohydrates_100g': 3.6,
  'fat_100g': 0,
};

Map<String, Object?> _aggregated(
  Map<String, Object?> nutrients, {
  Object? per = '100g',
  String preparation = 'as_sold',
}) {
  return <String, Object?>{
    'aggregated_set': <String, Object?>{
      'per': per,
      'preparation': preparation,
      'nutrients': nutrients,
    },
  };
}

Map<String, Object?> _entry(
  num value,
  String unit, {
  String source = 'packaging',
}) {
  return <String, Object?>{'value': value, 'unit': unit, 'source': source};
}

MappedOpenFoodFactsProduct _mapped(
  Map<String, Object?> product, {
  String? fallbackCode,
}) {
  final result = mapOpenFoodFactsProduct(product, fallbackCode: fallbackCode);
  if (result is! MappedOpenFoodFactsProduct) {
    fail('Expected a mapped product, got ${_reason(result)}.');
  }
  return result;
}

OpenFoodFactsExclusion? _reason(OpenFoodFactsMappingResult result) {
  return switch (result) {
    ExcludedOpenFoodFactsProduct(:final reason) => reason,
    MappedOpenFoodFactsProduct() => null,
  };
}
