import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/training/training_dimensions.dart';

abstract interface class PlatformExerciseSeedSource {
  Future<PlatformExerciseSeed> load();
}

class AssetPlatformExerciseSeedSource implements PlatformExerciseSeedSource {
  const AssetPlatformExerciseSeedSource({
    AssetBundle? bundle,
    this.assetPath = 'assets/seeds/platform_exercises.json',
  }) : _bundle = bundle;

  static final _rootBundleCache = <String, Future<PlatformExerciseSeed>>{};

  final AssetBundle? _bundle;
  final String assetPath;

  @override
  Future<PlatformExerciseSeed> load() async {
    final bundle = _bundle;
    if (bundle != null) {
      return _loadFromBundle(bundle);
    }

    return _rootBundleCache.putIfAbsent(
      assetPath,
      () => _loadFromBundle(rootBundle),
    );
  }

  Future<PlatformExerciseSeed> _loadFromBundle(AssetBundle bundle) async {
    final contents = await bundle.loadString(assetPath);
    return PlatformExerciseSeed.fromJson(
      jsonDecode(contents) as Map<String, Object?>,
    );
  }
}

class PlatformExerciseSeed {
  const PlatformExerciseSeed({
    this.metadata = const PlatformExerciseSeedMetadata.empty(),
    required this.categories,
    this.redirects = const <SeedExerciseRedirect>[],
    required this.exercises,
  });

  factory PlatformExerciseSeed.fromJson(Map<String, Object?> json) {
    final categories = json['categories'] as List<Object?>? ?? <Object?>[];
    final redirects =
        json['exercise_redirects'] as List<Object?>? ?? <Object?>[];
    final exercises = json['exercises'] as List<Object?>? ?? <Object?>[];

    return PlatformExerciseSeed(
      metadata: PlatformExerciseSeedMetadata.fromJson(
        json['metadata'] as Map<String, Object?>?,
      ),
      categories: categories
          .cast<Map<String, Object?>>()
          .map(SeedExerciseCategory.fromJson)
          .toList(growable: false),
      redirects: redirects
          .cast<Map<String, Object?>>()
          .map(SeedExerciseRedirect.fromJson)
          .toList(growable: false),
      exercises: exercises
          .cast<Map<String, Object?>>()
          .map(SeedExercise.fromJson)
          .toList(growable: false),
    );
  }

  final PlatformExerciseSeedMetadata metadata;
  final List<SeedExerciseCategory> categories;
  final List<SeedExerciseRedirect> redirects;
  final List<SeedExercise> exercises;
}

class SeedExerciseRedirect {
  const SeedExerciseRedirect({
    required this.fromExerciseId,
    required this.toExerciseId,
  });

  factory SeedExerciseRedirect.fromJson(Map<String, Object?> json) {
    return SeedExerciseRedirect(
      fromExerciseId: json['from_exercise_id']! as String,
      toExerciseId: json['to_exercise_id']! as String,
    );
  }

  final String fromExerciseId;
  final String toExerciseId;
}

class PlatformExerciseSeedMetadata {
  const PlatformExerciseSeedMetadata({
    required this.sourceName,
    required this.sourceUrl,
    required this.sourceCommit,
    required this.licenseSummary,
  });

  const PlatformExerciseSeedMetadata.empty()
      : sourceName = null,
        sourceUrl = null,
        sourceCommit = null,
        licenseSummary = null;

  factory PlatformExerciseSeedMetadata.fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return const PlatformExerciseSeedMetadata.empty();
    }

    return PlatformExerciseSeedMetadata(
      sourceName: json['source_name'] as String?,
      sourceUrl: json['source_url'] as String?,
      sourceCommit: json['source_commit'] as String?,
      licenseSummary: json['license_summary'] as String?,
    );
  }

  final String? sourceName;
  final String? sourceUrl;
  final String? sourceCommit;
  final String? licenseSummary;
}

class SeedExerciseCategory {
  const SeedExerciseCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.colorHex,
    required this.updatedAt,
  });

  factory SeedExerciseCategory.fromJson(Map<String, Object?> json) {
    return SeedExerciseCategory(
      id: json['id']! as String,
      name: json['name']! as String,
      sortOrder: json['sort_order']! as int,
      colorHex: json['color_hex']! as String,
      updatedAt: DateTime.parse(json['updated_at']! as String).toUtc(),
    );
  }

  final String id;
  final String name;
  final int sortOrder;
  final String colorHex;
  final DateTime updatedAt;
}

class SeedExercise {
  const SeedExercise({
    required this.id,
    required this.name,
    required this.dimensions,
    required this.categoryId,
    this.equipment = const <ExerciseEquipment>[],
    required this.notes,
    required this.updatedAt,
  });

  factory SeedExercise.fromJson(Map<String, Object?> json) {
    final dimensionNames =
        (json['dimension_ids'] as List<Object?>? ?? <Object?>[]).cast<String>();
    final equipmentIds =
        (json['equipment_ids'] as List<Object?>? ?? <Object?>[]).cast<String>();

    return SeedExercise(
      id: json['id']! as String,
      name: json['name']! as String,
      dimensions: dimensionNames
          .map((dimension) => DimensionId.values.byName(dimension))
          .toList(growable: false),
      categoryId: json['category_id'] as String?,
      equipment:
          equipmentIds.map(ExerciseEquipment.fromId).toList(growable: false),
      notes: json['notes'] as String?,
      updatedAt: DateTime.parse(json['updated_at']! as String).toUtc(),
    );
  }

  final String id;
  final String name;
  final List<DimensionId> dimensions;
  final String? categoryId;
  final List<ExerciseEquipment> equipment;
  final String? notes;
  final DateTime updatedAt;
}
