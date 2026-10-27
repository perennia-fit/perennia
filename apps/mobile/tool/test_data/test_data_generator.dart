/// Realistic test data for development: a training history, a body-weight
/// trend, logged meals, and a supplement stack with its Protocols and Doses,
/// written through the same repositories the app's screens use.
///
/// Writing through the repositories, rather than inserting rows, is the point:
/// every row passes the shared validation, gets its Activity Log entry, and
/// lands in exactly the shape the app reads. A generator that inserted rows
/// directly would drift from the schema the moment a repository changed.
///
/// This lives under `tool/`, not `lib/`, so none of it ships in the app. The
/// app has no sample data by design; this is for developers only.
library;

import 'dart:math' as math;

import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

class TestDataOptions {
  const TestDataOptions({
    required this.endDate,
    this.weeks = 12,
    this.seed = 42,
    this.timezone = 'UTC',
    this.includeBodyWeight = true,
    this.includeNutrition = true,
    this.includeProtocols = true,
  }) : assert(weeks > 0);

  /// The last day that can hold data. Usually today, so the Today screen and
  /// "prefill from last session" both have something to show.
  final TrainingDayDate endDate;
  final int weeks;

  /// Same seed, same history. Lets a bug report say "seed 42, 12 weeks".
  final int seed;
  final String timezone;
  final bool includeBodyWeight;
  final bool includeNutrition;

  /// The motivating supplement stack: its Compounds, three Protocols with
  /// one rhythm each, and the Doses logged against them.
  final bool includeProtocols;
}

class TestDataSummary {
  const TestDataSummary({
    required this.workouts,
    required this.sets,
    required this.bodyWeightEntries,
    required this.meals,
    required this.foodEntries,
    this.compounds = 0,
    this.protocols = 0,
    this.doses = 0,
  });

  final int workouts;
  final int sets;
  final int bodyWeightEntries;
  final int meals;
  final int foodEntries;

  /// The Compounds the stack uses, including the seeded Creatine.
  final int compounds;
  final int protocols;
  final int doses;

  @override
  String toString() =>
      '$workouts workouts, $sets sets, $bodyWeightEntries body-weight entries, '
      '$meals meals, $foodEntries food entries, $compounds compounds, '
      '$protocols protocols, $doses doses';
}

/// Platform Exercise Library IDs. They are stable across installs, which is
/// what lets generated history line up with the library a device already has.
abstract final class LibraryExercise {
  static const benchPress = '01910000-0000-7000-8000-000000000102';
  static const barbellSquat = '01910000-0000-7000-8000-000000000101';
  static const deadlift = '01910000-0000-7000-8000-000000000103';
  static const overheadPress = '01910000-0000-7000-8000-000000200687';
  static const pullUp = '01910000-0000-7000-8000-000000000104';
  static const legPress = '01910000-0000-7000-8000-000000200371';
  static const romanianDeadlift = '01910000-0000-7000-8000-000000201750';
  static const dumbbellCurl = '01910000-0000-7000-8000-000000201931';
  static const tricepsPushdown = '01910000-0000-7000-8000-000000201185';
  static const plank = '01910000-0000-7000-8000-000000000105';
  static const running = '01910000-0000-7000-8000-000000000109';
  static const legCurl = '01910000-0000-7000-8000-000000200364';
  static const inclineDumbbellPress = '01910000-0000-7000-8000-000000201277';
  static const hipThrust = '01910000-0000-7000-8000-000000200294';

  static const all = <String>[
    benchPress,
    barbellSquat,
    deadlift,
    overheadPress,
    pullUp,
    legPress,
    romanianDeadlift,
    dumbbellCurl,
    tricepsPushdown,
    plank,
    running,
    legCurl,
    inclineDumbbellPress,
    hipThrust,
  ];
}

Future<TestDataSummary> generateTestData(
  TrainingRepositories repositories,
  TestDataOptions options,
) async {
  await repositories.catalog.ensurePlatformLibrarySeeded();
  final generator = _Generator(repositories, options);
  return generator.run();
}

/// One prescription in the program: an exercise, its working-set shape, and
/// where its load starts and how fast it climbs.
class _Lift {
  const _Lift(
    this.exerciseId, {
    this.sets = 3,
    this.reps = 8,
    this.startLoad = 0,
    this.weeklyIncrement = 0,
    this.loadStep = 2.5,
  });

  final String exerciseId;
  final int sets;
  final int reps;
  final double startLoad;
  final double weeklyIncrement;
  final double loadStep;
}

/// A four-day upper/lower split plus a weekend run: the most common shape of
/// an intermediate lifter's week, and one that exercises every set dimension
/// the app supports (load × reps, reps only, duration, distance + duration).
const _upperA = <_Lift>[
  _Lift(LibraryExercise.benchPress,
      sets: 4, reps: 6, startLoad: 70, weeklyIncrement: 1.25),
  _Lift(LibraryExercise.pullUp, sets: 3, reps: 8),
  _Lift(LibraryExercise.overheadPress,
      sets: 3, reps: 8, startLoad: 40, weeklyIncrement: 0.625),
  _Lift(LibraryExercise.dumbbellCurl,
      sets: 3, reps: 12, startLoad: 12, weeklyIncrement: 0.25, loadStep: 1),
];
const _lowerA = <_Lift>[
  _Lift(LibraryExercise.barbellSquat,
      sets: 4, reps: 5, startLoad: 90, weeklyIncrement: 2.5),
  _Lift(LibraryExercise.romanianDeadlift,
      sets: 3, reps: 8, startLoad: 70, weeklyIncrement: 1.25),
  _Lift(LibraryExercise.legCurl,
      sets: 3, reps: 12, startLoad: 35, weeklyIncrement: 0.5),
  _Lift(LibraryExercise.plank, sets: 3),
];
const _upperB = <_Lift>[
  _Lift(LibraryExercise.inclineDumbbellPress,
      sets: 3, reps: 10, startLoad: 24, weeklyIncrement: 0.5, loadStep: 2),
  _Lift(LibraryExercise.pullUp, sets: 3, reps: 6),
  _Lift(LibraryExercise.tricepsPushdown,
      sets: 3, reps: 12, startLoad: 25, weeklyIncrement: 0.5),
  _Lift(LibraryExercise.dumbbellCurl,
      sets: 2, reps: 15, startLoad: 10, weeklyIncrement: 0.25, loadStep: 1),
];
const _lowerB = <_Lift>[
  _Lift(LibraryExercise.deadlift,
      sets: 3, reps: 5, startLoad: 120, weeklyIncrement: 2.5),
  _Lift(LibraryExercise.legPress,
      sets: 3, reps: 10, startLoad: 160, weeklyIncrement: 5, loadStep: 5),
  _Lift(LibraryExercise.hipThrust,
      sets: 3, reps: 10, startLoad: 80, weeklyIncrement: 2.5),
];

/// Weekday (DateTime.monday = 1) → session. Saturday is the run.
const _schedule = <int, List<_Lift>>{
  DateTime.monday: _upperA,
  DateTime.tuesday: _lowerA,
  DateTime.thursday: _upperB,
  DateTime.friday: _lowerB,
};

class _Food {
  const _Food(this.name, this.kcal, this.protein, this.carbs, this.fat,
      {this.grams = 100, this.isLiquid = false});

  final String name;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  /// The usual portion, in grams (or millilitres when [isLiquid]).
  final double grams;
  final bool isLiquid;
}

/// Per-100 g values, rounded from USDA FoodData Central.
const _breakfasts = <List<_Food>>[
  [
    _Food('Rolled oats', 379, 13.2, 67.7, 6.5, grams: 60),
    _Food('Whole milk', 61, 3.2, 4.8, 3.3, grams: 250, isLiquid: true),
    _Food('Banana', 89, 1.1, 22.8, 0.3, grams: 120),
  ],
  [
    _Food('Eggs, scrambled', 149, 10, 1.6, 11, grams: 150),
    _Food('Wholegrain toast', 247, 13, 41, 3.4, grams: 70),
  ],
  [
    _Food('Greek yoghurt', 97, 9, 3.9, 5, grams: 200),
    _Food('Blueberries', 57, 0.7, 14.5, 0.3, grams: 80),
  ],
];
const _lunches = <List<_Food>>[
  [
    _Food('Chicken breast, grilled', 165, 31, 0, 3.6, grams: 150),
    _Food('White rice, cooked', 130, 2.7, 28.2, 0.3, grams: 200),
    _Food('Broccoli, steamed', 35, 2.4, 7.2, 0.4, grams: 100),
  ],
  [
    _Food('Tuna, canned in water', 116, 25.5, 0, 0.8, grams: 95),
    _Food('Wholegrain wrap', 290, 9, 48, 7, grams: 64),
    _Food('Mixed salad', 20, 1.5, 3.5, 0.2, grams: 80),
  ],
];
const _dinners = <List<_Food>>[
  [
    _Food('Salmon fillet, baked', 206, 22, 0, 12.4, grams: 160),
    _Food('Sweet potato, baked', 90, 2, 20.7, 0.2, grams: 200),
    _Food('Green beans', 31, 1.8, 7, 0.1, grams: 100),
  ],
  [
    _Food('Beef mince, lean, cooked', 217, 26, 0, 12, grams: 150),
    _Food('Pasta, cooked', 158, 5.8, 30.9, 0.9, grams: 220),
    _Food('Tomato sauce', 29, 1.3, 6.5, 0.2, grams: 120),
  ],
];
const _snack = _Food('Whey protein shake', 400, 80, 8, 6, grams: 30);

/// One Compound of the stack and the planned dose its Schedule carries.
/// Amounts are placeholders for exercising the app, not dosing guidance.
class _StackCompound {
  const _StackCompound(
    this.name, {
    required this.amount,
    required this.unit,
    required this.route,
    this.strength,
  });

  final String name;
  final double amount;
  final DoseUnit unit;
  final DoseRoute route;
  final String? strength;

  String get amountEntered =>
      amount == amount.roundToDouble() ? amount.toInt().toString() : '$amount';
}

const _trt = _StackCompound(
  'TRT',
  amount: 0.1,
  unit: DoseUnit.milliliter,
  route: DoseRoute.subcutaneous,
  strength: '200 mg/mL',
);
const _ageMate = _StackCompound(
  'AgeMate',
  amount: 1,
  unit: DoseUnit.capsule,
  route: DoseRoute.oral,
);
const _mnem = _StackCompound(
  'MNEM',
  amount: 1,
  unit: DoseUnit.capsule,
  route: DoseRoute.oral,
);

/// Creatine is one of the app's seeded Compounds, so the stack reuses the
/// seeded row (stable id) rather than adding a second "Creatine".
const _creatine = _StackCompound(
  'Creatine',
  amount: 5,
  unit: DoseUnit.gram,
  route: DoseRoute.oral,
);
const _ghkCu = _StackCompound(
  'GHK-Cu',
  amount: 1,
  unit: DoseUnit.milligram,
  route: DoseRoute.subcutaneous,
);
const _bpc157 = _StackCompound(
  'BPC-157',
  amount: 250,
  unit: DoseUnit.microgram,
  route: DoseRoute.subcutaneous,
);
const _seededCreatineId = '019200ff-0000-7000-8000-000000000001';

class _Generator {
  _Generator(this._repositories, this._options)
      : _random = math.Random(_options.seed);

  final TrainingRepositories _repositories;
  final TestDataOptions _options;
  final math.Random _random;

  static const _actor = 'test_data_generator';

  int _workouts = 0;
  int _sets = 0;
  int _bodyWeightEntries = 0;
  int _meals = 0;
  int _foodEntries = 0;
  int _compounds = 0;
  int _protocols = 0;
  int _doses = 0;
  final _foodIds = <String, String>{};

  Future<TestDataSummary> run() async {
    final days = _options.weeks * 7;
    final start = _options.endDate.addDays(-(days - 1));

    String? bodyWeightId;
    if (_options.includeBodyWeight) {
      await _repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
        actor: _actor,
      );
      bodyWeightId = (await _repositories.measurements.listEnabled())
          .singleWhere(
            (measurement) =>
                measurement.name == MeasurementRepository.defaultBodyWeightName,
          )
          .id;
    }
    if (_options.includeNutrition) {
      await _repositories.nutrition.ensureDefaultMealTypes(actor: _actor);
    }

    for (var dayIndex = 0; dayIndex < days; dayIndex += 1) {
      final day = start.addDays(dayIndex);
      final weekday = day.toLocalDateTime().weekday;
      // Week 1 is week 0 here; every fourth week is a deload.
      final week = dayIndex ~/ 7;

      final session = _schedule[weekday];
      // About one planned session in twelve gets skipped, as in real life.
      if (session != null && _random.nextDouble() > 0.08) {
        await _logLiftingSession(day, session, week);
      } else if (weekday == DateTime.saturday && _random.nextDouble() > 0.15) {
        await _logRun(day, week);
      }

      if (bodyWeightId != null && _random.nextDouble() < 0.75) {
        await _logBodyWeight(bodyWeightId, day, dayIndex);
      }
      if (_options.includeNutrition && _random.nextDouble() < 0.85) {
        await _logNutritionDay(day);
      }
    }

    if (_options.includeProtocols) {
      await _logProtocolStack(start);
    }

    return TestDataSummary(
      workouts: _workouts,
      sets: _sets,
      bodyWeightEntries: _bodyWeightEntries,
      meals: _meals,
      foodEntries: _foodEntries,
      compounds: _compounds,
      protocols: _protocols,
      doses: _doses,
    );
  }

  /// The motivating stack, one Protocol per rhythm:
  /// - "Daily", from the range start: TRT, AgeMate and MNEM at 09:00, and
  ///   creatine at 17:00;
  /// - "Skin": GHK-Cu at 21:00 on a 60-days-on, 30-off cycle anchored (and
  ///   starting) 60 days before the range end;
  /// - "Shoulder": BPC-157 at 21:00 from 10 days before the range end, for
  ///   20 doses (its end date comes from the "N doses" helper).
  ///
  /// Then the Doses: every planned dose in the range, near its planned time,
  /// with one day in six left unlogged. A Dose whose time is still ahead of
  /// the real clock is not logged, so today's later planned doses stay
  /// unlogged.
  Future<void> _logProtocolStack(TrainingDayDate rangeStart) async {
    final protocols = _repositories.protocols;
    await protocols.ensureOtcLibrarySeeded(actor: _actor);
    final ids = <_StackCompound, String>{};
    for (final compound in const [_trt, _ageMate, _mnem, _ghkCu, _bpc157]) {
      final result = await protocols.createCompound(
        CompoundDraft(
          name: compound.name,
          defaultUnit: compound.unit,
          defaultRoute: compound.route,
          strength: CompoundStrength.tryParse(compound.strength),
        ),
        actor: _actor,
      );
      ids[compound] = result.compoundId;
    }
    ids[_creatine] = _seededCreatineId;
    final catalogue = {
      for (final record in await protocols.listCompounds()) record.id: record,
    };
    final compounds = <_StackCompound, CompoundRecord>{
      for (final MapEntry(key: compound, value: id) in ids.entries)
        compound: catalogue[id]!,
    };
    _compounds = compounds.length;

    final start = _protocolDay(rangeStart);
    final end = _protocolDay(_options.endDate);
    ScheduleDraft at(_StackCompound compound, String time) => ScheduleDraft(
          rule: TimedScheduleRule(
            days: const DailyScheduleDays(),
            times: <String>[time],
          ),
          doseAmountValue: compound.amount,
          doseAmountEntered: compound.amountEntered,
          doseUnit: compound.unit,
          route: compound.route,
        );

    await _createProtocol(
      ProtocolDraft(
        name: 'Daily',
        startLocalDate: start,
        compoundIds: [
          for (final compound in const [_trt, _ageMate, _mnem, _creatine])
            compounds[compound]!.id,
        ],
        schedulesByCompoundId: {
          compounds[_trt]!.id: at(_trt, '09:00'),
          compounds[_ageMate]!.id: at(_ageMate, '09:00'),
          compounds[_mnem]!.id: at(_mnem, '09:00'),
          compounds[_creatine]!.id: at(_creatine, '17:00'),
        },
      ),
    );

    final skinStart = end.addDays(-60);
    await _createProtocol(
      ProtocolDraft(
        name: 'Skin',
        startLocalDate: skinStart,
        period: ProtocolPeriod(
          cycle: ProtocolCycle(
            onDays: 60,
            offDays: 30,
            anchor: skinStart,
            anchorIsDefault: true,
          ),
        ),
        compoundIds: [compounds[_ghkCu]!.id],
        schedulesByCompoundId: {compounds[_ghkCu]!.id: at(_ghkCu, '21:00')},
      ),
    );

    final shoulderStart = end.addDays(-10);
    final shoulderSchedule = at(_bpc157, '21:00');
    await _createProtocol(
      ProtocolDraft(
        name: 'Shoulder',
        startLocalDate: shoulderStart,
        endLocalDate: endDateForDoseCount(
          startLocalDate: shoulderStart,
          rule: shoulderSchedule.rule,
          doseCount: 20,
        ),
        compoundIds: [compounds[_bpc157]!.id],
        schedulesByCompoundId: {compounds[_bpc157]!.id: shoulderSchedule},
      ),
    );

    await _logPlannedDoses(start, end, compounds.values);
  }

  Future<void> _createProtocol(ProtocolDraft draft) async {
    await _repositories.protocols.createProtocol(draft, actor: _actor);
    _protocols += 1;
  }

  Future<void> _logPlannedDoses(
    ProtocolDayDate start,
    ProtocolDayDate end,
    Iterable<CompoundRecord> compounds,
  ) async {
    final compoundsById = {
      for (final compound in compounds) compound.id: compound,
    };
    final protocols = await _repositories.protocols.listProtocols();
    final protocolsById = {
      for (final protocol in protocols) protocol.id: protocol,
    };
    final days = planDays(protocols.map(_planProtocolOf), start, end);
    final now = DateTime.now();
    final drafts = <DoseSnapshotDraft>[];
    ProtocolDayDate? draftsDay;

    Future<void> flush() async {
      if (drafts.isEmpty) {
        return;
      }
      // One batch per day, as "Log all planned" writes it.
      await _repositories.protocols.logDoses(
        List<DoseSnapshotDraft>.of(drafts),
        actor: _actor,
      );
      _doses += drafts.length;
      drafts.clear();
    }

    for (final day in days) {
      if (day.localDate != draftsDay) {
        await flush();
        draftsDay = day.localDate;
      }
      // One day in six is left unlogged, as real logs have gaps.
      if (day.localDate.daysBetween(start) % 6 == 5) {
        continue;
      }
      final compound = compoundsById[day.compoundId]!;
      final protocol = protocolsById[day.protocolId]!;
      for (final planned in day.planned) {
        final time = planLocalTimeMinutes(planned.localTime!);
        // Within 15 minutes either side of the planned time, as people take
        // a dose around its time rather than on the minute.
        final minutes = time + _protocolRandom.nextInt(31) - 15;
        final tookAt = DateTime(
          day.localDate.year,
          day.localDate.month,
          day.localDate.day,
        ).add(Duration(minutes: minutes.clamp(0, 24 * 60 - 1)));
        if (tookAt.isAfter(now)) {
          continue;
        }
        drafts.add(
          DoseSnapshotDraft.fromCompound(
            compound: compound,
            amountValue: planned.amount.amountValue!,
            amountEntered: planned.amount.amountEntered!,
            unit: planned.amount.unit!,
            route: planned.amount.route!,
            tookAt: tookAt,
            localDate: day.localDate,
            protocol: ProtocolOptionRecord(
              id: protocol.id,
              name: protocol.name,
            ),
          ),
        );
      }
    }
    await flush();
  }

  /// A separate stream for the Dose times, so adding the stack leaves the
  /// training, body-weight and nutrition history of a seed unchanged.
  late final math.Random _protocolRandom = math.Random(_options.seed + 1);

  ProtocolDayDate _protocolDay(TrainingDayDate day) =>
      ProtocolDayDate(year: day.year, month: day.month, day: day.day);

  Future<void> _logLiftingSession(
    TrainingDayDate day,
    List<_Lift> session,
    int week,
  ) async {
    final deload = week % 4 == 3;
    var clock = _at(day, hour: 6, minute: 30 + _random.nextInt(60));
    final workoutId = await _repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: clock,
        timezone: _options.timezone,
        localDate: day,
        comment: deload ? 'Deload week' : null,
      ),
      actor: _actor,
    );
    _workouts += 1;

    for (final lift in session) {
      await _repositories.workoutExercises.create(
        WorkoutExerciseDraft(workoutId: workoutId, exerciseId: lift.exerciseId),
        actor: _actor,
      );
      for (var position = 0; position < lift.sets; position += 1) {
        clock = clock.add(Duration(seconds: 90 + _random.nextInt(90)));
        final isLastSet = position == lift.sets - 1;
        await _repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutId,
            exerciseId: lift.exerciseId,
            position: position,
            values: _liftValues(lift, week, deload: deload, lastSet: isLastSet),
            performedAt: clock,
            isCompleted: true,
            comment: isLastSet && _random.nextDouble() < 0.05
                ? 'Felt strong today'
                : null,
          ),
          actor: _actor,
        );
        _sets += 1;
      }
    }

    await _repositories.workoutSessions.updateEndedAt(
      workoutId,
      endedAt: clock.add(const Duration(minutes: 5)),
      actor: _actor,
    );
  }

  LoggedSet _liftValues(
    _Lift lift,
    int week, {
    required bool deload,
    required bool lastSet,
  }) {
    if (lift.exerciseId == LibraryExercise.plank) {
      final seconds = 45 + week * 5 + _random.nextInt(10);
      return LoggedSet.fromValues(<SetDimensionValue>[
        _value(DimensionId.duration, seconds, TrainingUnit.second),
      ]);
    }

    // The final set sometimes falls a rep or two short: the honest shape of a
    // working set, and what gives PR detection something to decide.
    final missed = lastSet && !deload && _random.nextDouble() < 0.3
        ? 1 + _random.nextInt(2)
        : 0;
    final reps = math.max(1, lift.reps - missed);

    if (lift.startLoad == 0) {
      // Bodyweight: progress by adding reps instead of load.
      final bodyweightReps = reps + week ~/ 3 - missed;
      return LoggedSet.fromValues(<SetDimensionValue>[
        _value(DimensionId.reps, math.max(1, bodyweightReps),
            TrainingUnit.repetition),
      ]);
    }

    final raw = lift.startLoad + lift.weeklyIncrement * week;
    final load = _roundTo(deload ? raw * 0.8 : raw, lift.loadStep);
    return LoggedSet.fromValues(<SetDimensionValue>[
      _value(DimensionId.load, load, TrainingUnit.kilogram),
      _value(DimensionId.reps, reps, TrainingUnit.repetition),
    ]);
  }

  Future<void> _logRun(TrainingDayDate day, int week) async {
    final startedAt = _at(day, hour: 8, minute: _random.nextInt(45));
    final workoutId = await _repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: startedAt,
        timezone: _options.timezone,
        localDate: day,
      ),
      actor: _actor,
    );
    _workouts += 1;
    await _repositories.workoutExercises.create(
      WorkoutExerciseDraft(
        workoutId: workoutId,
        exerciseId: LibraryExercise.running,
      ),
      actor: _actor,
    );

    // 5 km building toward 8 km, at a pace that improves from 6:00 to ~5:30.
    final kilometres = math.min(8.0, 5 + week * 0.25);
    final secondsPerKm = math.max(330, 360 - week * 2) + _random.nextInt(15);
    final duration = (kilometres * secondsPerKm).round();
    await _repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: LibraryExercise.running,
        position: 0,
        values: LoggedSet.fromValues(<SetDimensionValue>[
          _value(DimensionId.distance, kilometres, TrainingUnit.kilometer),
          _value(DimensionId.duration, duration, TrainingUnit.second),
        ]),
        performedAt: startedAt.add(Duration(seconds: duration)),
        isCompleted: true,
      ),
      actor: _actor,
    );
    _sets += 1;
    await _repositories.workoutSessions.updateEndedAt(
      workoutId,
      endedAt: startedAt.add(Duration(seconds: duration + 300)),
      actor: _actor,
    );
  }

  Future<void> _logBodyWeight(
    String measurementId,
    TrainingDayDate day,
    int dayIndex,
  ) async {
    // A slow cut: about 0.35 kg a week down from 84 kg, with daily water noise.
    final trend = 84 - dayIndex * 0.05;
    final noise = (_random.nextDouble() - 0.5) * 1.2;
    final kilograms = (trend + noise).toStringAsFixed(1);
    await _repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: measurementId,
        valueEntered: kilograms,
        measuredAt: _at(day, hour: 6, minute: 10),
      ),
      actor: _actor,
    );
    _bodyWeightEntries += 1;
  }

  Future<void> _logNutritionDay(TrainingDayDate day) async {
    await _logMeal(day, 'meal-type-breakfast', 7,
        _breakfasts[_random.nextInt(_breakfasts.length)]);
    await _logMeal(
        day, 'meal-type-lunch', 12, _lunches[_random.nextInt(_lunches.length)]);
    await _logMeal(day, 'meal-type-dinner', 19,
        _dinners[_random.nextInt(_dinners.length)]);
    if (_random.nextDouble() < 0.6) {
      await _logMeal(day, 'meal-type-snack', 16, const [_snack]);
    }
  }

  Future<void> _logMeal(
    TrainingDayDate day,
    String mealTypeId,
    int hour,
    List<_Food> foods,
  ) async {
    final mealId = await _repositories.nutrition.createMeal(
      MealDraft(
        mealType: mealTypeId,
        startedAt: _at(day, hour: hour, minute: _random.nextInt(40)),
        timezone: _options.timezone,
        localDate: NutritionDayDate(
          year: day.year,
          month: day.month,
          day: day.day,
        ),
      ),
      actor: _actor,
    );
    _meals += 1;

    for (final food in foods) {
      // Portions wobble ±15% around the usual amount, as weighed food does.
      final amount =
          (food.grams * (0.85 + _random.nextDouble() * 0.3)).roundToDouble();
      await _repositories.nutrition.logFoodEntry(
        entry: FoodEntryDraft(
          mealId: mealId,
          foodId: await _foodId(food),
          portion: Portion(
            value: amount,
            entered: amount.toStringAsFixed(0),
            unit: food.isLiquid ? PortionUnit.milliliter : PortionUnit.gram,
          ),
        ),
        actor: _actor,
      );
      _foodEntries += 1;
    }
  }

  /// User Foods are created once, on first use, like a person building up
  /// their own food list.
  Future<String> _foodId(_Food food) async {
    final existing = _foodIds[food.name];
    if (existing != null) {
      return existing;
    }
    final id = await _repositories.nutrition.createUserFood(
      UserFoodDraft(
        name: food.name,
        nutrientsPer100: NutrientVector.energyAndMacros(
          energy: _nutrient(food.kcal, NutrientUnit.kilocalorie),
          protein: _nutrient(food.protein, NutrientUnit.gram),
          carbohydrate: _nutrient(food.carbs, NutrientUnit.gram),
          fat: _nutrient(food.fat, NutrientUnit.gram),
        ),
        isLiquid: food.isLiquid,
      ),
      actor: _actor,
    );
    _foodIds[food.name] = id;
    return id;
  }

  DateTime _at(TrainingDayDate day, {required int hour, required int minute}) {
    return DateTime.utc(day.year, day.month, day.day, hour, minute);
  }
}

SetDimensionValue _value(DimensionId dimension, num value, TrainingUnit unit) {
  final entered =
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
  return SetDimensionValue(dimension: dimension, entered: entered, unit: unit);
}

NutrientAmount _nutrient(double value, NutrientUnit unit) {
  return NutrientAmount.complete(
    value: value,
    entered: value.toString(),
    unit: unit,
  );
}

double _roundTo(double value, double step) => (value / step).round() * step;

/// [protocol] as the plan core reads it. Every member the generator writes
/// has exactly one Schedule Version, so its current version is its history.
PlanProtocol _planProtocolOf(ProtocolRecord protocol) {
  return PlanProtocol(
    protocolId: protocol.id,
    startLocalDate: protocol.startLocalDate,
    endLocalDate: protocol.endLocalDate,
    period: protocol.period,
    remindersEnabled: protocol.remindersEnabled,
    members: [
      for (final member in protocol.members)
        PlanMember(
          memberId: member.id,
          compoundId: member.compoundId,
          versions: [
            if (member.currentVersion case final version?)
              ScheduleVersion(
                id: version.id,
                effectiveFrom: version.effectiveFrom,
                rule: version.rule,
                amount: version.amount,
              ),
          ],
        ),
    ],
  );
}
