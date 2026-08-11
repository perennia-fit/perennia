import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/repositories/training_repositories.dart';

const defaultMonitoringSeriesCacheBytes = 25 * 1024 * 1024;

final monitoringSeriesCacheRepositoryProvider =
    Provider<MonitoringSeriesCacheRepository>((ref) {
  return MonitoringSeriesCacheRepository(ref.watch(appDatabaseProvider));
});

class MonitoringSeriesCacheRepository {
  MonitoringSeriesCacheRepository(
    this._database, {
    int maxCacheBytes = defaultMonitoringSeriesCacheBytes,
    DateTime Function()? clock,
  })  : assert(maxCacheBytes >= 0),
        _maxCacheBytes = maxCacheBytes,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final int _maxCacheBytes;
  final DateTime Function() _clock;

  Future<void> put(
    MonitoringSeriesCacheEntry entry, {
    DateTime? fetchedAt,
  }) async {
    final timestamp = (fetchedAt ?? _clock()).toUtc();
    await _database
        .into(_database.monitoringSeriesCache)
        .insertOnConflictUpdate(
          MonitoringSeriesCacheCompanion.insert(
            seriesId: entry.seriesId,
            source: entry.source,
            externalId: entry.externalId,
            seriesType: entry.seriesType,
            encoding: entry.encoding,
            compression: entry.compression,
            blobData: entry.blob,
            byteLength: entry.blob.lengthInBytes,
            fetchedAt: timestamp,
            lastAccessedAt: timestamp,
          ),
        );
    await evictToBudget();
  }

  Future<MonitoringSeriesCacheEntry?> get(
    String seriesId, {
    DateTime? accessedAt,
  }) async {
    final row = await (_database.select(_database.monitoringSeriesCache)
          ..where((cache) => cache.seriesId.equals(seriesId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }

    final timestamp = (accessedAt ?? _clock()).toUtc();
    await (_database.update(_database.monitoringSeriesCache)
          ..where((cache) => cache.seriesId.equals(seriesId)))
        .write(
      MonitoringSeriesCacheCompanion(
        lastAccessedAt: Value<DateTime>(timestamp),
      ),
    );

    return MonitoringSeriesCacheEntry.fromRow(row);
  }

  Future<void> evictToBudget() async {
    final rows = await (_database.select(_database.monitoringSeriesCache)
          ..orderBy([
            (cache) => OrderingTerm.asc(cache.lastAccessedAt),
            (cache) => OrderingTerm.asc(cache.fetchedAt),
            (cache) => OrderingTerm.asc(cache.seriesId),
          ]))
        .get();
    var totalBytes = rows.fold<int>(
      0,
      (total, row) => total + row.byteLength,
    );

    for (final row in rows) {
      if (totalBytes <= _maxCacheBytes) {
        break;
      }
      await (_database.delete(_database.monitoringSeriesCache)
            ..where((cache) => cache.seriesId.equals(row.seriesId)))
          .go();
      totalBytes -= row.byteLength;
    }
  }

  Future<int> cachedByteLength() async {
    final rows = await _database.select(_database.monitoringSeriesCache).get();
    return rows.fold<int>(0, (total, row) => total + row.byteLength);
  }

  Future<void> clear() {
    return _database.delete(_database.monitoringSeriesCache).go();
  }
}

class MonitoringSeriesCacheEntry {
  const MonitoringSeriesCacheEntry({
    required this.seriesId,
    required this.source,
    required this.externalId,
    required this.seriesType,
    required this.encoding,
    required this.compression,
    required this.blob,
  });

  final String seriesId;
  final String source;
  final String externalId;
  final String seriesType;
  final String encoding;
  final String compression;
  final Uint8List blob;

  int get byteLength => blob.lengthInBytes;

  static MonitoringSeriesCacheEntry fromRow(MonitoringSeriesCacheRow row) {
    return MonitoringSeriesCacheEntry(
      seriesId: row.seriesId,
      source: row.source,
      externalId: row.externalId,
      seriesType: row.seriesType,
      encoding: row.encoding,
      compression: row.compression,
      blob: row.blobData,
    );
  }
}
