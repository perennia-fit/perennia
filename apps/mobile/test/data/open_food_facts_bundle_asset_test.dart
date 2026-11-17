import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// Checks the committed Open Food Facts bundle against its format
/// (docs/designs/open-food-facts.md, "The bundle file"). The builder has no
/// separate verify mode, so this is what keeps a hand-edited or truncated
/// bundle from merging.
const _bundlePath = openFoodFactsBundleAssetPath;

/// 6 MB, as the builder's `sizeBudgetBytes`.
const _sizeBudgetBytes = 6 * 1024 * 1024;

void main() {
  final file = File(_bundlePath);
  late final List<int> bytes;
  late final int headerEnd;
  late final BundleHeader header;
  late final List<String> productLines;

  setUpAll(() {
    expect(file.existsSync(), isTrue, reason: '$_bundlePath is missing.');
    bytes = gzip.decode(file.readAsBytesSync());
    expect(bytes.last, 0x0A, reason: 'Every line ends with a newline.');
    headerEnd = bytes.indexOf(0x0A);
    header = BundleHeader.fromJsonLine(
      utf8.decode(bytes.sublist(0, headerEnd)),
    );
    productLines =
        const LineSplitter().convert(utf8.decode(bytes.sublist(headerEnd + 1)));
  });

  test('the bundle is within the 6 MB budget', () {
    expect(file.lengthSync(), lessThanOrEqualTo(_sizeBudgetBytes));
  });

  test('the header names this format and counts the product lines', () {
    expect(header.format, bundleFormat);
    expect(header.formatVersion, bundleFormatVersion);
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(header.datasetVersion),
      isTrue,
    );
    expect(header.productCount, productLines.length);
    expect(header.productCount, greaterThan(0));
  });

  test('the content hash is the SHA-256 of the product lines', () async {
    final hash = await Sha256().hash(bytes.sublist(headerEnd + 1));
    final hex =
        hash.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    expect(header.contentHash, hex);
  });

  test('every product line is in the canonical format, sorted by code', () {
    // Re-encoding a decoded line reproduces it exactly only when it has every
    // format key, in order, with no others; decoding also rejects a nutrient
    // key that is not a Nutrient id.
    final failures = <String>[];
    String? previousCode;
    for (final (index, line) in productLines.indexed) {
      final MappedOpenFoodFactsProduct product;
      try {
        product = decodeBundleProductLine(line);
      } on Object catch (error) {
        failures.add('line ${index + 2} does not decode: $error');
        continue;
      }
      if (encodeBundleProductLine(product) != line) {
        failures.add('line ${index + 2} is not in the canonical format');
      }
      if (previousCode != null && product.code.compareTo(previousCode) <= 0) {
        failures.add('line ${index + 2}: ${product.code} follows '
            '$previousCode');
      }
      previousCode = product.code;
    }

    expect(failures, isEmpty);
  });
}
