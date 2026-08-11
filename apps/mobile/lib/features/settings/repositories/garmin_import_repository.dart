import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/perennia_api_client.dart';
import '../../auth/repositories/auth_repository.dart';

typedef GarminImportApiClientFactory = PerenniaApiClient Function(
  Uri baseUrl,
);

final garminImportRepositoryProvider = Provider<GarminImportRepository>((ref) {
  return GarminImportRepository();
});

class GarminImportRepository {
  GarminImportRepository({GarminImportApiClientFactory? apiClientFactory})
      : _apiClientFactory = apiClientFactory ?? _defaultApiClient;

  final GarminImportApiClientFactory _apiClientFactory;

  Future<IntegrationCredentialIssueResponse> createGarminDbCredential({
    required AuthSession session,
  }) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      return await client.createIntegrationImportCredential(
        bearerToken: session.token,
        name: 'GarminDB sync',
        source: 'garmin-garmindb',
      );
    } finally {
      client.close();
    }
  }

  Future<CanonicalImportResponse> uploadGarminFitFile({
    required AuthSession session,
    required String credentialId,
    required List<int> bytes,
    required String filename,
    String? timezone,
  }) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      return await client.importGarminFitFile(
        bearerToken: session.token,
        credentialId: credentialId,
        fitBytes: bytes,
        filename: filename,
        timezone: timezone ?? DateTime.now().toLocal().timeZoneName,
      );
    } finally {
      client.close();
    }
  }
}

PerenniaApiClient _defaultApiClient(Uri baseUrl) {
  return PerenniaApiClient(baseUrl: baseUrl);
}
