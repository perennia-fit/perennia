import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// Checks the committed Open Food Facts bundle against its format
/// (docs/designs/open-food-facts.md, "The bundle file"). The builder has no
/// separate verify mode, so this is what keeps a hand-edited or truncated
/// bundle from merging.
const _bundlePath = 'assets/seeds/open_food_facts_bundle.ndjson.gz';

/// 6 MB, as the builder's `sizeBudgetBytes`.
const _sizeBudgetBytes = 6 * 1024 * 1024;

void main() {
  final file = File(_bundlePath);
  late final List<String> lines;

  setUpAll(() {
    expect(file.existsSync(), isTrue, reason: '$_bundlePath is missing.');
    final text = utf8.decode(gzip.decode(file.readAsBytesSync()));
    expect(text.endsWith('\n'), isTrue, reason: 'Every line ends with \\n.');
    lines = text.substring(0, text.length - 1).split('\n');
  });

  test('the bundle is within the 6 MB budget', () {
    expect(file.lengthSync(), lessThanOrEqualTo(_sizeBudgetBytes));
  });

  test('the header names this format and counts the product lines', () {
    final header = BundleHeader.fromJsonLine(lines.first);

    expect(header.format, bundleFormat);
    expect(header.formatVersion, bundleFormatVersion);
    expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(header.datasetVersion), isTrue);
    expect(header.productCount, lines.length - 1);
    expect(header.productCount, greaterThan(0));
  });

  test('the content hash is the SHA-256 of the product lines', () async {
    final header = BundleHeader.fromJsonLine(lines.first);
    final productBytes = utf8.encode(
      lines.skip(1).map((line) => '$line\n').join(),
    );
    final hash = await Sha256().hash(productBytes);
    final hex =
        hash.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    expect(header.contentHash, hex);
  });

  test('every product line decodes, with only the format keys', () {
    final nutrientKeys = {for (final id in NutrientId.values) id.storageKey};
    for (final (index, line) in lines.skip(1).indexed) {
      final json = jsonDecode(line) as Map<String, Object?>;
      expect(json.keys.toList(), bundleProductLineKeys,
          reason: 'line ${index + 2} keys');
      for (final key in (json['nutrients']! as Map<String, Object?>).keys) {
        expect(nutrientKeys, contains(key),
            reason: 'line ${index + 2}: $key is not a Nutrient id');
      }
      expect(() => decodeBundleProductLine(line), returnsNormally,
          reason: 'line ${index + 2}');
    }
  });

  test('codes are unique and sorted', () {
    String? previous;
    for (final line in lines.skip(1)) {
      final code =
          (jsonDecode(line) as Map<String, Object?>)['code']! as String;
      if (previous != null) {
        expect(code.compareTo(previous), greaterThan(0),
            reason: '$code follows $previous');
      }
      previous = code;
    }
  });
}
