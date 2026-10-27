import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';

/// Kill-and-reopen for "Log all planned" (D6), following the repository's
/// standing scenario (`test/data/plan_tree_reopen_test.dart`): a database
/// file that is closed and opened again.
///
/// A process kill mid-write can't be staged inside one test process, so the
/// kill is taken as what it leaves on disk. A query interceptor copies the
/// database file and its journal at two moments of "Log all planned": just
/// before the Batch's second Dose is inserted, and just before the commit.
/// Each copy is exactly the disk a kill at that moment leaves behind, and
/// opening it runs SQLite's crash recovery. Had the Doses been written in
/// more than one transaction, the first Dose would already be committed in
/// both copies.
void main() {
  group('Log all planned across a kill and reopen', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'prn_protocol_plan_reopen_',
      );
      file = File('${directory.path}/plan.sqlite');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'a kill before the commit leaves no part of the Batch, and the '
      'Planned list still reads Pending',
      () async {
        await _seedDailyStack(file);
        final killPoints = _KillPointInterceptor(file, directory);
        final database = AppDatabase(
          NativeDatabase(file).interceptWith(killPoints),
        );
        final container = _container(database);
        final activityBefore = await _activityLogCount(database);

        final results = await container
            .read(protocolDayControllerProvider.notifier)
            .logAllPlanned();
        container.dispose();
        await database.close();

        // The live write itself went through: two Doses, one Batch.
        expect(results, hasLength(2));
        expect(results.map((result) => result.batchId).toSet(), hasLength(1));
        // Both kill points were reached.
        expect(
          killPoints.snapshots.keys.toSet(),
          <String>{'before-second-dose', 'before-commit'},
        );

        for (final entry in killPoints.snapshots.entries) {
          final reopened = AppDatabase.openFile(entry.value);
          final repositories = TrainingRepositories(reopened);
          try {
            expect(
              await reopened.select(reopened.doses).get(),
              isEmpty,
              reason: 'killed ${entry.key}: no Dose of the Batch survives',
            );
            expect(
              await _activityLogCount(reopened),
              activityBefore,
              reason: 'killed ${entry.key}: no Activity Log entry survives',
            );
            final planned = await repositories.protocolPlan
                .watchPlannedDay(_today, today: _today)
                .first;
            expect(
              _labels(planned),
              <String, PlannedRowStatus>{
                'TRT': PlannedRowStatus.pending,
                'AgeMate': PlannedRowStatus.pending,
                'Creatine': PlannedRowStatus.pending,
              },
              reason: 'killed ${entry.key}',
            );
          } finally {
            await reopened.close();
          }
        }
      },
    );

    test(
      'a kill after the commit keeps the whole Batch, and the Planned list '
      'reads Logged',
      () async {
        await _seedDailyStack(file);
        var database = AppDatabase.openFile(file);
        final container = _container(database);

        final results = await container
            .read(protocolDayControllerProvider.notifier)
            .logAllPlanned();
        container.dispose();
        // The process dies straight after the commit returns.
        await database.close();

        database = AppDatabase.openFile(file);
        addTearDown(database.close);
        final repositories = TrainingRepositories(database);

        final doses = await database.select(database.doses).get();
        expect(doses.map((dose) => dose.id).toSet(), {
          for (final result in results) result.doseId,
        });
        expect(
          doses.map((dose) => dose.compoundName).toSet(),
          <String>{'TRT', 'AgeMate'},
        );
        // Each Dose carries its row's planned amount and Protocol tag.
        for (final dose in doses) {
          expect(dose.protocolName, 'Daily');
          expect(dose.amountEntered, dose.compoundName == 'TRT' ? '0.5' : '1');
          expect(dose.tookAt.isAtSameMomentAs(_now), isTrue);
        }
        final batchEntries = (await repositories.activityLog.listEntries())
            .where((entry) => entry.batchId == results.first.batchId);
        expect(batchEntries, hasLength(2));

        final planned = await repositories.protocolPlan
            .watchPlannedDay(_today, today: _today)
            .first;
        expect(_labels(planned), <String, PlannedRowStatus>{
          'TRT': PlannedRowStatus.logged,
          'AgeMate': PlannedRowStatus.logged,
          'Creatine': PlannedRowStatus.pending,
        });
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  });
}

/// CUJ 1 at 09:30: TRT and AgeMate are due at 09:00, creatine at 17:00.
final DateTime _now = DateTime(2026, 10, 27, 9, 30);
final ProtocolDayDate _today = ProtocolDayDate.fromDateTime(_now);

ProviderContainer _container(AppDatabase database) {
  return ProviderContainer(
    overrides: [
      trainingRepositoriesProvider.overrideWith(
        (ref) => TrainingRepositories(database),
      ),
      protocolsClockProvider.overrideWithValue(() => _now),
    ],
  );
}

/// Writes CUJ 1's "Daily" Protocol, then closes the file, so each test
/// starts from a committed plan.
Future<void> _seedDailyStack(File file) async {
  final database = AppDatabase.openFile(file);
  final repositories = TrainingRepositories(database);
  Future<String> compound(String name, DoseUnit unit, DoseRoute route) async {
    final result = await repositories.protocols.createCompound(
      CompoundDraft(name: name, defaultUnit: unit, defaultRoute: route),
    );
    return result.compoundId;
  }

  final trt = await compound(
    'TRT',
    DoseUnit.milliliter,
    DoseRoute.intramuscular,
  );
  final ageMate = await compound(
    'AgeMate',
    DoseUnit.capsule,
    DoseRoute.oral,
  );
  final creatine = await compound('Creatine', DoseUnit.gram, DoseRoute.oral);
  ScheduleDraft dailyAt(
    String time,
    String amount,
    DoseUnit unit,
    DoseRoute route,
  ) {
    return ScheduleDraft(
      rule: TimedScheduleRule(
        days: const DailyScheduleDays(),
        times: <String>[time],
      ),
      doseAmountValue: double.parse(amount),
      doseAmountEntered: amount,
      doseUnit: unit,
      route: route,
    );
  }

  await repositories.protocols.createProtocol(
    ProtocolDraft(
      name: 'Daily',
      startLocalDate: _today,
      compoundIds: <String>[trt, ageMate, creatine],
      remindersEnabled: true,
      schedulesByCompoundId: <String, ScheduleDraft?>{
        trt: dailyAt(
            '09:00', '0.5', DoseUnit.milliliter, DoseRoute.intramuscular),
        ageMate: dailyAt('09:00', '1', DoseUnit.capsule, DoseRoute.oral),
        creatine: dailyAt('17:00', '5', DoseUnit.gram, DoseRoute.oral),
      },
    ),
    today: _today,
  );
  await database.close();
}

Future<int> _activityLogCount(AppDatabase database) async {
  final rows = await database.select(database.activityLog).get();
  return rows.length;
}

Map<String, PlannedRowStatus> _labels(PlannedDay planned) {
  return <String, PlannedRowStatus>{
    for (final group in planned.groups)
      for (final row in group.rows)
        planned.compounds[row.compoundId]!.name: row.status,
  };
}

/// Copies the database file and its journal, as a kill would leave them, at
/// two moments of "Log all planned": just before the Batch's second Dose is
/// inserted, and just before the last commit that follows a Dose insert.
/// Had the Doses been written in separate transactions, the first Dose would
/// already be committed at both moments, and its copy would hold it.
class _KillPointInterceptor extends QueryInterceptor {
  _KillPointInterceptor(this._file, this._directory);

  final File _file;
  final Directory _directory;
  final snapshots = <String, File>{};
  var _doseInserts = 0;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('"doses"')) {
      _doseInserts += 1;
      if (_doseInserts == 2) {
        _snapshot('before-second-dose');
      }
    }
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    if (_doseInserts > 0) {
      _snapshot('before-commit');
    }
    return super.commitTransaction(inner);
  }

  void _snapshot(String name) {
    final target = Directory('${_directory.path}/$name');
    if (target.existsSync()) {
      target.deleteSync(recursive: true);
    }
    target.createSync();
    final base = _file.uri.pathSegments.last;
    for (final entity in _directory.listSync()) {
      final entityName = entity.uri.pathSegments.last;
      if (entity is File && entityName.startsWith(base)) {
        entity.copySync('${target.path}/$entityName');
      }
    }
    snapshots[name] = File('${target.path}/$base');
  }
}
