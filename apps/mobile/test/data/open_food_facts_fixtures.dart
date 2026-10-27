import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_bundle_installer.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// Small Open Food Facts bundles and products for the reference-database,
/// installer and repository tests.
MappedOpenFoodFactsProduct offProduct(
  String code,
  String name, {
  String? brand,
  int modifiedAt = 1760000000,
  int scans = 1,
  Map<NutrientId, String> nutrients = const <NutrientId, String>{
    NutrientId.energy: '100',
  },
}) {
  return MappedOpenFoodFactsProduct(
    code: code,
    name: name,
    brand: brand,
    isLiquid: false,
    servingLabel: null,
    servingSize: null,
    packageSize: null,
    nutrientText: nutrients,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      modifiedAt * 1000,
      isUtc: true,
    ),
    scans: scans,
  );
}

BundleHeader bundleHeader({
  required String contentHash,
  required int productCount,
  int formatVersion = bundleFormatVersion,
}) {
  return BundleHeader(
    format: bundleFormat,
    formatVersion: formatVersion,
    datasetVersion: '2026-10-26',
    contentHash: contentHash,
    sourceName: 'Open Food Facts',
    sourceUrl: 'https://world.openfoodfacts.org/',
    licenseName: 'Open Database License (ODbL) 1.0',
    licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    contentsLicenseUrl: 'https://opendatacommons.org/licenses/dbcl/1-0/',
    attributionText: 'Contains information from Open Food Facts.',
    countries: const <String>['au'],
    perCountryLimit: 10000,
    productCount: productCount,
  );
}

/// The product lines for [products], sorted by code as the builder writes them.
List<String> bundleLines(List<MappedOpenFoodFactsProduct> products) {
  final sorted = [...products]..sort((a, b) => a.code.compareTo(b.code));
  return [for (final product in sorted) encodeBundleProductLine(product)];
}

/// A gzip bundle file's bytes.
Uint8List bundleBytes(
  List<MappedOpenFoodFactsProduct> products, {
  String contentHash = 'hash-1',
  int formatVersion = bundleFormatVersion,
}) {
  final lines = bundleLines(products);
  final header = bundleHeader(
    contentHash: contentHash,
    productCount: lines.length,
    formatVersion: formatVersion,
  );
  final text = '${header.toJsonLine()}\n${lines.map((l) => '$l\n').join()}';
  return Uint8List.fromList(gzip.encode(utf8.encode(text)));
}

class FixtureBundleAsset implements BundleAssetSource {
  FixtureBundleAsset(this.bytes);

  Uint8List bytes;
  int loads = 0;

  @override
  Future<Uint8List> load() async {
    loads += 1;
    return bytes;
  }
}

class ThrowingBundleAsset implements BundleAssetSource {
  const ThrowingBundleAsset();

  @override
  Future<Uint8List> load() async => throw StateError('no asset');
}

Future<List<OpenFoodFactsProductRow>> allProducts(
  FoodReferenceDatabase database,
) {
  return (database.select(database.openFoodFactsProducts)
        ..orderBy([(table) => OrderingTerm.asc(table.code)]))
      .get();
}
