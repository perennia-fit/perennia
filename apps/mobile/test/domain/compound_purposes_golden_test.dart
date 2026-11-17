import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/protocols/compound_purposes.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion` and its schema's constant
/// (packages/golden-vectors/vectors/README.md).
const int _schemaVersion = 1;

/// The shared golden vector for the Compound Purposes core
/// (docs/designs/compound-purposes.md, D3 and D8). The agent API runs the same
/// file (`apps/server/test/compound-purposes.golden.test.mjs`), so the app and
/// an Agent agree on the starter set and on which names are allowed.
void main() {
  final vector = jsonDecode(
    _vectorFile('m40-compound-purposes.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the compound-purposes vector header matches this runner', () {
    expect(vector['name'], 'm40-compound-purposes');
    expect(vector['domain'], 'compound-purposes');
    expect(vector['schemaVersion'], _schemaVersion);
    expect(vector['schema'], 'm40-compound-purposes.schema.json');
    expect(vector['cases'], isNotEmpty);
  });

  group('the Compound Purposes core matches the shared golden vectors', () {
    for (final rawCase in vector['cases']! as List<Object?>) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final name = vectorCase['name']! as String;
      final function = vectorCase['function']! as String;
      test('$function: $name', () {
        final input = vectorCase['input']! as Map<String, Object?>;
        expect(_run(function, input), vectorCase['expected'], reason: name);
      });
    }
  });

  // Not vector cases: the seed tag table is Dart only (D8).
  test('the seed tags name only starter Purposes', () {
    final starterIds = starterPurposes.map((purpose) => purpose.id).toSet();
    expect(seedCompoundPurposeIds, hasLength(6));
    for (final purposeIds in seedCompoundPurposeIds.values) {
      expect(starterIds.containsAll(purposeIds), isTrue);
    }
  });
}

/// One entry per `function` the vector file uses. A case naming anything else
/// fails loudly rather than being skipped.
Object? _run(String function, Map<String, Object?> input) {
  return switch (function) {
    'starterPurposes' => <Map<String, Object?>>[
        for (final purpose in starterPurposes)
          <String, Object?>{
            'id': purpose.id,
            'name': purpose.name,
            'sortOrder': purpose.sortOrder,
          },
      ],
    'validatePurposeName' => _validateName(
        input['name']! as String,
        (input['activeNamesExcludingSelf']! as List<Object?>).cast<String>(),
      ),
    'normalizePurposeIds' => normalizePurposeIds(
        (input['ids']! as List<Object?>).cast<String>(),
      ),
    _ => throw ArgumentError.value(function, 'function', 'Unknown function.'),
  };
}

Map<String, Object?> _validateName(String name, List<String> activeNames) {
  try {
    return <String, Object?>{
      'accepted': validatePurposeName(name, activeNames),
    };
  } on PurposeNameException catch (error) {
    return <String, Object?>{'rejected': error.code};
  }
}

File _vectorFile(String name) {
  final relative = 'packages/golden-vectors/vectors/$name';
  // Run from the repo root or from apps/mobile.
  final fromRoot = File(relative);
  return fromRoot.existsSync() ? fromRoot : File('../../$relative');
}
