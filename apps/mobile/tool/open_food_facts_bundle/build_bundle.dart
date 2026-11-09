// Builds the offline Open Food Facts bundle.
//
// Run from apps/mobile, from Open Food Facts' JSONL dump:
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
// Or from an existing bundle, keeping its products and dataset version, with
// each product's Open Food Facts tags from the CSV export (tab separated
// despite its name), joined by code:
//
//   dart run tool/open_food_facts_bundle/build_bundle.dart \
//     --from-bundle assets/seeds/open_food_facts_bundle.ndjson.gz \
//     --tags-export <path to en.openfoodfacts.org.products.csv.gz>
//
// The bundle is read in full first, so it can be the file this run replaces.
//
// Adding Aisles is these runs: this tool with --aisle-input-only, which writes
// build/open_food_facts_aisle_input.ndjson and no bundle; label_aisles.dart
// label, second-opinion-input, second-opinion-apply and review; and this tool
// again, which refuses to write a bundle while any product's label, or a
// second opinion it needs, is missing or stale. --aisle-labels,
// --aisle-second-opinions and --aisle-overrides name the three data files when
// they are not at their committed paths. See docs/designs/food-aisles.md,
// "The builder".
//
// Exit status: 0 done, 1 data missing or stale or the bundle over budget,
// 64 usage, 65 a file that does not parse or decompress, 66 a missing input.
//
// This file is also the "method" the bundle's ODbL notice names: the bundle is
// a derived database, and anyone with the same day's dump can rebuild it.
// Running it twice on the same dump writes the same product lines and the same
// content hash. See docs/designs/open-food-facts.md, "Building the bundle".

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:perennia/domain/nutrition/food_aisle.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

import 'aisle_pipeline.dart';

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

const outputPath = openFoodFactsBundleAssetPath;

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
    'apps/mobile/tool/open_food_facts_bundle/build_bundle.dart. Each '
    "product's Aisle is decided from "
    'apps/mobile/tool/open_food_facts_bundle/aisle_labels.ndjson, '
    'aisle_second_opinions.ndjson and aisle_overrides.csv, made with '
    'label_aisles.dart, in the same directory.';

const _usage = '''
Usage:
  dart run tool/open_food_facts_bundle/build_bundle.dart --input <openfoodfacts-products.jsonl.gz> --dataset-version <YYYY-MM-DD> [options]
  dart run tool/open_food_facts_bundle/build_bundle.dart --from-bundle <bundle .ndjson.gz> --tags-export <en.openfoodfacts.org.products.csv.gz> [options]

Options:
  --aisle-labels <path>            default $aisleLabelsPath
  --aisle-second-opinions <path>   default $aisleSecondOpinionsPath
  --aisle-overrides <path>         default $aisleOverridesPath
  --aisle-input-only               write $aisleInputPath and no bundle''';

Future<void> main(List<String> args) async {
  final options = _parseArguments(args);
  if (options == null) {
    stderr.writeln(_usage);
    exit(64);
  }
  for (final path in [
    options.input,
    options.fromBundle,
    options.tagsExport,
  ].nonNulls) {
    if (!File(path).existsSync()) {
      stderr.writeln('Input not found: $path');
      exit(66);
    }
  }
  // Read before the products, so a broken data file costs seconds, not 30
  // minutes.
  final AisleLabels labels;
  final AisleSecondOpinions secondOpinions;
  final List<AisleOverrideRow> overrides;
  try {
    labels = _readDataFile(
      options.aisleLabels,
      parse: parseAisleLabels,
      ifMissing: const AisleLabels(header: null, byCode: {}),
    );
    secondOpinions = _readDataFile(
      options.aisleSecondOpinions,
      parse: parseAisleSecondOpinions,
      ifMissing: const AisleSecondOpinions(header: null, byCode: {}),
    );
    overrides = _readDataFile(
      options.aisleOverrides,
      parse: parseAisleOverrides,
      ifMissing: const [],
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(65);
  }

  final stopwatch = Stopwatch()..start();
  final report = _Report();
  final List<_Candidate> products;
  final String datasetVersion;
  final fromBundle = options.fromBundle;
  final tagsExport = options.tagsExport;
  if (fromBundle != null && tagsExport != null) {
    final read = await _readFromBundle(fromBundle, tagsExport, report);
    products = read.products;
    datasetVersion = read.datasetVersion;
  } else {
    products = await _readDump(options.input!, report, stopwatch);
    datasetVersion = options.datasetVersion!;
  }

  // The labeller's input, whichever kind of run this is: it is what a run that
  // stops here tells the maintainer to label.
  final aisleInput = [
    for (final candidate in products) candidate.aisleInputLine,
  ]..sort((a, b) => a.code.compareTo(b.code));
  File(aisleInputPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(
      aisleInput.map((line) => '${encodeAisleInputLine(line)}\n').join(),
    );
  final needLabels = aisleInput
      .where(
        (line) => !isCurrentLabel(
          labels.byCode[line.code],
          labels.header,
          line.inputHash,
        ),
      )
      .length;
  final needSecondOpinions =
      secondOpinionsToAsk(aisleInput, labels, secondOpinions).length;
  if (options.aisleInputOnly || needLabels > 0 || needSecondOpinions > 0) {
    report.printAisleInput(
      productCount: aisleInput.length,
      needLabels: needLabels,
      needSecondOpinions: needSecondOpinions,
    );
    if (options.aisleInputOnly) {
      return;
    }
    // Edge cases nobody answered do not stop a build: they have no Aisle.
    // Labels come first, because a product with none cannot say yet whether
    // it needs a second opinion.
    stdout.writeln(
      needLabels > 0
          ? '$needLabels products need labels: run label_aisles.dart label, '
              'then build again.'
          : '$needSecondOpinions products need a second opinion: run '
              'label_aisles.dart second-opinion-input, then build again.',
    );
    exit(1);
  }

  // Every label, and every second opinion a product needs, is current from
  // here on. Only current second opinions are passed: a stale line must not
  // count as agreement.
  final currentSecondOpinions = <String, AisleSecondOpinion>{
    for (final line in aisleInput)
      if (isCurrentSecondOpinion(
        secondOpinions.byCode[line.code],
        secondOpinions.header,
        line.inputHash,
      ))
        line.code: secondOpinions.byCode[line.code]!,
  };
  final aisleBundle = resolveAisleBundle(
    input: aisleInput,
    labels: labels.byCode,
    secondOpinions: currentSecondOpinions,
    overrides: overrides,
  );

  // Step 5: header, product lines, gzip. Each line carries the product's
  // resolved Aisle (format version 2).
  final aisleByCode = {
    for (final product in aisleBundle) product.code: product.aisle,
  };
  final productBytes = BytesBuilder(copy: false);
  for (final candidate in products) {
    final line = encodeBundleProductLine(
      candidate.product,
      aisle: aisleByCode[candidate.product.code],
    );
    productBytes.add(utf8.encode('$line\n'));
  }
  final productLines = productBytes.takeBytes();
  final hash = await Sha256().hash(productLines);

  final header = BundleHeader(
    format: bundleFormat,
    formatVersion: bundleFormatVersion,
    datasetVersion: datasetVersion,
    contentHash: _hex(hash.bytes),
    sourceName: 'Open Food Facts',
    sourceUrl: openFoodFactsBaseUrl,
    licenseName: 'Open Database License (ODbL) 1.0',
    licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    contentsLicenseUrl: 'https://opendatacommons.org/licenses/dbcl/1-0/',
    attributionText: _attributionText,
    countries: launchCountries.values.toList(),
    perCountryLimit: perCountryLimit,
    productCount: products.length,
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
    products: products,
    aisles: _AisleFigures.of(
      products: products,
      bundle: aisleBundle,
      labels: labels.byCode,
      secondOpinions: currentSecondOpinions,
      overrides: overrides,
    ),
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
    exitCode = 1;
  }
}

/// Steps 1 to 4 from the dump: every kept product, merged and sorted by code.
Future<List<_Candidate>> _readDump(
  String path,
  _Report report,
  Stopwatch stopwatch,
) async {
  // Step 2: every kept product, by code, after duplicates are resolved.
  final kept = <String, _Candidate>{};
  try {
    final lines = File(path)
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
    stderr.writeln('Could not read $path: ${error.message}');
    exit(66);
  } on FormatException catch (error) {
    stderr.writeln('Could not decompress $path: ${error.message}');
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
  report.eligibleByCountry = {
    for (final MapEntry(:key, :value) in byCountry.entries) key: value.length,
  };
  for (final list in byCountry.values) {
    list.sort(_byRank);
    if (list.length > perCountryLimit) {
      list.removeRange(perCountryLimit, list.length);
    }
  }
  report.keptByCountry = {
    for (final MapEntry(:key, :value) in byCountry.entries) key: value.length,
  };

  // Step 4: merge, remove duplicate codes, sort by code (string order).
  return <String, _Candidate>{
    for (final list in byCountry.values)
      for (final candidate in list) candidate.product.code: candidate,
  }.values.toList()
    ..sort((a, b) => a.product.code.compareTo(b.product.code));
}

/// The products of an existing bundle file, with tags and countries from the
/// tags export, in place of steps 1 to 4. A dump is 13 GB and Open Food Facts
/// keeps no older ones, so this is how Aisles are added without refreshing the
/// products. The bundle is read in full before anything is written, so
/// [bundlePath] can be the file this run replaces. The products, their order,
/// every field but `aisle`, and the dataset version are the file's.
Future<({List<_Candidate> products, String datasetVersion})> _readFromBundle(
  String bundlePath,
  String exportPath,
  _Report report,
) async {
  final List<String> lines;
  try {
    lines = const LineSplitter().convert(
      utf8.decode(gzip.decode(File(bundlePath).readAsBytesSync())),
    );
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read $bundlePath: ${error.message}');
    exit(66);
  } on FormatException catch (error) {
    stderr.writeln('Could not decompress $bundlePath: ${error.message}');
    exit(65);
  }
  final BundleHeader header;
  final products = <MappedOpenFoodFactsProduct>[];
  try {
    if (lines.isEmpty) {
      throw const FormatException('line 1: there is no header');
    }
    header = _decodeBundleLine(lines.first, 1, BundleHeader.fromJsonLine);
    if (header.format != bundleFormat ||
        !_readableBundleVersions.contains(header.formatVersion)) {
      throw FormatException(
        'line 1: not a $bundleFormat file of format version '
        '${_readableBundleVersions.join(' or ')}',
      );
    }
    for (var i = 1; i < lines.length; i++) {
      products.add(_decodeBundleLine(lines[i], i + 1, _decodeProductLine));
    }
  } on FormatException catch (error) {
    stderr.writeln('$bundlePath: ${error.message}');
    exit(65);
  }
  report.fromBundle = (
    path: bundlePath,
    datasetVersion: header.datasetVersion,
    products: products.length,
  );

  final wanted = {for (final product in products) product.code};
  final tagsByCode =
      <String, ({List<String> categories, List<String> countries})>{};
  try {
    AisleTagsColumns? columns;
    final rows = File(exportPath)
        .openRead()
        .transform(gzip.decoder)
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final line in rows) {
      if (columns == null) {
        columns = parseAisleTagsHeader(line);
        continue;
      }
      report.exportRowsRead++;
      if (report.exportRowsRead % 1000000 == 0) {
        stderr.writeln('  ${report.exportRowsRead} export rows read');
      }
      final row = parseAisleTagsRow(line, columns);
      if (row == null) {
        report.exportRowsSkipped++;
        continue;
      }
      // A later row with the same code wins.
      if (wanted.contains(row.code)) {
        tagsByCode[row.code] = (
          categories: row.categories,
          countries: row.countries,
        );
      }
    }
    if (columns == null) {
      throw const FormatException('line 1: there is no header row');
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read $exportPath: ${error.message}');
    exit(66);
  } on FormatException catch (error) {
    stderr.writeln('$exportPath: ${error.message}');
    exit(65);
  }

  final candidates = <_Candidate>[];
  for (final product in products) {
    final tags = tagsByCode[product.code];
    if (tags != null) {
      report.productsInExport++;
      if (tags.categories.isNotEmpty) {
        report.productsWithTags++;
      }
    }
    candidates.add(
      _Candidate(
        product: product,
        countryTags: {...?tags?.countries},
        structure: null,
        lineNumber: 0,
        // A product not in the export has no tags and is labelled from its
        // name and brand.
        categories: tags?.categories ?? const [],
      ),
    );
  }
  return (products: candidates, datasetVersion: header.datasetVersion);
}

/// The bundle format versions `--from-bundle` reads: 1, whose lines have no
/// `aisle`, and 2.
const _readableBundleVersions = {1, 2};

/// A bundle product line. A line with no `aisle` key (format version 1) gets
/// `"aisle":null` before the decoder reads it, the one place a missing key is
/// accepted; any `aisle` already on a line is ignored, because this run
/// decides it again.
MappedOpenFoodFactsProduct _decodeProductLine(String line) {
  final json = jsonDecode(line);
  if (json is! Map<String, Object?>) {
    throw const FormatException('not a JSON object');
  }
  final withAisle = json.containsKey('aisle')
      ? json
      : <String, Object?>{...json, 'aisle': null};
  return decodeBundleProductLine(jsonEncode(withAisle)).product;
}

/// [decode] for one line of the bundle, as a [FormatException] naming the
/// line when the line does not decode. The decoders cast, so a wrong or
/// missing value arrives as a [TypeError].
T _decodeBundleLine<T>(
  String line,
  int lineNumber,
  T Function(String line) decode,
) {
  try {
    return decode(line);
  } on FormatException catch (error) {
    throw FormatException('line $lineNumber: ${error.message}');
  } on TypeError catch (error) {
    throw FormatException('line $lineNumber: $error');
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
    categories: _englishCategories(decoded['categories_hierarchy']),
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

/// The `en:` entries of `categories_hierarchy`, in order, prefix kept. Anything
/// but a list records no tags.
List<String> _englishCategories(Object? hierarchy) {
  return <String>[
    if (hierarchy is List)
      for (final tag in hierarchy)
        if (tag is String && tag.startsWith('en:')) tag,
  ];
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
    required this.categories,
  });

  final MappedOpenFoodFactsProduct product;

  /// From a dump, the launch countries the product is kept for; from a bundle,
  /// every `en:` entry of the tags export's `countries_tags`.
  final Set<String> countryTags;

  /// `null` for a product read from a bundle, which does not record it.
  final OpenFoodFactsNutrientStructure? structure;
  final int lineNumber;

  /// The product's Open Food Facts tags, `en:` kept.
  final List<String> categories;

  AisleInputLine get aisleInputLine => AisleInputLine(
        code: product.code,
        name: product.name,
        brand: product.brand,
        categories: categories,
        scans: product.scans!,
        inputHash: aisleInputHash(
          aisleModelState(
            name: product.name,
            brand: product.brand,
            categories: categories,
          ),
        ),
      );
}

/// The Aisle lines of the report of a run that writes a bundle, worked out
/// from the data that decided each product's Aisle.
final class _AisleFigures {
  _AisleFigures._();

  final perAisle = <FoodAisle?, int>{};
  int overrideAisle = 0;
  int overrideNone = 0;
  int byLabel = 0;
  int byAgreement = 0;
  int byNone = 0;
  int productCount = 0;
  int secondOpinionsAgreed = 0;
  int secondOpinionsBothOther = 0;
  int edgeCases = 0;
  int edgeCasesAnswered = 0;
  int edgeCasesWithNoAisle = 0;
  int unsureRows = 0;

  /// For each Aisle, its [aisleBrowseLimit] most scanned products' countries.
  final topCountries = <FoodAisle, List<Set<String>>>{};

  /// [labels] and [secondOpinions] are current; every product has a label.
  factory _AisleFigures.of({
    required List<_Candidate> products,
    required List<AisleBundleProduct> bundle,
    required Map<String, AisleLabel> labels,
    required Map<String, AisleSecondOpinion> secondOpinions,
    required List<AisleOverrideRow> overrides,
  }) {
    final figures = _AisleFigures._();
    final overrideByCode = {for (final row in overrides) row.code: row};
    final countriesByCode = {
      for (final candidate in products)
        candidate.product.code: candidate.countryTags,
    };
    final byAisle = <FoodAisle, List<AisleBundleProduct>>{};
    for (final product in bundle) {
      figures.productCount++;
      final aisle = product.aisle;
      figures.perAisle[aisle] = (figures.perAisle[aisle] ?? 0) + 1;
      if (aisle != null) {
        (byAisle[aisle] ??= []).add(product);
      }

      final label = labels[product.code]!;
      final override = overrideByCode[product.code];
      // The deciding step, by asking resolveFoodAisle with fewer inputs, so
      // the report cannot disagree with the rule it reports on.
      if (override?.answer == AisleOverrideAnswer.aisle) {
        figures.overrideAisle++;
      } else if (override?.answer == AisleOverrideAnswer.none) {
        figures.overrideNone++;
      } else if (resolveFoodAisle(currentLabel: label) != null) {
        figures.byLabel++;
      } else if (aisle != null) {
        figures.byAgreement++;
      } else {
        figures.byNone++;
      }

      final opinion = secondOpinions[product.code];
      if (isConfidentLabel(label) || opinion == null) {
        continue;
      }
      if (opinion.aisle == label.aisle) {
        if (opinion.aisle == null) {
          figures.secondOpinionsBothOther++;
        } else {
          figures.secondOpinionsAgreed++;
        }
        continue;
      }
      figures.edgeCases++;
      if (override != null) {
        figures.edgeCasesAnswered++;
      }
      if (aisle == null) {
        figures.edgeCasesWithNoAisle++;
      }
    }
    figures.unsureRows = overrides
        .where((row) => row.answer == AisleOverrideAnswer.unsure)
        .length;
    for (final MapEntry(key: aisle, value: list) in byAisle.entries) {
      list.sort((a, b) {
        final byScans = b.scans.compareTo(a.scans);
        return byScans != 0 ? byScans : a.code.compareTo(b.code);
      });
      figures.topCountries[aisle] = [
        for (final product in list.take(aisleBrowseLimit))
          countriesByCode[product.code] ?? const {},
      ];
    }
    return figures;
  }

  void write(StringBuffer out) {
    final withAisle = productCount - (perAisle[null] ?? 0);
    final share = productCount == 0 ? 0.0 : withAisle / productCount;
    out.writeln('  products per Aisle:');
    for (final aisle in FoodAisle.values) {
      out.writeln('    ${aisle.name.padRight(21)} ${perAisle[aisle] ?? 0}');
    }
    out
      ..writeln('    ${'no Aisle'.padRight(21)} ${perAisle[null] ?? 0}')
      ..writeln('  products per deciding step:')
      ..writeln('    ${'override, an Aisle'.padRight(21)} $overrideAisle')
      ..writeln('    ${'override, none'.padRight(21)} $overrideNone')
      ..writeln('    ${'label'.padRight(21)} $byLabel')
      ..writeln('    ${'agreement'.padRight(21)} $byAgreement')
      ..writeln('    ${'none'.padRight(21)} $byNone')
      ..writeln(
        '  products with an Aisle:  $withAisle of $productCount '
        '(${_percent(share)}; floor ${_percent(aisleCoverageFloor)}'
        '${share < aisleCoverageFloor ? ', BELOW THE FLOOR' : ''})',
      )
      ..writeln('  second opinions:')
      ..writeln('    ${'agreed'.padRight(21)} $secondOpinionsAgreed')
      ..writeln('    ${'both other'.padRight(21)} $secondOpinionsBothOther')
      ..writeln('    ${'made an edge case'.padRight(21)} $edgeCases')
      ..writeln('  edge cases answered by a person: $edgeCasesAnswered')
      ..writeln('  edge cases with no Aisle:        $edgeCasesWithNoAisle')
      ..writeln('  override rows marked unsure:     $unsureRows')
      ..writeln(
        '  launch countries in each Aisle\'s $aisleBrowseLimit most scanned '
        'products:',
      );
    for (final aisle in FoodAisle.values) {
      final top = topCountries[aisle] ?? const [];
      final counts = launchCountries.entries.map((country) {
        final carrying = top.where((tags) => tags.contains(country.key));
        return '${country.value} ${carrying.length}';
      });
      out.writeln('    ${aisle.name.padRight(21)} ${counts.join('  ')}');
    }
  }
}

class _Report {
  // From a dump.
  int linesRead = 0;
  int malformedLines = 0;
  int notInLaunchCountry = 0;
  int launchCountryProducts = 0;
  final Map<OpenFoodFactsExclusion, int> excluded = {};
  int missingCoreNutrients = 0;
  int zeroScans = 0;
  int duplicateCodes = 0;
  Map<String, int> eligibleByCountry = const {};
  Map<String, int> keptByCountry = const {};

  /// Lines whose mapping threw, with the line number and the error.
  final List<String> failedLines = [];

  // From a bundle and the tags export. `fromBundle` is null for a dump.
  ({String path, String datasetVersion, int products})? fromBundle;
  int exportRowsRead = 0;
  int exportRowsSkipped = 0;
  int productsInExport = 0;
  int productsWithTags = 0;

  void print({
    required List<_Candidate> products,
    required _AisleFigures aisles,
    required int uncompressedProductBytes,
    required int compressedBytes,
    required BundleHeader header,
    required Duration elapsed,
  }) {
    final out = StringBuffer()
      ..writeln('Open Food Facts bundle report')
      ..writeln('  dataset version:         ${header.datasetVersion}')
      ..writeln('  content hash:            ${header.contentHash}');
    _writeInputSection(out);
    out.writeln('  merged products:         ${products.length}');
    if (fromBundle == null) {
      final byStructure = <OpenFoodFactsNutrientStructure, int>{};
      for (final candidate in products) {
        final structure = candidate.structure!;
        byStructure[structure] = (byStructure[structure] ?? 0) + 1;
      }
      out.writeln('  nutrients read from:');
      for (final structure in OpenFoodFactsNutrientStructure.values) {
        out.writeln(
          '    ${structure.name.padRight(21)} ${byStructure[structure] ?? 0}',
        );
      }
    }
    out
      ..writeln('  labels missing or stale: 0')
      ..writeln('  second opinions missing or stale: 0');
    aisles.write(out);
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

  /// The report of a run that stops after the aisle input: it has no header,
  /// hash or size lines, because no bundle was built.
  void printAisleInput({
    required int productCount,
    required int needLabels,
    required int needSecondOpinions,
  }) {
    final out = StringBuffer()..writeln('Open Food Facts aisle input report');
    _writeInputSection(out);
    out
      ..writeln('  aisle input:             $aisleInputPath')
      ..writeln('  aisle input products:    $productCount')
      ..writeln('  labels missing or stale: $needLabels')
      ..writeln('  second opinions missing or stale: $needSecondOpinions');
    stdout.write(out);
  }

  /// What was read: the dump's figures, or the bundle's and the export's.
  void _writeInputSection(StringBuffer out) {
    final bundle = fromBundle;
    if (bundle != null) {
      out
        ..writeln('  bundle read:             ${bundle.path}')
        ..writeln('  bundle dataset version:  ${bundle.datasetVersion}')
        ..writeln('  bundle products read:    ${bundle.products}')
        ..writeln('  export rows read:        $exportRowsRead')
        ..writeln(
            '  export rows skipped:     $exportRowsSkipped (too few cells)')
        ..writeln('  products in the export:  $productsInExport')
        ..writeln(
          '  products not in it:      ${bundle.products - productsInExport} '
          '(labelled from name and brand)',
        )
        ..writeln('  products with tags:      $productsWithTags');
      return;
    }
    out
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
  }
}

typedef _Options = ({
  String? input,
  String? datasetVersion,
  String? fromBundle,
  String? tagsExport,
  String aisleLabels,
  String aisleSecondOpinions,
  String aisleOverrides,
  bool aisleInputOnly,
});

/// The options, or `null` (exit 64) for an unknown option, a missing value,
/// a value given to the `--aisle-input-only` flag, both inputs at once, or
/// half of either.
_Options? _parseArguments(List<String> args) {
  const flag = '--aisle-input-only';
  const valued = {
    '--input',
    '--dataset-version',
    '--from-bundle',
    '--tags-export',
    '--aisle-labels',
    '--aisle-second-opinions',
    '--aisle-overrides',
  };
  final values = <String, String>{};
  var aisleInputOnly = false;
  for (var i = 0; i < args.length; i++) {
    final [name, ...inline] = args[i].split('=');
    if (name == flag) {
      if (inline.isNotEmpty) {
        stderr.writeln('$flag takes no value.');
        return null;
      }
      aisleInputOnly = true;
      continue;
    }
    final value = inline.isNotEmpty
        ? inline.join('=')
        : (i + 1 < args.length && !args[i + 1].startsWith('--')
            ? args[++i]
            : null);
    if (!valued.contains(name)) {
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
  final fromBundle = values['--from-bundle'];
  final tagsExport = values['--tags-export'];
  final dumpPair = input != null || datasetVersion != null;
  final bundlePair = fromBundle != null || tagsExport != null;
  if (dumpPair && bundlePair) {
    stderr.writeln(
      '--from-bundle and --tags-export replace --input and --dataset-version; '
      'give one pair.',
    );
    return null;
  }
  if (bundlePair) {
    if (fromBundle == null || tagsExport == null) {
      stderr.writeln('Both --from-bundle and --tags-export are required.');
      return null;
    }
  } else {
    if (input == null || datasetVersion == null) {
      stderr.writeln('Both --input and --dataset-version are required.');
      return null;
    }
    if (!_isDate(datasetVersion)) {
      stderr.writeln('--dataset-version must be a YYYY-MM-DD date.');
      return null;
    }
  }
  return (
    input: input,
    datasetVersion: datasetVersion,
    fromBundle: fromBundle,
    tagsExport: tagsExport,
    aisleLabels: values['--aisle-labels'] ?? aisleLabelsPath,
    aisleSecondOpinions:
        values['--aisle-second-opinions'] ?? aisleSecondOpinionsPath,
    aisleOverrides: values['--aisle-overrides'] ?? aisleOverridesPath,
    aisleInputOnly: aisleInputOnly,
  );
}

/// [ifMissing] when the file does not exist. A file that does not parse, or
/// is not UTF-8, throws a [FormatException] that names the path and keeps the
/// parser's message.
T _readDataFile<T>(
  String path, {
  required T Function(String text) parse,
  required T ifMissing,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    return ifMissing;
  }
  try {
    return parse(utf8.decode(file.readAsBytesSync()));
  } on FormatException catch (error) {
    throw FormatException('$path: ${error.message}');
  }
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

String _percent(double share) => '${(share * 100).toStringAsFixed(1)}%';

String _duration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds % 60;
  return minutes > 0 ? '$minutes min $seconds s' : '$seconds s';
}
