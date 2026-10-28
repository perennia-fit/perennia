import 'dart:convert';
import 'dart:math' as math;

import 'nutrition.dart';

/// The one Open Food Facts product mapping. The app's live path and the bundle
/// builder (`tool/open_food_facts_bundle/build_bundle.dart`) both use it, so a
/// bundled product and the same product fetched live produce the same record.
/// Pure: imports only `dart:` libraries and other domain files, so the builder
/// can run it with `dart run`.
///
/// See docs/designs/open-food-facts.md, "The product mapping".
OpenFoodFactsMappingResult mapOpenFoodFactsProduct(
  Map<String, Object?> product, {
  String? fallbackCode,
}) {
  final code = _string(product['code']) ?? _string(fallbackCode);
  if (code == null) {
    return const ExcludedOpenFoodFactsProduct(
        OpenFoodFactsExclusion.missingCode);
  }
  final name = _firstString(
    product,
    const <String>['product_name', 'product_name_en', 'generic_name'],
  );
  if (name == null) {
    return const ExcludedOpenFoodFactsProduct(
        OpenFoodFactsExclusion.missingName);
  }
  final modifiedSeconds = _number(product['last_modified_t']);
  // A change date DateTime cannot hold is as unusable as a missing one.
  if (modifiedSeconds == null || modifiedSeconds.abs() > _maxDateTimeSeconds) {
    return const ExcludedOpenFoodFactsProduct(
      OpenFoodFactsExclusion.missingChangeDate,
    );
  }

  final nutrientText = _nutrientText(product);
  if (_isImplausible(nutrientText)) {
    return const ExcludedOpenFoodFactsProduct(
        OpenFoodFactsExclusion.implausible);
  }

  final serving = _quantity(
    value: product['serving_quantity'],
    unit: product['serving_quantity_unit'],
    fallbackText: product['serving_size'],
  );
  final package = _quantity(
    value: product['product_quantity'],
    unit: product['product_quantity_unit'],
    fallbackText: product['quantity'],
  );
  final scans = _number(product['unique_scans_n']);

  return MappedOpenFoodFactsProduct(
    code: code,
    name: name,
    brand: _firstBrand(product['brands']),
    isLiquid: serving?.isLiquid ?? package?.isLiquid ?? false,
    servingLabel: serving == null ? null : 'serving',
    servingSize: serving?.baseQuantity,
    packageSize: package?.baseQuantity,
    nutrientText: nutrientText,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      modifiedSeconds.truncate() * 1000,
      isUtc: true,
    ),
    scans: scans?.truncate(),
  );
}

/// The largest Unix time in seconds a `DateTime` can hold (±8.64e15 ms).
const _maxDateTimeSeconds = 8640000000000;

sealed class OpenFoodFactsMappingResult {
  const OpenFoodFactsMappingResult();
}

class MappedOpenFoodFactsProduct extends OpenFoodFactsMappingResult {
  const MappedOpenFoodFactsProduct({
    required this.code,
    required this.name,
    required this.brand,
    required this.isLiquid,
    required this.servingLabel,
    required this.servingSize,
    required this.packageSize,
    required this.nutrientText,
    required this.modifiedAt,
    required this.scans,
  });

  final String code;
  final String name;
  final String? brand;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;

  /// Each known Nutrient's value per 100 g or ml, as its `entered` text in the
  /// Nutrient's default unit. An absent Nutrient is unknown, never zero.
  final Map<NutrientId, String> nutrientText;

  /// The product's change date (`last_modified_t`), in UTC.
  final DateTime modifiedAt;

  /// `unique_scans_n`, used only to rank.
  final int? scans;
}

class ExcludedOpenFoodFactsProduct extends OpenFoodFactsMappingResult {
  const ExcludedOpenFoodFactsProduct(this.reason);

  final OpenFoodFactsExclusion reason;
}

enum OpenFoodFactsExclusion {
  missingCode,
  missingName,

  /// No `last_modified_t`: the newer-copy rule needs a change date.
  missingChangeDate,

  /// A value that cannot be right per 100 g or ml.
  implausible,
}

/// Builds the vector a reader uses: the text is the `entered` text and the
/// parsed number is the value, so the app and the server read the same number
/// from the same text. Absent Nutrients are unknown.
NutrientVector nutrientVectorFromText(Map<NutrientId, String> text) {
  return NutrientVector.full(<NutrientId, NutrientAmount>{
    for (final MapEntry(key: id, value: entered) in text.entries)
      id: NutrientAmount.complete(
        value: double.parse(entered),
        entered: entered,
        unit: id.defaultUnit,
      ),
  });
}

/// The `entered` text of every complete amount; the inverse of
/// [nutrientVectorFromText] for complete amounts.
Map<NutrientId, String> nutrientTextFromVector(NutrientVector vector) {
  return <NutrientId, String>{
    for (final id in NutrientId.values)
      if (vector[id]
          case NutrientAmount(
            status: NutrientValueStatus.complete,
            :final entered?,
          ))
        id: entered,
  };
}

PlatformFoodRecord toPlatformFoodRecord(MappedOpenFoodFactsProduct product) {
  return PlatformFoodRecord(
    id: product.code,
    name: product.name,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: nutrientVectorFromText(product.nutrientText),
    isLiquid: product.isLiquid,
    servingLabel: product.servingLabel,
    servingSize: product.servingSize,
    packageSize: product.packageSize,
    brand: product.brand,
    sourceModifiedAt: product.modifiedAt,
    scans: product.scans,
  );
}

/// Which of Open Food Facts' two nutrition structures the mapping reads for
/// [product]: `nutrition.aggregated_set` when it is per 100 g or ml as sold,
/// otherwise legacy `nutriments`. The builder's report calls this too, so the
/// report and the mapping cannot disagree.
///
/// See docs/designs/open-food-facts.md, "Where nutrient values are read from".
OpenFoodFactsNutrientStructure openFoodFactsNutrientStructure(
  Map<String, Object?> product,
) {
  return _qualifyingAggregatedSet(product) == null
      ? OpenFoodFactsNutrientStructure.nutriments
      : OpenFoodFactsNutrientStructure.nutrition;
}

/// `nutrition.aggregated_set` when it is per 100 g or ml as sold, else `null`.
Map<Object?, Object?>? _qualifyingAggregatedSet(Map<String, Object?> product) {
  return switch (product) {
    {
      'nutrition': {
        'aggregated_set': {
              'per': '100g' || '100ml',
              'preparation': 'as_sold',
            } &&
            final Map<Object?, Object?> aggregated,
      },
    } =>
      aggregated,
    _ => null,
  };
}

enum OpenFoodFactsNutrientStructure { nutrition, nutriments }

/// The barcodes to try for a scanned or typed code, in order. Golden-vectored
/// with the server's `barcodeCandidates` (`apps/server/src/barcode-candidates.ts`)
/// through `packages/golden-vectors/vectors/m36-barcode-candidates.json`.
///
/// Whitespace and hyphens are removed; anything that is not then 6 to 18
/// digits is not a barcode. A 12-digit UPC-A code is also tried with a leading
/// `0`, as Open Food Facts usually stores it, and a 13-digit code starting
/// with `0` is also tried without it.
List<String> barcodeCandidates(String raw) {
  final code = raw.replaceAll(_barcodeSeparators, '');
  if (!_barcodeDigits.hasMatch(code)) {
    return const <String>[];
  }
  return <String>[
    code,
    if (code.length == 12) '0$code',
    if (code.length == 13 && code.startsWith('0')) code.substring(1),
  ];
}

/// The FTS5 match expression for a picker query, or `null` when the query has
/// no parts. The query is lower-cased and split on every character that is not
/// a Unicode letter, digit or combining mark; the first 8 parts become quoted prefix terms
/// that must all match (`"chobani"* "gr"*`). Quoting makes typed FTS5
/// operators (`AND`, `NEAR`, `*`, `:`) plain text.
String? buildFoodSearchMatch(String query) {
  final parts = query
      .toLowerCase()
      .split(_searchPartSeparators)
      .where((part) => part.isNotEmpty)
      .take(_maxSearchParts)
      .toList();
  if (parts.isEmpty) {
    return null;
  }
  return parts.map((part) => '"$part"*').join(' ');
}

final _barcodeSeparators = RegExp(r'[\s-]');
final _barcodeDigits = RegExp(r'^\d{6,18}$');
// Combining marks (\p{M}) stay inside a part, as the FTS5 unicode61
// tokenizer keeps them inside a token, so a decomposed "Cre\u0300me" is one
// part, not two.
final _searchPartSeparators = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);
const _maxSearchParts = 8;

/// The `fields` every live request asks for, comma-joined. Both nutrition
/// structures are requested; `nutrition.aggregated_set` leaves out the input
/// sets, which the mapping does not read.
const openFoodFactsFields = 'code,product_name,product_name_en,generic_name,'
    'brands,nutrition.aggregated_set,nutriments,serving_quantity,'
    'serving_quantity_unit,serving_size,product_quantity,'
    'product_quantity_unit,quantity,unique_scans_n,last_modified_t';

/// Shown with every Open Food Facts food (Goal 7).
const openFoodFactsDisclaimer =
    'Values come from Open Food Facts contributors and may be incomplete or '
    'wrong. Check the label. Not for medical use.';

/// The product's own page, where a user can check and correct its data.
String openFoodFactsProductUrl(String code) =>
    '${openFoodFactsBaseUrl}product/${Uri.encodeComponent(code)}';

/// Open Food Facts' site and API host.
const openFoodFactsBaseUrl = 'https://world.openfoodfacts.org/';

/// The shipped bundle, relative to `apps/mobile`: the builder writes it, the
/// app installs it, and the asset test checks it.
const openFoodFactsBundleAssetPath =
    'assets/seeds/open_food_facts_bundle.ndjson.gz';

/// The compact nutrient form: Nutrient storage key → entered text, in
/// [NutrientId] order. A bundle product line and a stored device row both
/// carry it.
Map<String, String> nutrientTextToJson(Map<NutrientId, String> text) {
  return <String, String>{
    for (final id in NutrientId.values)
      if (text[id] case final entered?) id.storageKey: entered,
  };
}

/// The inverse of [nutrientTextToJson]; an unknown key is an error.
Map<NutrientId, String> nutrientTextFromJson(Map<String, Object?> json) {
  return <NutrientId, String>{
    for (final MapEntry(:key, :value) in json.entries)
      NutrientId.byStorageKey(key): value! as String,
  };
}

// The bundle format. See docs/designs/open-food-facts.md, "The bundle file".

const bundleFormat = 'perennia-open-food-facts-bundle';
const bundleFormatVersion = 1;

/// One product line, without its newline. Every key is always present, in the
/// order written here, with no extra whitespace. A bundled product
/// always has a scan count (the builder keeps only scanned products).
String encodeBundleProductLine(MappedOpenFoodFactsProduct product) {
  final scans = product.scans;
  if (scans == null) {
    throw ArgumentError.value(product.code, 'product', 'has no scan count');
  }
  return jsonEncode(<String, Object?>{
    'code': product.code,
    'name': product.name,
    'brand': product.brand,
    'isLiquid': product.isLiquid,
    'servingLabel': product.servingLabel,
    'servingSize': _compactNumber(product.servingSize),
    'packageSize': _compactNumber(product.packageSize),
    'nutrients': nutrientTextToJson(product.nutrientText),
    'modifiedAt': product.modifiedAt.millisecondsSinceEpoch ~/ 1000,
    'scans': scans,
  });
}

MappedOpenFoodFactsProduct decodeBundleProductLine(String line) {
  final json = jsonDecode(line);
  if (json is! Map<String, Object?>) {
    throw const FormatException('A bundle product line is not an object.');
  }
  final nutrients = json['nutrients'];
  if (nutrients is! Map<String, Object?>) {
    throw const FormatException('A bundle product line has no nutrients.');
  }
  return MappedOpenFoodFactsProduct(
    code: json['code']! as String,
    name: json['name']! as String,
    brand: json['brand'] as String?,
    isLiquid: json['isLiquid']! as bool,
    servingLabel: json['servingLabel'] as String?,
    servingSize: (json['servingSize'] as num?)?.toDouble(),
    packageSize: (json['packageSize'] as num?)?.toDouble(),
    nutrientText: nutrientTextFromJson(nutrients),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['modifiedAt']! as int) * 1000,
      isUtc: true,
    ),
    scans: json['scans']! as int,
  );
}

/// The bundle's first line.
class BundleHeader {
  const BundleHeader({
    required this.format,
    required this.formatVersion,
    required this.datasetVersion,
    required this.contentHash,
    required this.sourceName,
    required this.sourceUrl,
    required this.licenseName,
    required this.licenseUrl,
    required this.contentsLicenseUrl,
    required this.attributionText,
    required this.countries,
    required this.perCountryLimit,
    required this.productCount,
  });

  factory BundleHeader.fromJsonLine(String line) {
    final json = jsonDecode(line);
    if (json is! Map<String, Object?>) {
      throw const FormatException('The bundle header is not an object.');
    }
    return BundleHeader(
      format: json['format']! as String,
      formatVersion: json['formatVersion']! as int,
      datasetVersion: json['datasetVersion']! as String,
      contentHash: json['contentHash']! as String,
      sourceName: json['sourceName']! as String,
      sourceUrl: json['sourceUrl']! as String,
      licenseName: json['licenseName']! as String,
      licenseUrl: json['licenseUrl']! as String,
      contentsLicenseUrl: json['contentsLicenseUrl']! as String,
      attributionText: json['attributionText']! as String,
      countries: List<String>.unmodifiable(json['countries']! as List<Object?>),
      perCountryLimit: json['perCountryLimit']! as int,
      productCount: json['productCount']! as int,
    );
  }

  final String format;
  final int formatVersion;

  /// The dump's `Last-Modified` date, `YYYY-MM-DD`.
  final String datasetVersion;

  /// SHA-256 of the bytes after the header line's newline, lowercase hex.
  final String contentHash;
  final String sourceName;
  final String sourceUrl;
  final String licenseName;
  final String licenseUrl;
  final String contentsLicenseUrl;
  final String attributionText;
  final List<String> countries;
  final int perCountryLimit;
  final int productCount;

  String toJsonLine() {
    return jsonEncode(<String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'datasetVersion': datasetVersion,
      'contentHash': contentHash,
      'sourceName': sourceName,
      'sourceUrl': sourceUrl,
      'licenseName': licenseName,
      'licenseUrl': licenseUrl,
      'contentsLicenseUrl': contentsLicenseUrl,
      'attributionText': attributionText,
      'countries': countries,
      'perCountryLimit': perCountryLimit,
      'productCount': productCount,
    });
  }
}

// Mapping helpers.

/// Each Nutrient's key in `nutrition.aggregated_set.nutrients` and its
/// `_100g` keys in legacy `nutriments` (primary first, then aliases). Energy is
/// kilocalories only: `energy-kcal_value` is on the label's basis, which can be
/// per serving, and kilojoules are not converted.
const _nutrientKeys = <(NutrientId, String, List<String>)>[
  (NutrientId.energy, 'energy-kcal', ['energy-kcal_100g']),
  (NutrientId.protein, 'proteins', ['proteins_100g']),
  (NutrientId.carbohydrate, 'carbohydrates', ['carbohydrates_100g']),
  (NutrientId.sugar, 'sugars', ['sugars_100g']),
  (NutrientId.fat, 'fat', ['fat_100g']),
  (NutrientId.saturatedFat, 'saturated-fat', ['saturated-fat_100g']),
  (
    NutrientId.monounsaturatedFat,
    'monounsaturated-fat',
    ['monounsaturated-fat_100g', 'mono-unsaturated-fat_100g'],
  ),
  (
    NutrientId.polyunsaturatedFat,
    'polyunsaturated-fat',
    ['polyunsaturated-fat_100g', 'poly-unsaturated-fat_100g'],
  ),
  (NutrientId.fiber, 'fiber', ['fiber_100g', 'fibers_100g']),
  (NutrientId.sodium, 'sodium', ['sodium_100g']),
  (NutrientId.cholesterol, 'cholesterol', ['cholesterol_100g']),
  (NutrientId.caffeine, 'caffeine', ['caffeine_100g']),
];

/// Mass units accepted in `nutrition.aggregated_set`, as powers of ten of a
/// gram. `µg` is accepted with the micro sign (U+00B5) and the Greek mu
/// (U+03BC).
const _gramExponentByUnit = <String, int>{
  'g': 0,
  'mg': -3,
  '\u00b5g': -6,
  '\u03bcg': -6,
  'mcg': -6,
};

/// The most a value can be per 100 g or ml before the product is excluded as
/// implausible.
const _maxPer100 = <NutrientId, double>{
  NutrientId.energy: 900,
  NutrientId.protein: 100,
  NutrientId.carbohydrate: 100,
  NutrientId.sugar: 100,
  NutrientId.fat: 100,
  NutrientId.saturatedFat: 100,
  NutrientId.monounsaturatedFat: 100,
  NutrientId.polyunsaturatedFat: 100,
  NutrientId.fiber: 100,
};

/// Reads every Nutrient from the one structure
/// [openFoodFactsNutrientStructure] picks, never a mix, then drops negative
/// values and formats the rest. The plausibility check runs on this text.
Map<NutrientId, String> _nutrientText(Map<String, Object?> product) {
  final aggregated = _qualifyingAggregatedSet(product);
  final values = aggregated == null
      ? _nutrimentsValues(product)
      : _aggregatedValues(aggregated);
  return <NutrientId, String>{
    for (final MapEntry(key: id, :value) in values.entries)
      if (value >= 0) id: formatNutrientEntered(value),
  };
}

Map<NutrientId, double> _aggregatedValues(Map<Object?, Object?> aggregated) {
  final nutrients = aggregated['nutrients'];
  if (nutrients is! Map) {
    return const <NutrientId, double>{};
  }
  final values = <NutrientId, double>{};
  for (final (id, key, _) in _nutrientKeys) {
    final entry = nutrients[key];
    if (entry is! Map || entry['source'] == 'estimate') {
      continue;
    }
    final value = _number(entry['value']);
    final unit = entry['unit'];
    if (value == null || unit is! String) {
      continue;
    }
    final converted = _convertUnit(value, unit.trim(), id.defaultUnit);
    if (converted != null) {
      values[id] = converted;
    }
  }
  return values;
}

/// Converts [value] from [unit] (trimmed, matched exactly) into [target], or
/// returns `null` when the unit is not accepted for it or the converted value
/// is not finite: a huge gram value scaled to micrograms can overflow to
/// infinity, and a value must be finite to be kept.
double? _convertUnit(double value, String unit, NutrientUnit target) {
  if (target == NutrientUnit.kilocalorie) {
    return unit == 'kcal' ? value : null;
  }
  final from = _gramExponentByUnit[unit];
  final to = switch (target) {
    NutrientUnit.gram => 0,
    NutrientUnit.milligram => -3,
    NutrientUnit.microgram => -6,
    _ => null,
  };
  if (from == null || to == null) {
    return null;
  }
  // Multiply or divide by an exact power of ten, so 0.5 g is exactly 500 mg.
  final scale = math.pow(10, (from - to).abs()).toDouble();
  final converted = from >= to ? value * scale : value / scale;
  return converted.isFinite ? converted : null;
}

Map<NutrientId, double> _nutrimentsValues(Map<String, Object?> product) {
  final nutriments = product['nutriments'];
  if (nutriments is! Map) {
    return const <NutrientId, double>{};
  }
  final values = <NutrientId, double>{};
  for (final (id, _, keys) in _nutrientKeys) {
    for (final key in keys) {
      final value = _number(nutriments[key]);
      if (value != null) {
        // Legacy values are in grams, except energy in kilocalories.
        final unit = id.defaultUnit == NutrientUnit.kilocalorie ? 'kcal' : 'g';
        if (_convertUnit(value, unit, id.defaultUnit) case final converted?) {
          values[id] = converted;
        }
        break;
      }
    }
  }
  return values;
}

bool _isImplausible(Map<NutrientId, String> text) {
  return text.entries.any(
    (entry) => switch (_maxPer100[entry.key]) {
      final max? => double.parse(entry.value) > max,
      null => false,
    },
  );
}

String? _firstBrand(Object? brands) =>
    _string(_string(brands)?.split(',').first);

/// Writes an integral size as an integer (`170`, not `170.0`). Only below
/// 2^53, where every integer is exact as a double: `toInt` clamps larger
/// values to the int64 maximum, which would change them.
num? _compactNumber(double? value) {
  if (value == null) {
    return null;
  }
  return value.abs() < _maxExactInteger && value == value.truncateToDouble()
      ? value.toInt()
      : value;
}

const _maxExactInteger = 9007199254740992.0;

String? _firstString(Map<String, Object?> values, List<String> keys) {
  for (final key in keys) {
    final value = _string(values[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _string(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

double? _number(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

_Quantity? _quantity({
  required Object? value,
  required Object? unit,
  required Object? fallbackText,
}) {
  final parsedValue = _number(value);
  final parsedUnit = _string(unit);
  if (parsedValue != null && parsedUnit != null) {
    final quantity = _quantityFromValue(parsedValue, parsedUnit);
    if (quantity != null) {
      return quantity;
    }
  }

  final text = _string(fallbackText);
  if (text == null) {
    return null;
  }
  final match = _quantityText.firstMatch(text);
  if (match == null) {
    return null;
  }
  return _quantityFromValue(_number(match.group(1))!, match.group(2)!);
}

final _quantityText = RegExp(r'(-?\d+(?:[\.,]\d+)?)\s*([A-Za-z ]+)');
final _whitespaceRun = RegExp(r'\s+');

_Quantity? _quantityFromValue(double value, String unit) {
  if (value <= 0) {
    return null;
  }
  final normalizedUnit = unit
      .trim()
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(_whitespaceRun, ' ');
  return switch (normalizedUnit) {
    'g' || 'gram' || 'grams' => (baseQuantity: value, isLiquid: false),
    'kg' || 'kilogram' || 'kilograms' => (
        baseQuantity: value * 1000,
        isLiquid: false
      ),
    'oz' || 'ounce' || 'ounces' => (
        baseQuantity: value * gramsPerOunce,
        isLiquid: false
      ),
    'ml' || 'milliliter' || 'milliliters' || 'millilitre' || 'millilitres' => (
        baseQuantity: value,
        isLiquid: true
      ),
    'l' || 'liter' || 'liters' || 'litre' || 'litres' => (
        baseQuantity: value * 1000,
        isLiquid: true
      ),
    'fl oz' || 'floz' || 'fluid ounce' || 'fluid ounces' => (
        baseQuantity: value * millilitresPerFluidOunce,
        isLiquid: true
      ),
    _ => null,
  };
}

typedef _Quantity = ({double baseQuantity, bool isLiquid});
