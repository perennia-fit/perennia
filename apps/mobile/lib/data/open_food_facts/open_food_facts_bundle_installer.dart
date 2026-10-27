import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../../domain/nutrition/open_food_facts.dart';
import '../../features/settings/services/client_crash_reporting.dart';
import '../local/food_reference_database.dart';

const openFoodFactsBundleAssetPath =
    'assets/seeds/open_food_facts_bundle.ndjson.gz';

/// Where the installer reads the bundle's bytes; tests pass a fixture.
abstract interface class BundleAssetSource {
  Future<Uint8List> load();
}

class RootBundleAssetSource implements BundleAssetSource {
  const RootBundleAssetSource();

  @override
  Future<Uint8List> load() async {
    final data = await rootBundle.load(openFoodFactsBundleAssetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

enum BundleStatus { unknown, installing, ready, failed }

/// Installs the shipped bundle into [FoodReferenceDatabase] when its content
/// hash differs from the stored one. The UI isolate reads the asset once and
/// decodes only the header line; the install itself runs in `Isolate.run`
/// on its own WAL connection, in one transaction, so a killed install leaves
/// the previous state and the next start runs it again (CUJ 9).
///
/// Nothing here throws: every failure sets [BundleStatus.failed] and goes to
/// the opt-in crash reporter, and the next app start tries again.
///
/// See docs/designs/open-food-facts.md, "Installing the bundle on the device".
class OpenFoodFactsBundleInstaller {
  OpenFoodFactsBundleInstaller({
    required FoodReferenceDatabase database,
    required BundleAssetSource asset,
    File? databaseFile,
    ClientCrashReporter? crashReporter,
  })  : _database = database,
        _asset = asset,
        _databaseFile = databaseFile,
        _crashReporter = crashReporter;

  final FoodReferenceDatabase _database;
  final BundleAssetSource _asset;
  final File? _databaseFile;
  final ClientCrashReporter? _crashReporter;

  // Synchronous, so a relay (the repository) holds the new status as soon as
  // it is set, and a listener added later starts from the right one.
  final StreamController<BundleStatus> _changes =
      StreamController<BundleStatus>.broadcast(sync: true);
  BundleStatus _status = BundleStatus.unknown;
  Future<void>? _running;

  BundleStatus get currentStatus => _status;

  /// Each change only, delivered synchronously as it happens; for a relay
  /// that keeps its own copy of [currentStatus].
  Stream<BundleStatus> get statusChanges => _changes.stream;

  /// The current status first, then each change.
  Stream<BundleStatus> watchStatus() {
    return Stream<BundleStatus>.multi((controller) {
      controller.add(_status);
      final subscription = _changes.stream.listen(
        controller.add,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  /// Installs the bundle if needed. A call while an install runs returns that
  /// install's future.
  Future<void> ensureInstalled() {
    return _running ??= _install().whenComplete(() => _running = null);
  }

  /// The asset's header, or `null` when it cannot be read.
  Future<BundleHeader?> bundleHeader() async {
    try {
      return readBundleHeader(await _asset.load());
    } on Object {
      return null;
    }
  }

  Future<void> _install() async {
    try {
      final bytes = await _asset.load();
      final header = readBundleHeader(bytes);
      if (header.format != bundleFormat ||
          header.formatVersion != bundleFormatVersion) {
        throw FormatException(
          'Unsupported bundle ${header.format} v${header.formatVersion}.',
        );
      }
      final storedHash = await _database.metaValue(bundleContentHashKey);
      if (storedHash == header.contentHash) {
        _setStatus(BundleStatus.ready);
        return;
      }

      _setStatus(BundleStatus.installing);
      final file = _databaseFile;
      if (file == null) {
        await _database.replaceBundle(bundleProductLines(bytes), header);
      } else {
        await _spawnInstall(file.path, bytes, header);
      }
      _setStatus(BundleStatus.ready);
    } on Object catch (error, stackTrace) {
      _setStatus(BundleStatus.failed);
      unawaited(_reportFailure(error, stackTrace));
    }
  }

  Future<void> _reportFailure(Object error, StackTrace stackTrace) async {
    try {
      await _crashReporter?.captureException(error, stackTrace);
    } on Object {
      // Reporting is best effort; the status already says the install failed.
    }
  }

  void _setStatus(BundleStatus status) {
    _status = status;
    _changes.add(status);
  }

  /// Ends the status streams. The controller's close future waits for its
  /// listeners, so it is not awaited.
  Future<void> close() async {
    unawaited(_changes.close());
  }
}

/// Starts the install isolate from a top-level function, so the closure it
/// sends captures only these three sendable values, never the installer.
Future<void> _spawnInstall(String path, Uint8List bytes, BundleHeader header) {
  return Isolate.run(() => _installInIsolate(path, bytes, header));
}

/// Runs on the install isolate: its own connection, closed before returning.
Future<void> _installInIsolate(
  String path,
  Uint8List bytes,
  BundleHeader header,
) async {
  final database = FoodReferenceDatabase.openInIsolate(File(path));
  try {
    await database.replaceBundle(bundleProductLines(bytes), header);
  } finally {
    await database.close();
  }
}

/// Decodes only the start of the gzip stream, up to the end of the header
/// line, so the UI isolate never inflates the whole bundle.
BundleHeader readBundleHeader(Uint8List bytes) {
  final output = _ByteCollector();
  final input = gzip.decoder.startChunkedConversion(output);
  const chunkSize = 4096;
  for (var start = 0; start < bytes.length; start += chunkSize) {
    final end =
        start + chunkSize < bytes.length ? start + chunkSize : bytes.length;
    input.addSlice(bytes, start, end, false);
    final newline = output.bytes.indexOf(0x0A);
    if (newline >= 0) {
      return BundleHeader.fromJsonLine(
        utf8.decode(output.bytes.sublist(0, newline)),
      );
    }
  }
  throw const FormatException('The bundle has no header line.');
}

/// The product lines: every line after the header, without newlines.
List<String> bundleProductLines(Uint8List bytes) {
  final lines = const LineSplitter().convert(utf8.decode(gzip.decode(bytes)));
  return lines.length <= 1 ? const <String>[] : lines.sublist(1);
}

class _ByteCollector implements Sink<List<int>> {
  final List<int> bytes = [];

  @override
  void add(List<int> data) => bytes.addAll(data);

  @override
  void close() {}
}
