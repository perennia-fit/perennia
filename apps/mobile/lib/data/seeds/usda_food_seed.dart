import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/nutrition/nutrition.dart';

abstract interface class UsdaFoodSeedSource {
  Future<UsdaFoodSeed> load();
}

class AssetUsdaFoodSeedSource implements UsdaFoodSeedSource {
  const AssetUsdaFoodSeedSource({
    AssetBundle? bundle,
    this.assetPath = 'assets/seeds/usda_foods.json',
  }) : _bundle = bundle;

  final AssetBundle? _bundle;
  final String assetPath;

  @override
  Future<UsdaFoodSeed> load() async {
    final contents = await (_bundle ?? rootBundle).loadString(assetPath);
    return UsdaFoodSeed.fromJson(
      jsonDecode(contents) as Map<String, Object?>,
    );
  }
}

class UsdaFoodSeed {
  const UsdaFoodSeed({
    required this.metadata,
    required this.foods,
  });

  factory UsdaFoodSeed.fromJson(Map<String, Object?> json) {
    final metadataJson = _requiredObject(json, 'metadata');
    final foodsJson = json['foods'] as List<Object?>? ?? <Object?>[];
    final metadata = UsdaFoodSeedMetadata.fromJson(metadataJson);

    return UsdaFoodSeed(
      metadata: metadata,
      foods: foodsJson
          .cast<Map<String, Object?>>()
          .map((foodJson) => _platformFoodFromJson(foodJson, metadata))
          .toList(growable: false),
    );
  }

  final UsdaFoodSeedMetadata metadata;
  final List<PlatformFoodRecord> foods;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metadata': metadata.toJson(),
      'foods': foods.map(_platformFoodToJson).toList(growable: false),
    };
  }
}

class UsdaFoodSeedMetadata {
  const UsdaFoodSeedMetadata({
    required this.datasetVersion,
    required this.sourceName,
    required this.sourceUrl,
    required this.licenseName,
    required this.attributionText,
    this.foodSource = FoodSource.usda,
  });

  factory UsdaFoodSeedMetadata.fromJson(Map<String, Object?> json) {
    return UsdaFoodSeedMetadata(
      datasetVersion: _requiredString(json, 'dataset_version'),
      sourceName: _requiredString(json, 'source_name'),
      sourceUrl: _requiredString(json, 'source_url'),
      licenseName: _requiredString(json, 'license_name'),
      attributionText: _requiredString(json, 'attribution_text'),
      foodSource: FoodSource.values.byName(
        json['food_source'] as String? ?? FoodSource.usda.name,
      ),
    );
  }

  final String datasetVersion;
  final String sourceName;
  final String sourceUrl;
  final String licenseName;
  final String attributionText;
  final FoodSource foodSource;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'dataset_version': datasetVersion,
      'source_name': sourceName,
      'source_url': sourceUrl,
      'license_name': licenseName,
      'attribution_text': attributionText,
      'food_source': foodSource.name,
    };
  }
}

PlatformFoodRecord _platformFoodFromJson(
  Map<String, Object?> json,
  UsdaFoodSeedMetadata metadata,
) {
  return PlatformFoodRecord(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    foodSource: FoodSource.values.byName(
      json['food_source'] as String? ?? metadata.foodSource.name,
    ),
    nutrientsPer100: NutrientVector.fromJson(
      _requiredObject(json, 'nutrients_per_100'),
    ),
    isLiquid: _requiredBool(json, 'is_liquid'),
    servingLabel: _optionalTrimmedString(json, 'serving_label'),
    servingSize: _optionalDouble(json, 'serving_size'),
    packageSize: _optionalDouble(json, 'package_size'),
  );
}

Map<String, Object?> _platformFoodToJson(PlatformFoodRecord food) {
  return <String, Object?>{
    'id': food.id,
    'name': food.name,
    'food_source': food.foodSource.name,
    'is_liquid': food.isLiquid,
    'serving_label': food.servingLabel,
    'serving_size': food.servingSize,
    'package_size': food.packageSize,
    'nutrients_per_100': food.nutrientsPer100.toJson(),
  };
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  throw FormatException('Expected object field $key.', json);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  throw FormatException('Expected non-empty string field $key.', json);
}

String? _optionalTrimmedString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  throw FormatException('Expected optional string field $key.', json);
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected optional numeric field $key.', json);
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected boolean field $key.', json);
}
