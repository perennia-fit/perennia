import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/data/infra/` is the repositories' write plumbing (write contexts,
/// id minting, Activity Log appends). Features write through repositories,
/// never around them, or their writes would skip validation and the batch
/// rules the repositories own.
void main() {
  test('nothing under lib/features/ imports lib/data/infra/', () {
    final directive = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final violations = <String>[];
    final features = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in features) {
      for (final match in directive.allMatches(file.readAsStringSync())) {
        final uri = match.group(1)!;
        final resolved = uri.startsWith('package:')
            ? uri
            : file.parent.uri.resolve(uri).path;
        if (resolved.contains('data/infra/')) {
          violations.add('${file.path}: $uri');
        }
      }
    }

    expect(features, isNotEmpty);
    expect(violations, isEmpty);
  });
}
