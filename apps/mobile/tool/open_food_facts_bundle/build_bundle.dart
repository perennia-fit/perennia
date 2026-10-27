// Builds the offline Open Food Facts bundle from Open Food Facts' JSONL dump.
//
// Run from apps/mobile:
//
//   dart run tool/open_food_facts_bundle/build_bundle.dart \
//     --input <path to openfoodfacts-products.jsonl.gz> \
//     --dataset-version <YYYY-MM-DD>
//
// The dump is https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz
// (about 13 GB compressed, replaced daily); --dataset-version is its
// Last-Modified date. The output is
// assets/seeds/open_food_facts_bundle.ndjson.gz, followed by a report.
//
// This file is also the "method" the bundle's ODbL notice names: the bundle is
// a derived database, and anyone with the same day's dump can rebuild it.
// Running it twice on the same dump writes the same product lines and the same
// content hash. See docs/designs/open-food-facts.md, "Building the bundle".

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// Country tag in `countries_tags` → the code written in the header.
const launchCountries = <String, String>{
  'en:australia': 'au',
  'en:united-states': 'us',
  'en:united-kingdom': 'gb',
  'en:canada': 'ca',
  'en:new-zealand': 'nz',
};

/// Each country keeps its best products by scans, up to this many.
const perCountryLimit = 10000;

/// The compressed bundle may not be larger than 6 MB (6 × 1,024 × 1,024
/// bytes). `test/data/open_food_facts_bundle_asset_test.dart` checks the same.
const sizeBudgetBytes = 6 * 1024 * 1024;

const outputPath = 'assets/seeds/open_food_facts_bundle.ndjson.gz';

const _coreNutrients = <NutrientId>[
  NutrientId.energy,
  NutrientId.protein,
  NutrientId.carbohydrate,
  NutrientId.fat,
];

const _attributionText =
    'Contains information from Open Food Facts, made available under the Open '
    'Database License (ODbL) 1.0. The bundle, its licence file and the tool '
    'that builds it are in the Perennia repository: '
    'apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz, '
    'apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md and '
    'apps/mobile/tool/open_food_facts_bundle/build_bundle.dart.';

Future<void> main(List<String> args) async {
  final options = _parseArguments(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/open_food_facts_bundle/build_bundle.dart '
      '--input <openfoodfacts-products.jsonl.gz> '
      '--dataset-version <YYYY-MM-DD>',
    );
    exit(64);
  }
  final input = File(options.input);
  if (!input.existsSync()) {
    stderr.writeln('Input not found: ${options.input}');
    exit(66);
  }

  final stopwatch = Stopwatch()..start();
  final report = _Report();
  // Step 2: every kept product, by code, after duplicates are resolved.
  final kept = <String, _Candidate>{};

  try {
    final lines = input
        .openRead()
        .transform(gzip.decoder)
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final line in lines) {
      report.linesRead++;
      if (report.linesRead % 500000 == 0) {
        stderr.writeln(
          '  ${report.linesRead} lines read, '
          '${kept.length} kept, ${stopwatch.elapsed.inSeconds} s',
        );
      }
      // Step 1: skip before decoding; most of the dump is other countries.
      if (!launchCountries.keys.any(line.contains)) {
        continue;
      }
      try {
        _consider(line, report.linesRead, kept, report);
      } on Object catch (error) {
        // One odd product must not end a 30-minute run; the report names it.
        report.failedLines.add('line ${report.linesRead}: $error');
      }
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read ${options.input}: ${error.message}');
    exit(66);
  } on FormatException catch (error) {
    stderr.writeln('Could not decompress ${options.input}: ${error.message}');
    exit(65);
  }

  // Step 3: each country keeps its best products.
  final byCountry = <String, List<_Candidate>>{
    for (final tag in launchCountries.keys) tag: <_Candidate>[],
  };
  for (final candidate in kept.values) {
    for (final tag in candidate.countryTags) {
      byCountry[tag]!.add(candidate);
    }
  }
  final eligibleByCountry = <String, int>{
    for (final MapEntry(:key, :value) in byCountry.entries) key: value.length,
  };
  for (final list in byCountry.values) {
    list.sort(_byRank);
    if (list.length > perCountryLimit) {
      list.removeRange(perCountryLimit, list.length);
    }
  }

  // Step 4: merge, remove duplicate codes, sort by code (string order).
  final merged = <String, _Candidate>{
    for (final list in byCountry.values)
      for (final candidate in list) candidate.product.code: candidate,
  }.values.toList()
    ..sort((a, b) => a.product.code.compareTo(b.product.code));

  // Step 5: header, product lines, gzip.
  final productBytes = BytesBuilder(copy: false);
  for (final candidate in merged) {
    productBytes.add(
      utf8.encode('${encodeBundleProductLine(candidate.product)}\n'),
    );
  }
  final productLines = productBytes.takeBytes();
  final hash = await Sha256().hash(productLines);

  final header = BundleHeader(
    format: bundleFormat,
    formatVersion: bundleFormatVersion,
    datasetVersion: options.datasetVersion,
    contentHash: _hex(hash.bytes),
    sourceName: 'Open Food Facts',
    sourceUrl: 'https://world.openfoodfacts.org/',
    licenseName: 'Open Database License (ODbL) 1.0',
    licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    contentsLicenseUrl: 'https://opendatacommons.org/licenses/dbcl/1-0/',
    attributionText: _attributionText,
    countries: launchCountries.values.toList(),
    perCountryLimit: perCountryLimit,
    productCount: merged.length,
  );
  final uncompressed = BytesBuilder(copy: false)
    ..add(utf8.encode('${header.toJsonLine()}\n'))
    ..add(productLines);
  final compressed = GZipCodec(level: 9).encode(uncompressed.takeBytes());
  File(outputPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(compressed);

  // Step 6: the report.
  stopwatch.stop();
  report.print(
    eligibleByCountry: eligibleByCountry,
    keptByCountry: {
      for (final MapEntry(:key, :value) in byCountry.entries) key: value.length,
    },
    merged: merged,
    uncompressedProductBytes: productLines.length,
    compressedBytes: compressed.length,
    header: header,
    elapsed: stopwatch.elapsed,
  );

  if (compressed.length > sizeBudgetBytes) {
    stderr.writeln(
      'The bundle is ${compressed.length} bytes, over the '
      '$sizeBudgetBytes-byte budget.',
    );
    exit(1);
  }
}

/// Step 2 for one line: decode, map, keep when eligible, and resolve a
/// duplicate code against the copy already kept.
void _consider(
  String line,
  int lineNumber,
  Map<String, _Candidate> kept,
  _Report report,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    report.malformedLines++;
    return;
  }
  if (decoded is! Map<String, Object?>) {
    report.malformedLines++;
    return;
  }
  final countryTags = decoded['countries_tags'];
  final tags = <String>{
    if (countryTags is List)
      for (final tag in countryTags)
        if (tag is String && launchCountries.containsKey(tag)) tag,
  };
  if (tags.isEmpty) {
    // The tag text appeared elsewhere in the line.
    report.notInLaunchCountry++;
    return;
  }
  report.launchCountryProducts++;

  final MappedOpenFoodFactsProduct product;
  switch (mapOpenFoodFactsProduct(decoded)) {
    case ExcludedOpenFoodFactsProduct(:final reason):
      report.excluded[reason] = (report.excluded[reason] ?? 0) + 1;
      return;
    case final MappedOpenFoodFactsProduct mapped:
      product = mapped;
  }
  if (!_coreNutrients.every(product.nutrientText.containsKey)) {
    report.missingCoreNutrients++;
    return;
  }
  if ((product.scans ?? 0) <= 0) {
    report.zeroScans++;
    return;
  }

  final candidate = _Candidate(
    product: product,
    countryTags: tags,
    structure: openFoodFactsNutrientStructure(decoded),
    lineNumber: lineNumber,
  );
  final existing = kept[product.code];
  if (existing != null) {
    report.duplicateCodes++;
    if (!_winsDuplicate(candidate, existing)) {
      return;
    }
  }
  kept[product.code] = candidate;
}

/// A duplicate code keeps the later change date, then more scans, then the
/// earlier line.
bool _winsDuplicate(_Candidate challenger, _Candidate existing) {
  final byDate = challenger.product.modifiedAt.compareTo(
    existing.product.modifiedAt,
  );
  if (byDate != 0) {
    return byDate > 0;
  }
  final byScans = challenger.product.scans!.compareTo(existing.product.scans!);
  if (byScans != 0) {
    return byScans > 0;
  }
  return challenger.lineNumber < existing.lineNumber;
}

/// Scans descending, then code ascending.
int _byRank(_Candidate a, _Candidate b) {
  final byScans = b.product.scans!.compareTo(a.product.scans!);
  return byScans != 0 ? byScans : a.product.code.compareTo(b.product.code);
}

class _Candidate {
  const _Candidate({
    required this.product,
    required this.countryTags,
    required this.structure,
    required this.lineNumber,
  });

  final MappedOpenFoodFactsProduct product;
  final Set<String> countryTags;
  final OpenFoodFactsNutrientStructure structure;
  final int lineNumber;
}

class _Report {
  int linesRead = 0;
  int malformedLines = 0;
  int notInLaunchCountry = 0;
  int launchCountryProducts = 0;
  final Map<OpenFoodFactsExclusion, int> excluded = {};
  int missingCoreNutrients = 0;
  int zeroScans = 0;
  int duplicateCodes = 0;

  /// Lines whose mapping threw, with the line number and the error.
  final List<String> failedLines = [];

  void print({
    required Map<String, int> eligibleByCountry,
    required Map<String, int> keptByCountry,
    required List<_Candidate> merged,
    required int uncompressedProductBytes,
    required int compressedBytes,
    required BundleHeader header,
    required Duration elapsed,
  }) {
    final byStructure = <OpenFoodFactsNutrientStructure, int>{};
    for (final candidate in merged) {
      byStructure[candidate.structure] =
          (byStructure[candidate.structure] ?? 0) + 1;
    }
    final out = StringBuffer()
      ..writeln('Open Food Facts bundle report')
      ..writeln('  dataset version:         ${header.datasetVersion}')
      ..writeln('  content hash:            ${header.contentHash}')
      ..writeln('  dump lines read:         $linesRead')
      ..writeln('  malformed lines:         $malformedLines')
      ..writeln('  failed lines:            ${failedLines.length}')
      ..writeAll(failedLines.take(10).map((line) => '    $line\n'))
      ..writeln('  tag text, not tagged:    $notInLaunchCountry')
      ..writeln('  launch-country products: $launchCountryProducts')
      ..writeln('  excluded by the mapping:');
    for (final reason in OpenFoodFactsExclusion.values) {
      out.writeln('    ${reason.name.padRight(21)} ${excluded[reason] ?? 0}');
    }
    out
      ..writeln('  missing core nutrients:  $missingCoreNutrients')
      ..writeln('  zero scans:              $zeroScans')
      ..writeln('  duplicate codes:         $duplicateCodes')
      ..writeln('  per country (eligible → kept, limit $perCountryLimit):');
    for (final MapEntry(key: tag, value: code) in launchCountries.entries) {
      out.writeln(
        '    $code  ${eligibleByCountry[tag].toString().padLeft(8)} → '
        '${keptByCountry[tag]}',
      );
    }
    out
      ..writeln('  merged products:         ${merged.length}')
      ..writeln('  nutrients read from:');
    for (final structure in OpenFoodFactsNutrientStructure.values) {
      out.writeln(
        '    ${structure.name.padRight(21)} ${byStructure[structure] ?? 0}',
      );
    }
    out
      ..writeln(
        '  product lines:           $uncompressedProductBytes bytes '
        'uncompressed',
      )
      ..writeln(
        '  compressed bundle:       $compressedBytes bytes '
        '(${(compressedBytes / 1024 / 1024).toStringAsFixed(2)} MB, '
        'budget ${sizeBudgetBytes ~/ 1024 ~/ 1024} MB)',
      )
      ..writeln('  run time:                ${_duration(elapsed)}')
      ..writeln('  wrote:                   $outputPath');
    stdout.write(out);
  }
}

({String input, String datasetVersion})? _parseArguments(List<String> args) {
  final values = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final [name, ...inline] = args[i].split('=');
    final value = inline.isNotEmpty
        ? inline.join('=')
        : (i + 1 < args.length && !args[i + 1].startsWith('--')
            ? args[++i]
            : null);
    if (name != '--input' && name != '--dataset-version') {
      stderr.writeln('Unknown argument: $name');
      return null;
    }
    if (value == null) {
      stderr.writeln('$name needs a value.');
      return null;
    }
    values[name] = value;
  }
  final input = values['--input'];
  final datasetVersion = values['--dataset-version'];
  if (input == null || datasetVersion == null) {
    stderr.writeln('Both --input and --dataset-version are required.');
    return null;
  }
  if (!_isDate(datasetVersion)) {
    stderr.writeln('--dataset-version must be a YYYY-MM-DD date.');
    return null;
  }
  return (input: input, datasetVersion: datasetVersion);
}

/// A dataset version is a `YYYY-MM-DD` date, the same form as a nutrition day.
bool _isDate(String value) {
  try {
    NutritionDayDate.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String _duration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds % 60;
  return minutes > 0 ? '$minutes min $seconds s' : '$seconds s';
}
