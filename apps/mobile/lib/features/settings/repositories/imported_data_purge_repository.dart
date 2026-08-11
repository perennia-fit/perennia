import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/perennia_api_client.dart';
import '../../../data/local/uuid_v7.dart';
import '../../auth/repositories/auth_repository.dart';

final importedDataPurgeRepositoryProvider =
    Provider<ImportedDataPurgeRepository>((ref) {
  return ApiImportedDataPurgeRepository();
});

typedef ImportedDataPurgeApiClientFactory = PerenniaApiClient Function(
  Uri baseUrl,
);

enum ImportedDataPurgeScope {
  all,
  gpsOnly;

  String get wireName => switch (this) {
        ImportedDataPurgeScope.all => 'all',
        ImportedDataPurgeScope.gpsOnly => 'gpsOnly',
      };
}

abstract interface class ImportedDataPurgeRepository {
  Future<ImportedDataPurgeResponse> purgeGarminImportedData({
    required AuthSession session,
    required ImportedDataPurgeScope scope,
  });
}

class ApiImportedDataPurgeRepository implements ImportedDataPurgeRepository {
  ApiImportedDataPurgeRepository({
    ImportedDataPurgeApiClientFactory? apiClientFactory,
    UuidV7Generator? uuidGenerator,
    DateTime Function()? clock,
  })  : _apiClientFactory = apiClientFactory ?? _defaultApiClient,
        _uuidGenerator = uuidGenerator ?? UuidV7Generator(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final ImportedDataPurgeApiClientFactory _apiClientFactory;
  final UuidV7Generator _uuidGenerator;
  final DateTime Function() _clock;

  @override
  Future<ImportedDataPurgeResponse> purgeGarminImportedData({
    required AuthSession session,
    required ImportedDataPurgeScope scope,
  }) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      return await client.purgeImportedData(
        bearerToken: session.token,
        idempotencyKey: _uuidGenerator.generate(timestamp: _clock().toUtc()),
        source: 'garmin',
        scope: scope.wireName,
      );
    } finally {
      client.close();
    }
  }
}

PerenniaApiClient _defaultApiClient(Uri baseUrl) {
  return PerenniaApiClient(baseUrl: baseUrl);
}
