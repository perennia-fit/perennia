import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/features/metrics/repositories/monitoring_series_cache_repository.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('MonitoringSeriesCacheRepository', () {
    late AppDatabase database;
    late MonitoringSeriesCacheRepository repository;

    setUp(() {
      database = AppDatabase.inMemory();
      repository = MonitoringSeriesCacheRepository(
        database,
        maxCacheBytes: 8,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('fetches cached blobs and evicts least recently accessed entries',
        () async {
      await repository.put(
        _entry('series-a', <int>[1, 2, 3, 4]),
        fetchedAt: DateTime.utc(2026, 6, 25),
      );
      await repository.put(
        _entry('series-b', <int>[5, 6, 7, 8]),
        fetchedAt: DateTime.utc(2026, 6, 25, 0, 1),
      );

      final cached = await repository.get(
        'series-a',
        accessedAt: DateTime.utc(2026, 6, 25, 0, 2),
      );
      expect(cached, isNotNull);
      expect(cached!.blob, Uint8List.fromList(<int>[1, 2, 3, 4]));

      await repository.put(
        _entry('series-c', <int>[9, 10, 11, 12]),
        fetchedAt: DateTime.utc(2026, 6, 25, 0, 3),
      );

      expect(await repository.get('series-b'), isNull);
      expect(await repository.get('series-a'), isNotNull);
      expect(await repository.get('series-c'), isNotNull);
      expect(await repository.cachedByteLength(), 8);
    });
  });
}

MonitoringSeriesCacheEntry _entry(String seriesId, List<int> bytes) {
  return MonitoringSeriesCacheEntry(
    seriesId: seriesId,
    source: 'garmin',
    externalId: '$seriesId-external',
    seriesType: 'heartRate',
    encoding: 'canonical-series-delta-json-v1',
    compression: 'gzip',
    blob: Uint8List.fromList(bytes),
  );
}
