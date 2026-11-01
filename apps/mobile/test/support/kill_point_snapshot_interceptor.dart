import 'dart:io';

import 'package:drift/drift.dart';

/// A query interceptor that copies a database file and its journal, as a
/// process kill would leave them, at the moments a subclass picks.
///
/// A kill mid-write can't be staged inside one test process, so a
/// kill-and-reopen test takes the kill as what it leaves on disk. A subclass
/// overrides the hook it watches (an insert, an update, the commit) and calls
/// [snapshot] there. Each copy is exactly the disk a kill at that moment
/// leaves behind, and opening it runs SQLite's crash recovery.
abstract class KillPointSnapshotInterceptor extends QueryInterceptor {
  KillPointSnapshotInterceptor(this._file, this._directory);

  final File _file;
  final Directory _directory;

  /// Each kill point reached, by name, and the database file copied there.
  final snapshots = <String, File>{};

  void snapshot(String name) {
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
