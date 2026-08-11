enum DimensionId {
  load,
  reps,
  duration,
  distance,
}

enum TrainingUnit {
  kilogram,
  pound,
  repetition,
  second,
  kilometer,
  mile,
}

enum ExerciseLoadMode {
  added,
  assisted,
}

enum RecordProfile {
  repMax,
  maxLoad,
  maxReps,
  maxDuration,
  minDuration,
  maxDistance,
  fastestPace,
  minAssistancePerRepCount,
  completionStreak,
}

class ExerciseEquipment {
  factory ExerciseEquipment.fromId(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Equipment id cannot be blank.');
    }
    return _knownById[normalizedId] ?? ExerciseEquipment._(normalizedId);
  }

  const ExerciseEquipment._(this.id);

  static const bodyweight = ExerciseEquipment._('bodyweight');
  static const dumbbell = ExerciseEquipment._('dumbbell');
  static const barbell = ExerciseEquipment._('barbell');
  static const kettlebell = ExerciseEquipment._('kettlebell');
  static const band = ExerciseEquipment._('band');
  static const plate = ExerciseEquipment._('plate');
  static const pullUpBar = ExerciseEquipment._('pullUpBar');
  static const bench = ExerciseEquipment._('bench');
  static const inclineBench = ExerciseEquipment._('inclineBench');
  static const gymMat = ExerciseEquipment._('gymMat');
  static const swissBall = ExerciseEquipment._('swissBall');
  static const ezBar = ExerciseEquipment._('ezBar');
  static const cable = ExerciseEquipment._('cable');
  static const machine = ExerciseEquipment._('machine');
  static const smithMachine = ExerciseEquipment._('smithMachine');
  static const medicineBall = ExerciseEquipment._('medicineBall');
  static const foamRoll = ExerciseEquipment._('foamRoll');
  static const trx = ExerciseEquipment._('trx');
  static const box = ExerciseEquipment._('box');
  static const bosu = ExerciseEquipment._('bosu');
  static const rope = ExerciseEquipment._('rope');
  static const spinBike = ExerciseEquipment._('spinBike');
  static const step = ExerciseEquipment._('step');
  static const sled = ExerciseEquipment._('sled');
  static const sandbag = ExerciseEquipment._('sandbag');
  static const wall = ExerciseEquipment._('wall');
  static const rack = ExerciseEquipment._('rack');
  static const skiErg = ExerciseEquipment._('skiErg');

  static const known = <ExerciseEquipment>[
    bodyweight,
    dumbbell,
    barbell,
    kettlebell,
    band,
    plate,
    pullUpBar,
    bench,
    inclineBench,
    gymMat,
    swissBall,
    ezBar,
    cable,
    machine,
    smithMachine,
    medicineBall,
    foamRoll,
    trx,
    box,
    bosu,
    rope,
    spinBike,
    step,
    sled,
    sandbag,
    wall,
    rack,
    skiErg,
  ];

  static final _knownById = <String, ExerciseEquipment>{
    for (final equipment in known) equipment.id: equipment,
  };

  static const _labelsById = <String, String>{
    'bodyweight': 'Bodyweight',
    'dumbbell': 'Dumbbell',
    'barbell': 'Barbell',
    'kettlebell': 'Kettlebell',
    'band': 'Band',
    'plate': 'Plate',
    'pullUpBar': 'Pull-up bar',
    'bench': 'Bench',
    'inclineBench': 'Incline bench',
    'gymMat': 'Gym mat',
    'swissBall': 'Swiss ball',
    'ezBar': 'EZ bar',
    'cable': 'Cable',
    'machine': 'Machine',
    'smithMachine': 'Smith machine',
    'medicineBall': 'Medicine ball',
    'foamRoll': 'Foam roll',
    'trx': 'TRX',
    'box': 'Box',
    'bosu': 'BOSU',
    'rope': 'Rope',
    'spinBike': 'Spin bike',
    'step': 'Step',
    'sled': 'Sled',
    'sandbag': 'Sandbag',
    'wall': 'Wall',
    'rack': 'Rack',
    'skiErg': 'SkiErg',
  };

  final String id;

  String get label => _labelsById[id] ?? _humanizeEquipmentId(id);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ExerciseEquipment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

class DimensionDefinition {
  factory DimensionDefinition({
    required DimensionId id,
    required Iterable<TrainingUnit> units,
  }) {
    return DimensionDefinition._(
      id: id,
      units: Set<TrainingUnit>.unmodifiable(units),
    );
  }

  const DimensionDefinition._({
    required this.id,
    required this.units,
  });

  final DimensionId id;
  final Set<TrainingUnit> units;

  bool allowsUnit(TrainingUnit unit) => units.contains(unit);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DimensionDefinition &&
            other.id == id &&
            _unorderedSetEquals(other.units, units);
  }

  @override
  int get hashCode => Object.hash(id, Object.hashAllUnordered(units));

  double convertValue({
    required String entered,
    required TrainingUnit from,
    required TrainingUnit to,
  }) {
    if (!allowsUnit(from)) {
      throw ArgumentError.value(
        from,
        'from',
        'Unit is not valid for ${id.name}.',
      );
    }
    if (!allowsUnit(to)) {
      throw ArgumentError.value(
        to,
        'to',
        'Target unit is not valid for ${id.name}.',
      );
    }

    final numericValue = double.parse(entered);

    return switch (id) {
      DimensionId.load => _convertLoad(numericValue, from, to),
      DimensionId.reps => numericValue,
      DimensionId.duration => numericValue,
      DimensionId.distance => _convertDistance(numericValue, from, to),
    };
  }

  double _convertLoad(double value, TrainingUnit from, TrainingUnit to) {
    final kilograms = switch (from) {
      TrainingUnit.kilogram => value,
      TrainingUnit.pound => value * 0.45359237,
      _ => throw StateError('Unsupported load unit: ${from.name}.'),
    };

    return switch (to) {
      TrainingUnit.kilogram => kilograms,
      TrainingUnit.pound => kilograms / 0.45359237,
      _ => throw StateError('Unsupported target load unit: ${to.name}.'),
    };
  }

  double _convertDistance(double value, TrainingUnit from, TrainingUnit to) {
    final kilometers = switch (from) {
      TrainingUnit.kilometer => value,
      TrainingUnit.mile => value * 1.609344,
      _ => throw StateError('Unsupported distance unit: ${from.name}.'),
    };

    return switch (to) {
      TrainingUnit.kilometer => kilometers,
      TrainingUnit.mile => kilometers / 1.609344,
      _ => throw StateError('Unsupported target distance unit: ${to.name}.'),
    };
  }
}

class DimensionRegistry {
  const DimensionRegistry._();

  static const _definitions = <DimensionId, DimensionDefinition>{
    DimensionId.load: DimensionDefinition._(
      id: DimensionId.load,
      units: <TrainingUnit>{TrainingUnit.kilogram, TrainingUnit.pound},
    ),
    DimensionId.reps: DimensionDefinition._(
      id: DimensionId.reps,
      units: <TrainingUnit>{TrainingUnit.repetition},
    ),
    DimensionId.duration: DimensionDefinition._(
      id: DimensionId.duration,
      units: <TrainingUnit>{TrainingUnit.second},
    ),
    DimensionId.distance: DimensionDefinition._(
      id: DimensionId.distance,
      units: <TrainingUnit>{TrainingUnit.kilometer, TrainingUnit.mile},
    ),
  };

  static final ids = List<DimensionId>.unmodifiable(_definitions.keys);

  static DimensionDefinition byId(DimensionId id) => _definitions[id]!;
}

class ExerciseType {
  factory ExerciseType(Iterable<DimensionId> dimensions) {
    final dimensionList = List<DimensionId>.unmodifiable(dimensions);
    if (dimensionList.toSet().length != dimensionList.length) {
      throw ArgumentError.value(
        dimensions,
        'dimensions',
        'Exercise type dimensions must be unique.',
      );
    }

    return ExerciseType._(dimensionList);
  }

  const ExerciseType._(this._dimensions);

  static const empty = ExerciseType._(<DimensionId>[]);

  final List<DimensionId> _dimensions;

  List<DimensionId> get dimensions => _dimensions;

  bool get isCompletionOnly => dimensions.isEmpty;

  bool hasDimension(DimensionId id) => dimensions.contains(id);

  bool accepts(LoggedSet set) {
    if (dimensions.length != set.dimensionIds.length) {
      return false;
    }

    final expected = dimensions.toSet();
    return set.dimensionIds.every(expected.contains);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ExerciseType &&
            _orderedListEquals(other._dimensions, _dimensions);
  }

  @override
  int get hashCode => Object.hashAll(_dimensions);
}

RecordProfile defaultRecordProfileFor({
  required ExerciseType type,
  required ExerciseLoadMode loadMode,
}) {
  if (type.isCompletionOnly) {
    return RecordProfile.completionStreak;
  }
  if (loadMode == ExerciseLoadMode.assisted &&
      type.hasDimension(DimensionId.load)) {
    return RecordProfile.minAssistancePerRepCount;
  }
  if (type.hasDimension(DimensionId.load) &&
      type.hasDimension(DimensionId.reps)) {
    return RecordProfile.repMax;
  }
  if (type.hasDimension(DimensionId.reps)) {
    return RecordProfile.maxReps;
  }
  if (type.hasDimension(DimensionId.distance) &&
      type.hasDimension(DimensionId.duration)) {
    return RecordProfile.fastestPace;
  }
  if (type.hasDimension(DimensionId.duration)) {
    return RecordProfile.maxDuration;
  }
  if (type.hasDimension(DimensionId.distance)) {
    return RecordProfile.maxDistance;
  }
  if (type.hasDimension(DimensionId.load)) {
    return RecordProfile.maxLoad;
  }

  return RecordProfile.completionStreak;
}

class LoggedSet {
  const LoggedSet._(this._values);

  factory LoggedSet.completion() => const LoggedSet._(
        <DimensionId, SetDimensionValue>{},
      );

  factory LoggedSet.fromValues(Iterable<SetDimensionValue> values) {
    final mappedValues = <DimensionId, SetDimensionValue>{};

    for (final value in values) {
      final definition = DimensionRegistry.byId(value.dimension);
      if (!definition.allowsUnit(value.unit)) {
        throw ArgumentError.value(
          value.unit,
          'unit',
          'Unit is not valid for ${value.dimension.name}.',
        );
      }

      double.parse(value.entered);

      if (mappedValues.containsKey(value.dimension)) {
        throw ArgumentError.value(
          value.dimension,
          'dimension',
          'Each logged set can carry a dimension at most once.',
        );
      }

      mappedValues[value.dimension] = value;
    }

    return LoggedSet._(
        Map<DimensionId, SetDimensionValue>.unmodifiable(mappedValues));
  }

  final Map<DimensionId, SetDimensionValue> _values;

  Map<DimensionId, SetDimensionValue> get values => _values;

  bool get isCompletionOnly => _values.isEmpty;

  List<DimensionId> get dimensionIds =>
      List<DimensionId>.unmodifiable(_values.keys);

  SetDimensionValue? get load => valueFor(DimensionId.load);

  SetDimensionValue? get reps => valueFor(DimensionId.reps);

  SetDimensionValue? get duration => valueFor(DimensionId.duration);

  SetDimensionValue? get distance => valueFor(DimensionId.distance);

  SetDimensionValue? valueFor(DimensionId id) => _values[id];

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LoggedSet && _dimensionValueMapEquals(other._values, _values);
  }

  @override
  int get hashCode {
    return Object.hashAllUnordered(
      _values.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    );
  }
}

/// A raw user-entered dimension value; [LoggedSet] is the validation boundary.
class SetDimensionValue {
  const SetDimensionValue({
    required this.dimension,
    required this.entered,
    required this.unit,
  });

  final DimensionId dimension;
  final String entered;
  final TrainingUnit unit;

  double get numericValue => double.parse(entered);

  double convertedTo(TrainingUnit targetUnit) {
    return DimensionRegistry.byId(dimension).convertValue(
      entered: entered,
      from: unit,
      to: targetUnit,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SetDimensionValue &&
            other.dimension == dimension &&
            other.entered == entered &&
            other.unit == unit;
  }

  @override
  int get hashCode => Object.hash(dimension, entered, unit);
}

bool _orderedListEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}

String _humanizeEquipmentId(String id) {
  final spaced = id
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .trim();
  if (spaced.isEmpty) {
    return id;
  }
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}

bool _unorderedSetEquals<T>(Set<T> left, Set<T> right) {
  if (left.length != right.length) {
    return false;
  }

  return left.every(right.contains);
}

bool _dimensionValueMapEquals(
  Map<DimensionId, SetDimensionValue> left,
  Map<DimensionId, SetDimensionValue> right,
) {
  if (left.length != right.length) {
    return false;
  }

  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}
