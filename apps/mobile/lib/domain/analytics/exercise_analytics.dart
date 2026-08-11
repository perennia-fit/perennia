import '../training/training_dimensions.dart';

class ExerciseAnalyticsEngine {
  const ExerciseAnalyticsEngine();

  ExerciseAnalyticsResult compute({
    required ExerciseAnalyticsProfile profile,
    required Iterable<AnalyticsSet> sets,
  }) {
    final orderedSets = sets.toList(growable: false)..sort(_compareSets);
    final catalog = RecordCatalog(
      repMaxRecords: _repMaxRecords(profile, orderedSets),
      minAssistanceRecords: _minAssistanceRecords(profile, orderedSets),
      maxLoad: _bestScalarRecord(
        profile,
        orderedSets,
        RecordProfile.maxLoad,
        DimensionId.load,
        TrainingUnit.kilogram,
        prefersLower: false,
      ),
      maxReps: _bestScalarRecord(
        profile,
        orderedSets,
        RecordProfile.maxReps,
        DimensionId.reps,
        TrainingUnit.repetition,
        prefersLower: false,
      ),
      maxDuration: _bestScalarRecord(
        profile,
        orderedSets,
        RecordProfile.maxDuration,
        DimensionId.duration,
        TrainingUnit.second,
        prefersLower: false,
      ),
      minDuration: _bestScalarRecord(
        profile,
        orderedSets,
        RecordProfile.minDuration,
        DimensionId.duration,
        TrainingUnit.second,
        prefersLower: true,
      ),
      maxDistance: _bestScalarRecord(
        profile,
        orderedSets,
        RecordProfile.maxDistance,
        DimensionId.distance,
        TrainingUnit.kilometer,
        prefersLower: false,
      ),
      fastestPace: _fastestPaceRecord(profile, orderedSets),
    );

    final e1rm = profile.loadMode == ExerciseLoadMode.assisted
        ? const DerivedSeries.undefined()
        : DerivedSeries.defined(_estimatedOneRepMaxSeries(orderedSets));
    final volume = profile.loadMode == ExerciseLoadMode.assisted
        ? const DerivedSeries.undefined()
        : DerivedSeries.defined(_volumeSeries(profile, orderedSets));

    return ExerciseAnalyticsResult(
      profile: profile,
      recordCatalog: catalog,
      headlineRecords: catalog.recordsFor(profile.recordProfile),
      estimatedOneRepMax: e1rm,
      volume: volume,
    );
  }

  List<AnalyticsRecord> _repMaxRecords(
    ExerciseAnalyticsProfile profile,
    List<AnalyticsSet> sets,
  ) {
    if (profile.loadMode == ExerciseLoadMode.assisted ||
        !profile.type.hasDimension(DimensionId.load) ||
        !profile.type.hasDimension(DimensionId.reps)) {
      return const <AnalyticsRecord>[];
    }

    final bestByReps = <int, AnalyticsRecord>{};
    for (final set in sets) {
      final load = _metricValue(set.values.load, TrainingUnit.kilogram);
      final reps = _integerReps(set.values.reps);
      if (load == null || reps == null) {
        continue;
      }

      final candidate = AnalyticsRecord(
        profile: RecordProfile.repMax,
        setId: set.id,
        achievedAt: set.performedAt,
        sequence: set.sequence,
        value: load,
        unit: TrainingUnit.kilogram,
        reps: reps,
      );
      final current = bestByReps[reps];
      if (current == null || _isBetter(candidate, current)) {
        bestByReps[reps] = candidate;
      }
    }

    final records = bestByReps.values.where((record) {
      return !bestByReps.values.any(
        (other) =>
            other.reps != null &&
            record.reps != null &&
            other.reps! > record.reps! &&
            other.value >= record.value,
      );
    }).toList(growable: false)
      ..sort((left, right) => left.reps!.compareTo(right.reps!));

    return List<AnalyticsRecord>.unmodifiable(records);
  }

  List<AnalyticsRecord> _minAssistanceRecords(
    ExerciseAnalyticsProfile profile,
    List<AnalyticsSet> sets,
  ) {
    if (profile.loadMode != ExerciseLoadMode.assisted ||
        !profile.type.hasDimension(DimensionId.load)) {
      return const <AnalyticsRecord>[];
    }

    final bestByReps = <int, AnalyticsRecord>{};
    for (final set in sets) {
      final assistance = _metricValue(set.values.load, TrainingUnit.kilogram);
      final reps = _integerReps(set.values.reps);
      if (assistance == null || reps == null) {
        continue;
      }

      final candidate = AnalyticsRecord(
        profile: RecordProfile.minAssistancePerRepCount,
        setId: set.id,
        achievedAt: set.performedAt,
        sequence: set.sequence,
        value: assistance,
        unit: TrainingUnit.kilogram,
        reps: reps,
      );
      final current = bestByReps[reps];
      if (current == null ||
          _isBetter(candidate, current, prefersLower: true)) {
        bestByReps[reps] = candidate;
      }
    }

    final records = bestByReps.values.toList(growable: false)
      ..sort((left, right) => left.reps!.compareTo(right.reps!));
    return List<AnalyticsRecord>.unmodifiable(records);
  }

  AnalyticsRecord? _bestScalarRecord(
    ExerciseAnalyticsProfile profile,
    List<AnalyticsSet> sets,
    RecordProfile recordProfile,
    DimensionId dimension,
    TrainingUnit metricUnit, {
    required bool prefersLower,
  }) {
    if (!profile.type.hasDimension(dimension)) {
      return null;
    }

    AnalyticsRecord? best;
    for (final set in sets) {
      final value = _metricValue(set.values.valueFor(dimension), metricUnit);
      if (value == null) {
        continue;
      }

      final candidate = AnalyticsRecord(
        profile: recordProfile,
        setId: set.id,
        achievedAt: set.performedAt,
        sequence: set.sequence,
        value: value,
        unit: metricUnit,
      );
      if (best == null ||
          _isBetter(candidate, best, prefersLower: prefersLower)) {
        best = candidate;
      }
    }

    return best;
  }

  AnalyticsRecord? _fastestPaceRecord(
    ExerciseAnalyticsProfile profile,
    List<AnalyticsSet> sets,
  ) {
    if (!profile.type.hasDimension(DimensionId.distance) ||
        !profile.type.hasDimension(DimensionId.duration)) {
      return null;
    }

    AnalyticsRecord? best;
    for (final set in sets) {
      final distance = _metricValue(
        set.values.distance,
        TrainingUnit.kilometer,
      );
      final duration = _metricValue(set.values.duration, TrainingUnit.second);
      if (distance == null || duration == null || distance <= 0) {
        continue;
      }

      final candidate = AnalyticsRecord(
        profile: RecordProfile.fastestPace,
        setId: set.id,
        achievedAt: set.performedAt,
        sequence: set.sequence,
        value: duration / distance,
        unit: TrainingUnit.second,
      );
      if (best == null || _isBetter(candidate, best, prefersLower: true)) {
        best = candidate;
      }
    }

    return best;
  }

  List<AnalyticsPoint> _estimatedOneRepMaxSeries(List<AnalyticsSet> sets) {
    final points = <AnalyticsPoint>[];
    for (final set in sets) {
      final load = _metricValue(set.values.load, TrainingUnit.kilogram);
      final reps = _integerReps(set.values.reps);
      if (load == null || reps == null || reps < 1 || reps > 10) {
        continue;
      }

      points.add(
        AnalyticsPoint(
          setId: set.id,
          achievedAt: set.performedAt,
          value: load * 36 / (37 - reps),
          unit: TrainingUnit.kilogram,
        ),
      );
    }
    return List<AnalyticsPoint>.unmodifiable(points);
  }

  List<AnalyticsPoint> _volumeSeries(
    ExerciseAnalyticsProfile profile,
    List<AnalyticsSet> sets,
  ) {
    final points = <AnalyticsPoint>[];
    for (final set in sets) {
      final load = _metricValue(set.values.load, TrainingUnit.kilogram);
      final reps = _metricValue(set.values.reps, TrainingUnit.repetition);
      if (profile.type.hasDimension(DimensionId.load) &&
          profile.type.hasDimension(DimensionId.reps)) {
        if (load == null || reps == null) {
          continue;
        }

        points.add(
          AnalyticsPoint(
            setId: set.id,
            achievedAt: set.performedAt,
            value: load * reps,
            unit: TrainingUnit.kilogram,
          ),
        );
        continue;
      }

      if (profile.type.hasDimension(DimensionId.distance)) {
        final distance = _metricValue(
          set.values.distance,
          TrainingUnit.kilometer,
        );
        if (distance == null) {
          continue;
        }

        points.add(
          AnalyticsPoint(
            setId: set.id,
            achievedAt: set.performedAt,
            value: distance,
            unit: TrainingUnit.kilometer,
          ),
        );
        continue;
      }

      if (profile.type.hasDimension(DimensionId.duration)) {
        final duration = _metricValue(set.values.duration, TrainingUnit.second);
        if (duration == null) {
          continue;
        }

        points.add(
          AnalyticsPoint(
            setId: set.id,
            achievedAt: set.performedAt,
            value: duration,
            unit: TrainingUnit.second,
          ),
        );
      }
    }
    return List<AnalyticsPoint>.unmodifiable(points);
  }
}

class ExerciseAnalyticsProfile {
  const ExerciseAnalyticsProfile({
    required this.type,
    required this.loadMode,
    required this.recordProfile,
  });

  final ExerciseType type;
  final ExerciseLoadMode loadMode;
  final RecordProfile recordProfile;

  factory ExerciseAnalyticsProfile.defaults({
    required ExerciseType type,
    ExerciseLoadMode loadMode = ExerciseLoadMode.added,
  }) {
    return ExerciseAnalyticsProfile(
      type: type,
      loadMode: loadMode,
      recordProfile: defaultRecordProfileFor(type: type, loadMode: loadMode),
    );
  }

  ExerciseAnalyticsProfile copyWith({
    ExerciseType? type,
    ExerciseLoadMode? loadMode,
    RecordProfile? recordProfile,
  }) {
    return ExerciseAnalyticsProfile(
      type: type ?? this.type,
      loadMode: loadMode ?? this.loadMode,
      recordProfile: recordProfile ?? this.recordProfile,
    );
  }
}

class AnalyticsSet {
  const AnalyticsSet({
    required this.id,
    required this.performedAt,
    required this.sequence,
    required this.values,
  });

  final String id;
  final DateTime performedAt;
  final int sequence;
  final LoggedSet values;
}

class ExerciseAnalyticsResult {
  ExerciseAnalyticsResult({
    required this.profile,
    required this.recordCatalog,
    required Iterable<AnalyticsRecord> headlineRecords,
    required this.estimatedOneRepMax,
    required this.volume,
  }) : headlineRecords = List<AnalyticsRecord>.unmodifiable(headlineRecords);

  final ExerciseAnalyticsProfile profile;
  final RecordCatalog recordCatalog;
  final List<AnalyticsRecord> headlineRecords;
  final DerivedSeries estimatedOneRepMax;
  final DerivedSeries volume;

  AnalyticsRecord? get headlineRecord {
    if (headlineRecords.isEmpty) {
      return null;
    }
    return headlineRecords.reduce((best, candidate) {
      if (profile.recordProfile == RecordProfile.minAssistancePerRepCount ||
          profile.recordProfile == RecordProfile.minDuration ||
          profile.recordProfile == RecordProfile.fastestPace) {
        return _isBetter(candidate, best, prefersLower: true)
            ? candidate
            : best;
      }
      return _isBetter(candidate, best) ? candidate : best;
    });
  }
}

class RecordCatalog {
  RecordCatalog({
    required Iterable<AnalyticsRecord> repMaxRecords,
    required Iterable<AnalyticsRecord> minAssistanceRecords,
    required this.maxLoad,
    required this.maxReps,
    required this.maxDuration,
    required this.minDuration,
    required this.maxDistance,
    required this.fastestPace,
  })  : repMaxRecords = List<AnalyticsRecord>.unmodifiable(repMaxRecords),
        minAssistanceRecords =
            List<AnalyticsRecord>.unmodifiable(minAssistanceRecords);

  final List<AnalyticsRecord> repMaxRecords;
  final List<AnalyticsRecord> minAssistanceRecords;
  final AnalyticsRecord? maxLoad;
  final AnalyticsRecord? maxReps;
  final AnalyticsRecord? maxDuration;
  final AnalyticsRecord? minDuration;
  final AnalyticsRecord? maxDistance;
  final AnalyticsRecord? fastestPace;

  List<AnalyticsRecord> recordsFor(RecordProfile profile) {
    final scalar = switch (profile) {
      RecordProfile.repMax => null,
      RecordProfile.minAssistancePerRepCount => null,
      RecordProfile.maxLoad => maxLoad,
      RecordProfile.maxReps => maxReps,
      RecordProfile.maxDuration => maxDuration,
      RecordProfile.minDuration => minDuration,
      RecordProfile.maxDistance => maxDistance,
      RecordProfile.fastestPace => fastestPace,
      RecordProfile.completionStreak => null,
    };

    return switch (profile) {
      RecordProfile.repMax => repMaxRecords,
      RecordProfile.minAssistancePerRepCount => minAssistanceRecords,
      RecordProfile.completionStreak => const <AnalyticsRecord>[],
      _ => scalar == null
          ? const <AnalyticsRecord>[]
          : List<AnalyticsRecord>.unmodifiable(<AnalyticsRecord>[scalar]),
    };
  }
}

class AnalyticsRecord {
  const AnalyticsRecord({
    required this.profile,
    required this.setId,
    required this.achievedAt,
    required this.sequence,
    required this.value,
    required this.unit,
    this.reps,
  });

  final RecordProfile profile;
  final String setId;
  final DateTime achievedAt;
  final int sequence;
  final double value;
  final TrainingUnit unit;
  final int? reps;
}

class DerivedSeries {
  DerivedSeries.defined(Iterable<AnalyticsPoint> points)
      : isDefined = true,
        points = List<AnalyticsPoint>.unmodifiable(points);

  const DerivedSeries.undefined()
      : isDefined = false,
        points = const <AnalyticsPoint>[];

  final bool isDefined;
  final List<AnalyticsPoint> points;

  double? get total {
    if (!isDefined) {
      return null;
    }
    return points.fold<double>(0, (sum, point) => sum + point.value);
  }
}

class AnalyticsPoint {
  const AnalyticsPoint({
    required this.setId,
    required this.achievedAt,
    required this.value,
    required this.unit,
  });

  final String setId;
  final DateTime achievedAt;
  final double value;
  final TrainingUnit unit;
}

int _compareSets(AnalyticsSet left, AnalyticsSet right) {
  final timeComparison = left.performedAt.compareTo(right.performedAt);
  if (timeComparison != 0) {
    return timeComparison;
  }
  final sequenceComparison = left.sequence.compareTo(right.sequence);
  if (sequenceComparison != 0) {
    return sequenceComparison;
  }
  return left.id.compareTo(right.id);
}

bool _isBetter(
  AnalyticsRecord candidate,
  AnalyticsRecord current, {
  bool prefersLower = false,
}) {
  if (candidate.value != current.value) {
    return prefersLower
        ? candidate.value < current.value
        : candidate.value > current.value;
  }
  final timeComparison = candidate.achievedAt.compareTo(current.achievedAt);
  if (timeComparison != 0) {
    return timeComparison < 0;
  }
  if (candidate.sequence != current.sequence) {
    return candidate.sequence < current.sequence;
  }
  return candidate.setId.compareTo(current.setId) < 0;
}

double? _metricValue(SetDimensionValue? value, TrainingUnit metricUnit) {
  if (value == null) {
    return null;
  }
  return value.convertedTo(metricUnit);
}

int? _integerReps(SetDimensionValue? value) {
  final reps = _metricValue(value, TrainingUnit.repetition);
  if (reps == null || reps <= 0 || reps.roundToDouble() != reps) {
    return null;
  }
  return reps.toInt();
}
