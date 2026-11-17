import 'dart:io';

/// Regenerates the schema migration test helpers from the committed Drift
/// schema snapshots, and fails when `AppDatabase.schemaVersion` has no
/// snapshot.
///
///   dart run tool/drift_schema_snapshots.dart          # regenerate
///   dart run tool/drift_schema_snapshots.dart --check  # CI: also fail when
///                                                      # the output changed
///
/// Run from apps/mobile. A snapshot itself is written by
/// `dart run drift_dev schema dump lib/data/local/app_database.dart
/// drift_schemas/app_database/`; docs/releasing.md says when.
const _databasePath = 'lib/data/local/app_database.dart';
const _snapshotDir = 'drift_schemas/app_database';
const _helperDir = 'test/generated_migrations/app_database';

final _schemaVersionPattern = RegExp(r'int get schemaVersion => (\d+);');
final _snapshotPattern = RegExp(r'^drift_schema_v(\d+)\.json$');

Future<void> main(List<String> args) async {
  final check = args.contains('--check');

  final match = _schemaVersionPattern.firstMatch(
    File(_databasePath).readAsStringSync(),
  );
  if (match == null) {
    _fail('Could not find schemaVersion in $_databasePath.');
  }
  final schemaVersion = int.parse(match.group(1)!);

  final snapshotVersions = <int>[
    for (final entity in Directory(_snapshotDir).listSync())
      if (_snapshotPattern.firstMatch(entity.uri.pathSegments.last)
          case final snapshot?)
        int.parse(snapshot.group(1)!),
  ]..sort();
  if (!snapshotVersions.contains(schemaVersion)) {
    _fail(
      'AppDatabase.schemaVersion is $schemaVersion, but $_snapshotDir has no '
      'drift_schema_v$schemaVersion.json. Dump it with:\n'
      '  dart run drift_dev schema dump $_databasePath $_snapshotDir/\n'
      'then run this script again (docs/releasing.md).',
    );
  }
  if (snapshotVersions.last > schemaVersion) {
    _fail(
      '$_snapshotDir has a snapshot for v${snapshotVersions.last}, newer than '
      'AppDatabase.schemaVersion $schemaVersion.',
    );
  }

  Directory(_helperDir).createSync(recursive: true);
  final generate = await Process.run(
    'dart',
    [
      'run',
      'drift_dev',
      'schema',
      'generate',
      '$_snapshotDir/',
      '$_helperDir/'
    ],
    runInShell: Platform.isWindows,
  );
  stdout.write(generate.stdout);
  stderr.write(generate.stderr);
  if (generate.exitCode != 0) exit(generate.exitCode);

  for (final version in snapshotVersions) {
    _renameTableDslClash(File('$_helperDir/schema_v$version.dart'));
  }

  if (check) {
    final status = await Process.run(
      'git',
      [
        'status',
        '--porcelain',
        '--untracked-files=all',
        '--',
        _snapshotDir,
        _helperDir,
      ],
    );
    // Like the gate's `git diff --exit-code` steps, a staged change passes:
    // only unstaged edits and untracked files mean regenerated output that
    // isn't in the change yet.
    final dirty = [
      for (final line in (status.stdout as String).split('\n'))
        if (line.length > 1 && line[1] != ' ') line,
    ].join('\n');
    if (status.exitCode != 0 || dirty.isNotEmpty) {
      _fail(
        'Drift schema snapshots or their test helpers are stale or not added:\n'
        '$dirty${status.stderr}',
      );
    }
  }
}

/// drift_dev names a column's field after its SQL name, ignoring the snapshot's
/// getter_name. The `monitoring_series_cache.blob` column then declares a field
/// `blob`, which clashes with `Table.blob()` and stops the helper compiling.
/// Rename it to the app's own getter, `blobData`.
void _renameTableDslClash(File file) {
  final field = RegExp(r'(late final GeneratedColumn<[\w.]*Uint8List> )blob =');
  const listEntry = '        blob,\n';
  final source = file.readAsStringSync();
  if (!field.hasMatch(source)) return;
  if (!source.contains(listEntry)) {
    _fail('${file.path}: found the blob column but not its \$columns entry.');
  }
  file.writeAsStringSync(
    source
        .replaceFirstMapped(field, (match) => '${match[1]}blobData =')
        .replaceFirst(listEntry, '        blobData,\n'),
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
