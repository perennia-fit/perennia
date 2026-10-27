import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/nutrition/nutrition.dart';
import '../../domain/nutrition/open_food_facts.dart';
import '../../features/settings/services/client_crash_reporting.dart';
import '../local/food_reference_database.dart';
import '../open_food_facts/open_food_facts_bundle_installer.dart';
import '../open_food_facts/open_food_facts_client.dart';

export '../open_food_facts/open_food_facts_bundle_installer.dart'
    show BundleStatus;

enum OnlineSearchStatus { ok, noResults, offline, unavailable, disabled }

enum BarcodeLookupOutcome {
  found,
  notFound,
  notABarcode,
  offline,
  unavailable,
  disabled,
}

/// Open Food Facts products for the app: the shipped bundle and the device
/// cache (one row per barcode, in [FoodReferenceDatabase]), plus live lookups
/// the user starts. Live requests go out only when `allowOnline` is true.
///
/// See docs/designs/open-food-facts.md, "Technical Plan".
abstract interface class OpenFoodFactsRepository {
  Future<void> ensureBundleInstalled();

  Stream<BundleStatus> watchBundleStatus();

  Future<BundleHeader?> bundleHeader();

  /// Barcode-candidate matches first, then the FTS5 search, without
  /// duplicates.
  Future<List<PlatformFoodRecord>> searchLocal(String query, {int limit = 50});

  /// One live search. Stores nothing.
  Future<({OnlineSearchStatus status, List<PlatformFoodRecord> products})>
      searchOnline(String query, {required bool allowOnline});

  /// A stored match is returned with `found` and nothing is sent. Otherwise
  /// one live product request; a hit is returned at once and kept in the
  /// background.
  Future<({BarcodeLookupOutcome status, PlatformFoodRecord? product})>
      lookupBarcode(String raw, {required bool allowOnline});

  /// Keeps a live product the user opened. Never throws; a failure only means
  /// the product is not kept.
  Future<void> keepOpenedProduct(PlatformFoodRecord record);

  /// Erase all data: waits for a running install, deletes every product and
  /// the stored hash, then installs the bundle again.
  Future<void> resetDeviceData();
}

class DriftOpenFoodFactsRepository implements OpenFoodFactsRepository {
  /// The app's repository: resolves the file and opens the database lazily on
  /// first use.
  DriftOpenFoodFactsRepository({
    required Future<File> Function() databaseFile,
    required OpenFoodFactsClient client,
    ClientCrashReporter? crashReporter,
  })  : _databaseFile = databaseFile,
        _client = client,
        _crashReporter = crashReporter,
        _asset = const RootBundleAssetSource();

  /// A repository over an in-memory [database]; the installer runs on it
  /// directly, with no isolate.
  DriftOpenFoodFactsRepository.forTesting({
    required FoodReferenceDatabase database,
    required OpenFoodFactsClient client,
    required BundleAssetSource asset,
  })  : _databaseFile = null,
        _client = client,
        _crashReporter = null,
        _asset = asset {
    _opened = Future.value(_attach(database, null));
  }

  final Future<File> Function()? _databaseFile;
  final OpenFoodFactsClient _client;
  final ClientCrashReporter? _crashReporter;
  final BundleAssetSource _asset;

  Future<_Opened>? _opened;

  /// The status is the installer's own; before it exists the repository only
  /// knows whether opening failed (for example, no cache directory).
  OpenFoodFactsBundleInstaller? _installer;
  bool _openFailed = false;

  // Synchronous, so a change is relayed as it happens and a listener added
  // later starts from the right status.
  final StreamController<BundleStatus> _statusChanges =
      StreamController<BundleStatus>.broadcast(sync: true);
  StreamSubscription<BundleStatus>? _installerStatus;

  BundleStatus get _status => _openFailed
      ? BundleStatus.failed
      : _installer?.currentStatus ?? BundleStatus.unknown;

  /// Opens the database and its installer once. A failure sets the status to
  /// `failed`, and later calls see `null`.
  Future<_Opened?> _open() async {
    try {
      return await (_opened ??= () async {
        final file = await _databaseFile!();
        return _attach(FoodReferenceDatabase.connect(file), file);
      }());
    } on Object catch (error, stackTrace) {
      if (!_openFailed) {
        _openFailed = true;
        _announce(BundleStatus.failed);
        unawaited(reportQuietly(_crashReporter, error, stackTrace));
      }
      return null;
    }
  }

  _Opened _attach(FoodReferenceDatabase database, File? file) {
    final installer = _installer = OpenFoodFactsBundleInstaller(
      database: database,
      asset: _asset,
      databaseFile: file,
      crashReporter: _crashReporter,
    );
    _installerStatus = installer.statusChanges.listen(_announce);
    return _Opened(database, installer);
  }

  void _announce(BundleStatus status) {
    if (!_statusChanges.isClosed) {
      _statusChanges.add(status);
    }
  }

  @override
  Future<void> ensureBundleInstalled() async {
    await (await _open())?.installer.ensureInstalled();
  }

  @override
  Stream<BundleStatus> watchBundleStatus() {
    return currentThenChanges(() => _status, _statusChanges.stream);
  }

  @override
  Future<BundleHeader?> bundleHeader() async {
    return (await _open())?.installer.bundleHeader() ??
        readBundleHeaderOrNull(_asset);
  }

  @override
  Future<List<PlatformFoodRecord>> searchLocal(
    String query, {
    int limit = 50,
  }) async {
    final opened = await _open();
    if (opened == null || limit <= 0) {
      return const <PlatformFoodRecord>[];
    }
    final database = opened.database;
    final byCode = await database.productsByCodes(barcodeCandidates(query));
    final match = buildFoodSearchMatch(query);
    final matched = match == null
        ? const <OpenFoodFactsProductRow>[]
        : await database.searchProducts(match, limit);
    final seen = <String>{};
    return [
      for (final row in [...byCode, ...matched])
        if (seen.add(row.code)) toPlatformFoodRecord(productFromRow(row)),
    ].take(limit).toList();
  }

  @override
  Future<({OnlineSearchStatus status, List<PlatformFoodRecord> products})>
      searchOnline(String query, {required bool allowOnline}) async {
    if (!allowOnline) {
      return (
        status: OnlineSearchStatus.disabled,
        products: const <PlatformFoodRecord>[],
      );
    }
    final outcome = await _client.search(query);
    final products = outcome is OpenFoodFactsResults
        ? outcome.products.map(toPlatformFoodRecord).toList()
        : const <PlatformFoodRecord>[];
    return (
      status: switch (outcome) {
        OpenFoodFactsResults() when products.isNotEmpty =>
          OnlineSearchStatus.ok,
        OpenFoodFactsResults() ||
        OpenFoodFactsNotFound() =>
          OnlineSearchStatus.noResults,
        OpenFoodFactsOffline() => OnlineSearchStatus.offline,
        OpenFoodFactsUnavailable() => OnlineSearchStatus.unavailable,
      },
      products: products,
    );
  }

  @override
  Future<({BarcodeLookupOutcome status, PlatformFoodRecord? product})>
      lookupBarcode(String raw, {required bool allowOnline}) async {
    final candidates = barcodeCandidates(raw);
    if (candidates.isEmpty) {
      return (status: BarcodeLookupOutcome.notABarcode, product: null);
    }
    final opened = await _open();
    final stored = opened == null
        ? const <OpenFoodFactsProductRow>[]
        : await opened.database.productsByCodes(candidates);
    if (stored.isNotEmpty) {
      return (
        status: BarcodeLookupOutcome.found,
        product: toPlatformFoodRecord(productFromRow(stored.first)),
      );
    }
    if (!allowOnline) {
      return (status: BarcodeLookupOutcome.disabled, product: null);
    }
    switch (await _client.product(candidates.first)) {
      case OpenFoodFactsResults(:final products) when products.isNotEmpty:
        final product = products.first;
        unawaited(_keep(productCompanion(product, origin: originOnline)));
        return (
          status: BarcodeLookupOutcome.found,
          product: toPlatformFoodRecord(product),
        );
      case OpenFoodFactsResults() || OpenFoodFactsNotFound():
        return (status: BarcodeLookupOutcome.notFound, product: null);
      case OpenFoodFactsOffline():
        return (status: BarcodeLookupOutcome.offline, product: null);
      case OpenFoodFactsUnavailable():
        return (status: BarcodeLookupOutcome.unavailable, product: null);
    }
  }

  @override
  Future<void> keepOpenedProduct(PlatformFoodRecord record) {
    return _keep(
      productCompanion(
        MappedOpenFoodFactsProduct(
          code: record.id,
          name: record.name,
          brand: record.brand,
          isLiquid: record.isLiquid,
          servingLabel: record.servingLabel,
          servingSize: record.servingSize,
          packageSize: record.packageSize,
          nutrientText: nutrientTextFromVector(record.nutrientsPer100),
          modifiedAt: record.sourceModifiedAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          scans: record.scans,
        ),
        origin: originOnline,
      ),
    );
  }

  /// Stores a kept product. During a first install this can wait up to the
  /// 5-second busy timeout; if it still fails, the product is simply not kept.
  Future<void> _keep(OpenFoodFactsProductsCompanion row) async {
    try {
      await (await _open())?.database.keepProduct(row);
    } on Object catch (error, stackTrace) {
      unawaited(reportQuietly(_crashReporter, error, stackTrace));
    }
  }

  @override
  Future<void> resetDeviceData() async {
    final opened = await _open();
    if (opened == null) {
      return;
    }
    await opened.installer.ensureInstalled();
    await opened.database.resetAll();
    await opened.installer.ensureInstalled();
  }

  Future<void> close() async {
    await _installerStatus?.cancel();
    // A controller's close future waits for its listeners; nothing here
    // depends on it.
    unawaited(_statusChanges.close());
    _Opened? opened;
    try {
      opened = await _opened;
    } on Object {
      opened = null;
    }
    if (opened != null) {
      await opened.installer.close();
      await opened.database.close();
    }
  }
}

class _Opened {
  const _Opened(this.database, this.installer);

  final FoodReferenceDatabase database;
  final OpenFoodFactsBundleInstaller installer;
}

/// Installs nothing, finds nothing and sends nothing: for widget tests and the
/// app-shell harness.
class StubOpenFoodFactsRepository implements OpenFoodFactsRepository {
  const StubOpenFoodFactsRepository();

  @override
  Future<void> ensureBundleInstalled() async {}

  @override
  Stream<BundleStatus> watchBundleStatus() => Stream.value(BundleStatus.ready);

  @override
  Future<BundleHeader?> bundleHeader() async => null;

  @override
  Future<List<PlatformFoodRecord>> searchLocal(
    String query, {
    int limit = 50,
  }) async =>
      const <PlatformFoodRecord>[];

  @override
  Future<({OnlineSearchStatus status, List<PlatformFoodRecord> products})>
      searchOnline(String query, {required bool allowOnline}) async => (
            status: OnlineSearchStatus.disabled,
            products: const <PlatformFoodRecord>[]
          );

  @override
  Future<({BarcodeLookupOutcome status, PlatformFoodRecord? product})>
      lookupBarcode(String raw, {required bool allowOnline}) async =>
          (status: BarcodeLookupOutcome.disabled, product: null);

  @override
  Future<void> keepOpenedProduct(PlatformFoodRecord record) async {}

  @override
  Future<void> resetDeviceData() async {}
}

final openFoodFactsRepositoryProvider = Provider<OpenFoodFactsRepository>((
  ref,
) {
  final repository = DriftOpenFoodFactsRepository(
    databaseFile: () async => File(
      p.join(
          (await getApplicationCacheDirectory()).path, 'food_reference.sqlite'),
    ),
    client: OpenFoodFactsClient(httpClient: http.Client()),
    crashReporter: ref.read(clientCrashReporterProvider),
  );
  ref.onDispose(repository.close);
  return repository;
});

final bundleStatusProvider = StreamProvider<BundleStatus>((ref) {
  return ref.watch(openFoodFactsRepositoryProvider).watchBundleStatus();
});

final bundleHeaderProvider = FutureProvider<BundleHeader?>((ref) {
  return ref.watch(openFoodFactsRepositoryProvider).bundleHeader();
});
