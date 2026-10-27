import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// The shared golden vector for turning a scanned or typed code into the
/// Open Food Facts barcodes to try (docs/designs/open-food-facts.md, "Search
/// and barcode rules"). The agent API's `barcodeCandidates` runs the same file
/// (`apps/server/test/barcode-candidates.golden.test.mjs`), so the app and an
/// agent find the same product for the same code.
void main() {
  test('barcode candidates match the shared golden vectors', () {
    final vector = jsonDecode(
      _vectorFile('m36-barcode-candidates.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(vector['domain'], 'barcode-candidates');

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);

    for (final rawCase in cases) {
      final vectorCase = rawCase! as Map<String, Object?>;
      expect(
        barcodeCandidates(vectorCase['input']! as String),
        (vectorCase['expected']! as List<Object?>).cast<String>(),
        reason: vectorCase['name']! as String,
      );
    }
  });
}

File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors'
      '${Platform.pathSeparator}$name',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Golden vector not found: $name.');
}
