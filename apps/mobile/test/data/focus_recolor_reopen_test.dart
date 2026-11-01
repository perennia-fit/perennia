import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

/// Kill-and-reopen for a Focus recolor (docs/designs/progress-overview.md,
/// D6), following `test/features/protocols/protocol_plan_reopen_test.dart`:
/// a database file that is closed and opened again.
///
/// A process kill mid-write can't be staged inside one test process, so the
/// kill is taken as what it leaves on disk. A query interceptor copies the
/// database file and its journal just before the Focus row is updated and
/// just before the commit. Each copy is exactly the disk a kill at that
/// moment leaves behind, and opening it runs SQLite's crash recovery. The
/// color and its Activity Log entry must survive together or not at all.
void main() {
  group('recoloring a Focus across a kill and reopen', () {
    late Directory directory;
    late File file;
    late String focusId;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'prn_focus_recolor_reopen_',
      );
      file = File('${directory.path}/focus.sqlite');
      final database = AppDatabase.openFile(file);
      focusId = await TrainingRepositories(database).focuses.create('Climbing');
      await database.close();
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test(
        'a kill before the update or the commit leaves neither the color '
        'nor its Activity Log entry', () async {
      final killPoints = _KillPointInterceptor(file, directory);
      final database = AppDatabase(
        NativeDatabase(file).interceptWith(killPoints),
      );

      await TrainingRepositories(database)
          .focuses
          .recolor(focusId, colorHex: '#5FB05C');
      await database.close();

      expect(
        killPoints.snapshots.keys.toSet(),
        <String>{'before-update', 'before-commit'},
      );
      for (final entry in killPoints.snapshots.entries) {
        final reopened = AppDatabase.openFile(entry.value);
        try {
          expect(
            await _storedColor(reopened, focusId),
            isNull,
            reason: 'killed ${entry.key}: the color is not stored',
          );
          expect(
            await _recolorEntries(reopened, focusId),
            isEmpty,
            reason: 'killed ${entry.key}: no Activity Log entry survives',
          );
        } finally {
          await reopened.close();
        }
      }
    });

    test('a kill after the commit keeps both the color and its entry',
        () async {
      var database = AppDatabase.openFile(file);
      await TrainingRepositories(database)
          .focuses
          .recolor(focusId, colorHex: '#5FB05C');
      // The process dies straight after the commit returns.
      await database.close();

      database = AppDatabase.openFile(file);
      addTearDown(database.close);

      expect(await _storedColor(database, focusId), '#5FB05C');
      expect(await _recolorEntries(database, focusId), hasLength(1));
    });
  });
}

Future<String?> _storedColor(AppDatabase database, String focusId) async {
  final row = await (database.select(database.focuses)
        ..where((row) => row.id.equals(focusId)))
      .getSingle();
  return row.colorHex;
}

Future<List<ActivityLogEntry>> _recolorEntries(
  AppDatabase database,
  String focusId,
) async {
  final entries =
      await TrainingRepositories(database).activityLog.listEntries();
  return entries
      .where(
        (entry) =>
            entry.entityTable == AppDatabase.focusesTable &&
            entry.entityId == focusId &&
            entry.afterImage?['color_hex'] == '#5FB05C',
      )
      .toList();
}

/// Copies the database file and its journal, as a kill would leave them,
/// just before the Focus row is updated and just before the commit that
/// follows that update.
class _KillPointInterceptor extends QueryInterceptor {
  _KillPointInterceptor(this._file, this._directory);

  final File _file;
  final Directory _directory;
  final snapshots = <String, File>{};
  var _focusUpdates = 0;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('"focuses"')) {
      _focusUpdates += 1;
      _snapshot('before-update');
    }
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    if (_focusUpdates > 0) {
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
