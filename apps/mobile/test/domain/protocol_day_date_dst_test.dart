import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'protocol_day_date_dst_checks.dart' as checks;

/// [ProtocolDayDate] arithmetic across both daylight-saving changes
/// (docs/designs/protocol-schedules-and-reminders.md, file 6), and
/// `TrainingDayDate.addDays`, which Progress Overview walks its dates with
/// (docs/designs/progress-overview.md). A local day is
/// 23 or 25 hours long on a change, so arithmetic on local `DateTime`s
/// repeats a date in autumn and skips one in spring; the arithmetic runs in
/// UTC so it cannot.
///
/// The bug only shows in a zone that changes its clocks, and a test process
/// cannot change its own zone, so the checks in
/// `protocol_day_date_dst_checks.dart` run in this process and again in one
/// child Dart VM per zone ([checks.dstZones]), each started with the `TZ`
/// environment variable set. The children run at once, and each first proves
/// its zone took effect, so a platform that ignored `TZ` would fail here
/// rather than pass without testing anything.
const String _checksFile = 'test/domain/protocol_day_date_dst_checks.dart';

void main() {
  group(
      'ProtocolDayDate across daylight-saving changes '
      '(TZ=${Platform.environment['TZ'] ?? 'unset'})', () {
    for (final check in checks.dstChecks()) {
      test(check.name, () => expect(check.run(), isEmpty));
    }
  });

  group('in each zone with daylight saving', () {
    final runs = <String, Future<ProcessResult>>{};
    setUpAll(() {
      final dart = _dartExecutable();
      final packages = _packageConfig();
      for (final zone in checks.dstZones) {
        runs[zone] = Process.run(
          dart,
          <String>['--packages=$packages', _checksFile],
          environment: <String, String>{
            'TZ': zone,
            checks.childZoneVariable: zone,
          },
          runInShell: Platform.isWindows,
        );
      }
    });

    for (final zone in checks.dstZones) {
      test(
        'TZ=$zone',
        () async {
          final result = await runs[zone]!;
          expect(
            result.exitCode,
            0,
            reason: 'The checks failed under TZ=$zone:\n'
                '${result.stdout}\n${result.stderr}',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}

/// The Dart VM of the SDK this test runs in, so the child needs nothing on
/// PATH. `flutter test` sets `FLUTTER_ROOT` for the test process; failing
/// that, the SDK is found from this process's own executable, the
/// `flutter_tester` in the SDK's `bin/cache/artifacts/engine/<platform>/`.
/// `dart` on PATH is the last resort.
String _dartExecutable() {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final separator = Platform.pathSeparator;
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      [root, 'bin', 'cache', 'dart-sdk', 'bin', name].join(separator),
    [
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path,
      'dart-sdk',
      'bin',
      name,
    ].join(separator),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return 'dart';
}

/// The package config `flutter test` resolved this package with: the nearest
/// `.dart_tool/package_config.json` at or above the package (in a pub
/// workspace it sits at the workspace root).
String _packageConfig() {
  for (Directory directory = Directory.current;; directory = directory.parent) {
    final config = File(
      [directory.path, '.dart_tool', 'package_config.json']
          .join(Platform.pathSeparator),
    );
    if (config.existsSync()) {
      return config.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('No .dart_tool/package_config.json above '
          '${Directory.current.path}.');
    }
  }
}
