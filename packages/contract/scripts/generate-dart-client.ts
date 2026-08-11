import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

type JsonObject = Record<string, unknown>;

type OpenApiOperation = {
  operationId?: string;
  responses?: JsonObject;
};

type OpenApiDocument = {
  paths?: Record<string, Record<string, OpenApiOperation>>;
  components?: {
    schemas?: Record<string, JsonObject>;
  };
};

type ClientOperation = {
  methodName: string;
  path: string;
  pathConstantName: string;
  responseClassName: string;
  responseSchema: JsonObject;
};

type DartProperty = {
  dartType: "String";
  jsonName: string;
  literalValue?: string;
  minLength?: number;
};

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "../../..");
const inputPath = resolve(repoRoot, "packages/contract/openapi.json");
const outputPath = resolve(
  repoRoot,
  "apps/mobile/lib/api/perennia_api_client.dart"
);

const document = JSON.parse(
  await readFile(inputPath, "utf8")
) as OpenApiDocument;
const operations = collectClientOperations(document);
assertAuthOperation(document, "/api/auth/sign-in/email", "post", "signInEmail");
assertAuthOperation(
  document,
  "/api/auth/sign-up/email",
  "post",
  "signUpWithEmailAndPassword"
);
assertAuthOperation(document, "/api/auth/sign-in/social", "post", "socialSignIn");
assertAuthOperation(
  document,
  "/api/auth/send-verification-email",
  "post",
  "sendVerificationEmail"
);
assertAuthOperation(document, "/api/auth/sign-out", "post", "signOut");
assertAuthOperation(document, "/sync/push", "post", "pushSync");
assertAuthOperation(document, "/sync/pull", "post", "pullSync");
assertAuthOperation(
  document,
  "/sync/device-push-token",
  "post",
  "registerDevicePushToken"
);
assertAuthOperation(
  document,
  "/monitoring/series/{seriesId}/blob",
  "get",
  "getMonitoringSeriesBlob"
);
assertAuthOperation(
  document,
  "/account/deletion",
  "post",
  "requestAccountDeletion"
);
assertAuthOperation(
  document,
  "/integrations/imported-data/purge",
  "post",
  "purgeImportedData"
);
assertAuthOperation(
  document,
  "/integrations/import-credentials",
  "post",
  "createIntegrationImportCredential"
);
assertAuthOperation(
  document,
  "/integrations/import-credentials",
  "get",
  "listIntegrationImportCredentials"
);
assertAuthOperation(
  document,
  "/integrations/import-credentials/{credentialId}",
  "delete",
  "revokeIntegrationImportCredential"
);
assertAuthOperation(
  document,
  "/integrations/import-profile",
  "get",
  "getIntegrationImportProfile"
);
assertAuthOperation(
  document,
  "/integrations/garmin/fit-import",
  "post",
  "importGarminFitFile"
);
assertAuthOperation(
  document,
  "/agent/api-keys",
  "post",
  "createAgentApiKey"
);
assertAuthOperation(document, "/agent/api-keys", "get", "listAgentApiKeys");
assertAuthOperation(
  document,
  "/agent/api-keys/{keyId}",
  "delete",
  "revokeAgentApiKey"
);
assertAuthOperation(
  document,
  "/agent/probe",
  "get",
  "getAgentProtectedProbe"
);
assertAuthOperation(
  document,
  "/agent/validate-set",
  "post",
  "validateAgentSet"
);
assertAuthOperation(document, "/agent/exercises", "get", "listAgentExercises");
assertAuthOperation(
  document,
  "/agent/exercises/resolve",
  "get",
  "resolveAgentExerciseName"
);
assertAuthOperation(
  document,
  "/agent/workouts/batch-write",
  "post",
  "batchWriteAgentWorkout"
);
assertAuthOperation(
  document,
  "/agent/analytics/exercises/{exerciseId}",
  "get",
  "getAgentExerciseAnalytics"
);
assertAuthOperation(
  document,
  "/agent/history/sets",
  "get",
  "listAgentHistorySets"
);

if (operations.length === 0) {
  throw new Error("OpenAPI document does not contain client-generatable operations.");
}

const dartSource = `// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated from packages/contract/openapi.json by packages/contract/scripts/generate-dart-client.ts.

import 'dart:convert';

import 'package:http/http.dart' as http;

class PerenniaApiClient {
  PerenniaApiClient({required Uri baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

${operations.map(generatePathConstant).join("\n")}
  static const String signInEmailPath = '/api/auth/sign-in/email';
  static const String signUpWithEmailAndPasswordPath =
      '/api/auth/sign-up/email';
  static const String socialSignInPath = '/api/auth/sign-in/social';
  static const String sendVerificationEmailPath =
      '/api/auth/send-verification-email';
  static const String signOutPath = '/api/auth/sign-out';
  static const String pushSyncPath = '/sync/push';
  static const String pullSyncPath = '/sync/pull';
  static const String devicePushTokenPath = '/sync/device-push-token';
  static const String monitoringSeriesBlobPathTemplate =
      '/monitoring/series/{seriesId}/blob';
  static const String accountDeletionPath = '/account/deletion';
  static const String importedDataPurgePath =
      '/integrations/imported-data/purge';
  static const String integrationImportCredentialsPath =
      '/integrations/import-credentials';
  static const String integrationImportCredentialPathTemplate =
      '/integrations/import-credentials/{credentialId}';
  static const String integrationImportProfilePath =
      '/integrations/import-profile';
  static const String garminFitImportPath =
      '/integrations/garmin/fit-import';
  static const String agentApiKeysPath = '/agent/api-keys';
  static const String agentProtectedProbePath = '/agent/probe';
  static const String agentValidateSetPath = '/agent/validate-set';

  final Uri _baseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

${operations.map(generateClientMethod).join("\n\n")}
${generateAuthClientMethods()}
${generateAgentApiKeyClientMethods()}
${generateSyncClientMethods()}
${generateMonitoringSeriesClientMethods()}
${generateAccountClientMethods()}
${generateImportedDataPurgeClientMethods()}
${generateIntegrationImportClientMethods()}

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}

${operations.map(generateResponseClass).join("\n\n")}
${generateAuthResponseClasses()}
${generateAgentApiKeyClasses()}
${generateSyncClasses()}
${generateMonitoringSeriesClasses()}
${generateAccountClasses()}
${generateImportedDataPurgeClasses()}
${generateIntegrationImportClasses()}

class ApiException implements Exception {
  const ApiException({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, body: $body)';
}
`;

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, dartSource, "utf8");

function collectClientOperations(document: OpenApiDocument): ClientOperation[] {
  const operations: ClientOperation[] = [];

  for (const [path, methods] of Object.entries(document.paths ?? {}).sort()) {
    if (path.startsWith("/api/auth/")) {
      continue;
    }
    if (path.startsWith("/agent/")) {
      continue;
    }
    if (path.startsWith("/monitoring/")) {
      continue;
    }
    if (path.startsWith("/integrations/")) {
      continue;
    }

    const getOperation = methods.get;
    if (getOperation === undefined) {
      continue;
    }

    const methodName = getOperation.operationId;
    if (methodName === undefined) {
      throw new Error(`GET ${path} is missing operationId.`);
    }

    const response = resolveResponseSchema(document, getOperation);
    assertSupportedObjectSchema(response.schemaName, response.schema);
    operations.push({
      methodName,
      path,
      pathConstantName: `${methodName}Path`,
      responseClassName: response.schemaName,
      responseSchema: response.schema
    });
  }

  return operations;
}

function assertAuthOperation(
  document: OpenApiDocument,
  path: string,
  method: string,
  operationId: string
) {
  const operation = document.paths?.[path]?.[method];
  if (operation?.operationId !== operationId) {
    throw new Error(`${method.toUpperCase()} ${path} must expose ${operationId}.`);
  }
}

function generatePathConstant(operation: ClientOperation): string {
  return `  static const String ${operation.pathConstantName} = '${escapeDartString(
    operation.path
  )}';`;
}

function generateClientMethod(operation: ClientOperation): string {
  return `  Future<${operation.responseClassName}> ${operation.methodName}() async {
    final response = await _httpClient.get(
      _baseUrl.resolve(${operation.pathConstantName}),
      headers: const {'accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return ${operation.responseClassName}.fromJson(decoded);
  }`;
}

function generateSyncClientMethods(): string {
  return `
  Future<SyncPushResponse> pushSync({
    required String bearerToken,
    required int protocolVersion,
    required String deviceId,
    required String entity,
    required List<SyncPushChange> changes,
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(pushSyncPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'protocolVersion': protocolVersion,
        'deviceId': deviceId,
        'entity': entity,
        'changes': changes.map((change) => change.toJson()).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return SyncPushResponse.fromJson(decoded);
  }

  Future<SyncPullResponse> pullSync({
    required String bearerToken,
    required int protocolVersion,
    required String? cursor,
    required int limit,
    String mode = 'delta',
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(pullSyncPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'protocolVersion': protocolVersion,
        'cursor': cursor,
        'limit': limit,
        if (mode != 'delta') 'mode': mode,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return SyncPullResponse.fromJson(decoded);
  }

  Future<DevicePushTokenRegistrationResponse> registerDevicePushToken({
    required String bearerToken,
    required String deviceId,
    required String platform,
    required String token,
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(devicePushTokenPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'deviceId': deviceId,
        'platform': platform,
        'token': token,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return DevicePushTokenRegistrationResponse.fromJson(decoded);
  }`;
}

function generateMonitoringSeriesClientMethods(): string {
  return `
  Future<MonitoringSeriesBlobResponse> getMonitoringSeriesBlob({
    required String bearerToken,
    required String seriesId,
  }) async {
    final encodedSeriesId = Uri.encodeComponent(seriesId);
    final path = monitoringSeriesBlobPathTemplate.replaceFirst(
      '{seriesId}',
      encodedSeriesId,
    );
    final response = await _httpClient.get(
      _baseUrl.resolve(path),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return MonitoringSeriesBlobResponse.fromJson(decoded);
  }`;
}

function generateAccountClientMethods(): string {
  return `
  Future<AccountDeletionResponse> requestAccountDeletion({
    required String bearerToken,
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(accountDeletionPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AccountDeletionResponse.fromJson(decoded);
  }`;
}

function generateImportedDataPurgeClientMethods(): string {
  return `
  Future<ImportedDataPurgeResponse> purgeImportedData({
    required String bearerToken,
    required String idempotencyKey,
    String source = 'garmin',
    required String scope,
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(importedDataPurgePath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'idempotencyKey': idempotencyKey,
        'source': source,
        'scope': scope,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return ImportedDataPurgeResponse.fromJson(decoded);
  }`;
}

function generateIntegrationImportClientMethods(): string {
  return `
  Future<IntegrationCredentialIssueResponse> createIntegrationImportCredential({
    required String bearerToken,
    required String name,
    String source = 'garmin-garmindb',
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(integrationImportCredentialsPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'name': name,
        'source': source,
      }),
    );

    if (response.statusCode != 201) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return IntegrationCredentialIssueResponse.fromJson(decoded);
  }

  Future<IntegrationCredentialListResponse> listIntegrationImportCredentials({
    required String bearerToken,
  }) async {
    final response = await _httpClient.get(
      _baseUrl.resolve(integrationImportCredentialsPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return IntegrationCredentialListResponse.fromJson(decoded);
  }

  Future<IntegrationCredentialRevokeResponse> revokeIntegrationImportCredential({
    required String bearerToken,
    required String credentialId,
  }) async {
    final path = integrationImportCredentialPathTemplate.replaceFirst(
      '{credentialId}',
      Uri.encodeComponent(credentialId),
    );
    final response = await _httpClient.delete(
      _baseUrl.resolve(path),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return IntegrationCredentialRevokeResponse.fromJson(decoded);
  }

  Future<IntegrationImportProfileResponse> getIntegrationImportProfile({
    required String bearerToken,
  }) async {
    final response = await _httpClient.get(
      _baseUrl.resolve(integrationImportProfilePath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return IntegrationImportProfileResponse.fromJson(decoded);
  }

  Future<CanonicalImportResponse> importGarminFitFile({
    required String bearerToken,
    required List<int> fitBytes,
    required String timezone,
    String? credentialId,
    String? idempotencyKey,
    String filename = 'garmin.fit',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _baseUrl.resolve(garminFitImportPath),
    );
    request.headers.addAll(<String, String>{
      'accept': 'application/json',
      'authorization': 'Bearer $bearerToken',
    });
    request.fields['timezone'] = timezone;
    if (credentialId != null) {
      request.fields['credentialId'] = credentialId;
    }
    if (idempotencyKey != null) {
      request.fields['idempotencyKey'] = idempotencyKey;
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fitBytes,
        filename: filename,
      ),
    );

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return CanonicalImportResponse.fromJson(decoded);
  }`;
}

function generateAuthClientMethods(): string {
  return `
  Future<AuthSignInResponse> signInEmail({
    required String email,
    required String password,
    String? callbackURL,
    bool? rememberMe,
  }) async {
    final decoded = await _postJson(
      signInEmailPath,
      <String, Object?>{
        'email': email,
        'password': password,
        'callbackURL': callbackURL,
        'rememberMe': rememberMe,
      },
    );

    return AuthSignInResponse.fromJson(decoded);
  }

  Future<AuthSignUpResponse> signUpWithEmailAndPassword({
    required String name,
    required String email,
    required String password,
    String? callbackURL,
    bool? rememberMe,
  }) async {
    final decoded = await _postJson(
      signUpWithEmailAndPasswordPath,
      <String, Object?>{
        'name': name,
        'email': email,
        'password': password,
        'callbackURL': callbackURL,
        'rememberMe': rememberMe,
      },
    );

    return AuthSignUpResponse.fromJson(decoded);
  }

  Future<SocialSignInResponse> socialSignIn({
    required String provider,
    String? callbackURL,
    String? errorCallbackURL,
    bool? disableRedirect,
    SocialIdToken? idToken,
  }) async {
    final decoded = await _postJson(
      socialSignInPath,
      <String, Object?>{
        'provider': provider,
        'callbackURL': callbackURL,
        'errorCallbackURL': errorCallbackURL,
        'disableRedirect': disableRedirect,
        'idToken': idToken?.toJson(),
      },
    );

    return SocialSignInResponse.fromJson(decoded);
  }

  Future<SendVerificationEmailResponse> sendVerificationEmail({
    required String email,
    String? callbackURL,
  }) async {
    final decoded = await _postJson(
      sendVerificationEmailPath,
      <String, Object?>{
        'email': email,
        'callbackURL': callbackURL,
      },
    );

    return SendVerificationEmailResponse.fromJson(decoded);
  }

  Future<AuthSignOutResponse> signOut({required String bearerToken}) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(signOutPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{}),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AuthSignOutResponse.fromJson(decoded);
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(path),
      headers: const {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: jsonEncode(_withoutNullValues(body)),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return decoded;
  }`;
}

function generateAgentApiKeyClientMethods(): string {
  return `
  Future<AgentApiKeyCreateResponse> createAgentApiKey({
    required String bearerToken,
    required String name,
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(agentApiKeysPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'name': name}),
    );

    if (response.statusCode != 201) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AgentApiKeyCreateResponse.fromJson(decoded);
  }

  Future<AgentApiKeyListResponse> listAgentApiKeys({
    required String bearerToken,
  }) async {
    final response = await _httpClient.get(
      _baseUrl.resolve(agentApiKeysPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AgentApiKeyListResponse.fromJson(decoded);
  }

  Future<AgentApiKeyRevokeResponse> revokeAgentApiKey({
    required String bearerToken,
    required String keyId,
  }) async {
    final response = await _httpClient.delete(
      _baseUrl.resolve('/agent/api-keys/\${Uri.encodeComponent(keyId)}'),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AgentApiKeyRevokeResponse.fromJson(decoded);
  }

  Future<AgentApiKeyProtectedProbeResponse> getAgentProtectedProbe({
    required String bearerToken,
  }) async {
    final response = await _httpClient.get(
      _baseUrl.resolve(agentProtectedProbePath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AgentApiKeyProtectedProbeResponse.fromJson(decoded);
  }

  Future<AgentSetValidationResponse> validateAgentSet({
    required String bearerToken,
    required List<String> exerciseDimensions,
    String loadMode = 'added',
    Map<String, AgentSetDimensionValue> values =
        const <String, AgentSetDimensionValue>{},
    Object? rpe,
    String? side,
  }) async {
    final response = await _httpClient.post(
      _baseUrl.resolve(agentValidateSetPath),
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer $bearerToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'exercise': <String, Object?>{
          'dimensions': exerciseDimensions,
          'loadMode': loadMode,
        },
        'values': values.map(
          (name, value) => MapEntry<String, Object?>(name, value.toJson()),
        ),
        if (rpe != null) 'rpe': rpe,
        if (side != null) 'side': side,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }

    return AgentSetValidationResponse.fromJson(decoded);
  }`;
}

function generateResponseClass(operation: ClientOperation): string {
  const properties = readDartProperties(operation.responseClassName, operation.responseSchema);
  const constructorParameters = properties
    .map((property) => `required this.${property.jsonName}`)
    .join(", ");
  const fields = properties
    .map((property) => `  final ${property.dartType} ${property.jsonName};`)
    .join("\n");
  const readers = properties.map(generatePropertyReader).join("\n\n");
  const returnValues = properties
    .map((property) => {
      if (property.literalValue !== undefined) {
        return `${property.jsonName}: '${escapeDartString(property.literalValue)}'`;
      }

      return `${property.jsonName}: ${property.jsonName}`;
    })
    .join(", ");
  const jsonEntries = properties
    .map((property) => `'${escapeDartString(property.jsonName)}': ${property.jsonName}`)
    .join(", ");

  return `class ${operation.responseClassName} {
  const ${operation.responseClassName}({${constructorParameters}});

  factory ${operation.responseClassName}.fromJson(Map<String, Object?> json) {
${indent(readers, 4)}

    return ${operation.responseClassName}(${returnValues});
  }

${fields}

  Map<String, Object?> toJson() => {${jsonEntries}};
}`;
}

function generateAuthResponseClasses(): string {
  return `
class AuthSignInResponse {
  const AuthSignInResponse({
    required this.redirect,
    required this.token,
    required this.user,
    this.url,
  });

  factory AuthSignInResponse.fromJson(Map<String, Object?> json) {
    final redirect = json['redirect'];
    if (redirect is! bool) {
      throw const FormatException('Expected redirect to be a boolean.');
    }

    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Expected token to be a non-empty string.');
    }

    final user = json['user'];
    if (user is! Map<String, Object?>) {
      throw const FormatException('Expected user to be an object.');
    }

    final url = json['url'];
    if (url != null && url is! String) {
      throw const FormatException('Expected url to be a string.');
    }

    return AuthSignInResponse(
      redirect: redirect,
      token: token,
      user: AuthUser.fromJson(user),
      url: url as String?,
    );
  }

  final bool redirect;
  final String token;
  final AuthUser user;
  final String? url;
}

class AuthSignUpResponse {
  const AuthSignUpResponse({required this.user, this.token});

  factory AuthSignUpResponse.fromJson(Map<String, Object?> json) {
    final token = json['token'];
    if (token != null && token is! String) {
      throw const FormatException('Expected token to be a string.');
    }

    final user = json['user'];
    if (user is! Map<String, Object?>) {
      throw const FormatException('Expected user to be an object.');
    }

    return AuthSignUpResponse(
      token: token as String?,
      user: AuthUser.fromJson(user),
    );
  }

  final String? token;
  final AuthUser user;
}

class SocialSignInResponse {
  const SocialSignInResponse({
    required this.redirect,
    this.token,
    this.url,
    this.user,
  });

  factory SocialSignInResponse.fromJson(Map<String, Object?> json) {
    final redirect = json['redirect'];
    if (redirect is! bool) {
      throw const FormatException('Expected redirect to be a boolean.');
    }

    final token = json['token'];
    if (token != null && token is! String) {
      throw const FormatException('Expected token to be a string.');
    }

    final url = json['url'];
    if (url != null && url is! String) {
      throw const FormatException('Expected url to be a string.');
    }

    final user = json['user'];
    if (user != null && user is! Map<String, Object?>) {
      throw const FormatException('Expected user to be an object.');
    }

    return SocialSignInResponse(
      redirect: redirect,
      token: token as String?,
      url: url as String?,
      user:
          user == null ? null : AuthUser.fromJson(user as Map<String, Object?>),
    );
  }

  final bool redirect;
  final String? token;
  final String? url;
  final AuthUser? user;
}

class SendVerificationEmailResponse {
  const SendVerificationEmailResponse({required this.status});

  factory SendVerificationEmailResponse.fromJson(Map<String, Object?> json) {
    final status = json['status'];
    if (status is! bool) {
      throw const FormatException('Expected status to be a boolean.');
    }

    return SendVerificationEmailResponse(status: status);
  }

  final bool status;
}

class AuthSignOutResponse {
  const AuthSignOutResponse({required this.success});

  factory AuthSignOutResponse.fromJson(Map<String, Object?> json) {
    final success = json['success'];
    if (success is! bool) {
      throw const FormatException('Expected success to be a boolean.');
    }

    return AuthSignOutResponse(success: success);
  }

  final bool success;
}

class SocialIdToken {
  const SocialIdToken({
    required this.token,
    this.accessToken,
    this.nonce,
  });

  final String token;
  final String? accessToken;
  final String? nonce;

  Map<String, Object?> toJson() => _withoutNullValues(<String, Object?>{
        'token': token,
        'accessToken': accessToken,
        'nonce': nonce,
      });
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.emailVerified,
    this.image,
  });

  factory AuthUser.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Expected user.id to be a non-empty string.');
    }

    final email = json['email'];
    if (email is! String || email.isEmpty) {
      throw const FormatException(
          'Expected user.email to be a non-empty string.');
    }

    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException(
          'Expected user.name to be a non-empty string.');
    }

    final emailVerified = json['emailVerified'];
    if (emailVerified is! bool) {
      throw const FormatException(
          'Expected user.emailVerified to be a boolean.');
    }

    final image = json['image'];
    if (image != null && image is! String) {
      throw const FormatException('Expected user.image to be a string.');
    }

    return AuthUser(
      id: id,
      email: email,
      name: name,
      emailVerified: emailVerified,
      image: image as String?,
    );
  }

  final String id;
  final String email;
  final String name;
  final bool emailVerified;
  final String? image;
}

Map<String, Object?> _withoutNullValues(Map<String, Object?> input) {
  return <String, Object?>{
    for (final entry in input.entries)
      if (entry.value != null)
        entry.key: entry.value is Map<String, Object?>
            ? _withoutNullValues(entry.value! as Map<String, Object?>)
            : entry.value,
      };
}`;
}

function generateAgentApiKeyClasses(): string {
  return `
class AgentApiKeyCreateResponse {
  const AgentApiKeyCreateResponse({
    required this.key,
    required this.secret,
  });

  factory AgentApiKeyCreateResponse.fromJson(Map<String, Object?> json) {
    final key = json['key'];
    if (key is! Map<String, Object?>) {
      throw const FormatException('Expected key to be an object.');
    }

    final secret = json['secret'];
    if (secret is! String || secret.isEmpty) {
      throw const FormatException('Expected secret to be a non-empty string.');
    }

    return AgentApiKeyCreateResponse(
      key: AgentApiKeyMetadata.fromJson(key),
      secret: secret,
    );
  }

  final AgentApiKeyMetadata key;
  final String secret;
}

class AgentApiKeyListResponse {
  AgentApiKeyListResponse({
    required List<AgentApiKeyMetadata> keys,
  }) : keys = List<AgentApiKeyMetadata>.unmodifiable(keys);

  factory AgentApiKeyListResponse.fromJson(Map<String, Object?> json) {
    final keys = json['keys'];
    if (keys is! List<Object?>) {
      throw const FormatException('Expected keys to be a list.');
    }

    return AgentApiKeyListResponse(
      keys: keys
          .map((key) {
            if (key is! Map<String, Object?>) {
              throw const FormatException('Expected key to be an object.');
            }
            return AgentApiKeyMetadata.fromJson(key);
          })
          .toList(growable: false),
    );
  }

  final List<AgentApiKeyMetadata> keys;
}

class AgentApiKeyMetadata {
  const AgentApiKeyMetadata({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.revoked,
    this.prefix,
    this.start,
    this.lastUsedAt,
  });

  factory AgentApiKeyMetadata.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Expected id to be a non-empty string.');
    }

    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Expected name to be a non-empty string.');
    }

    final prefix = json['prefix'];
    if (prefix != null && prefix is! String) {
      throw const FormatException('Expected prefix to be a string or null.');
    }

    final start = json['start'];
    if (start != null && start is! String) {
      throw const FormatException('Expected start to be a string or null.');
    }

    final createdAt = json['createdAt'];
    if (createdAt is! String || createdAt.isEmpty) {
      throw const FormatException(
          'Expected createdAt to be a non-empty string.');
    }

    final lastUsedAt = json['lastUsedAt'];
    if (lastUsedAt != null && lastUsedAt is! String) {
      throw const FormatException('Expected lastUsedAt to be a string or null.');
    }

    final revoked = json['revoked'];
    if (revoked is! bool) {
      throw const FormatException('Expected revoked to be a boolean.');
    }

    return AgentApiKeyMetadata(
      id: id,
      name: name,
      prefix: prefix as String?,
      start: start as String?,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt as String?,
      revoked: revoked,
    );
  }

  final String id;
  final String name;
  final String? prefix;
  final String? start;
  final String createdAt;
  final String? lastUsedAt;
  final bool revoked;
}

class AgentApiKeyRevokeResponse {
  const AgentApiKeyRevokeResponse({required this.revoked});

  factory AgentApiKeyRevokeResponse.fromJson(Map<String, Object?> json) {
    final revoked = json['revoked'];
    if (revoked != true) {
      throw const FormatException('Expected revoked to be true.');
    }

    return const AgentApiKeyRevokeResponse(revoked: true);
  }

  final bool revoked;
}

class AgentApiKeyProtectedProbeResponse {
  const AgentApiKeyProtectedProbeResponse({
    required this.authenticated,
    required this.userId,
    required this.keyId,
    this.keyName,
  });

  factory AgentApiKeyProtectedProbeResponse.fromJson(
      Map<String, Object?> json) {
    final authenticated = json['authenticated'];
    if (authenticated != true) {
      throw const FormatException('Expected authenticated to be true.');
    }

    final userId = json['userId'];
    if (userId is! String || userId.isEmpty) {
      throw const FormatException('Expected userId to be a non-empty string.');
    }

    final keyId = json['keyId'];
    if (keyId is! String || keyId.isEmpty) {
      throw const FormatException('Expected keyId to be a non-empty string.');
    }

    final keyName = json['keyName'];
    if (keyName != null && keyName is! String) {
      throw const FormatException('Expected keyName to be a string or null.');
    }

    return AgentApiKeyProtectedProbeResponse(
      authenticated: true,
      userId: userId,
      keyId: keyId,
      keyName: keyName as String?,
    );
  }

  final bool authenticated;
  final String userId;
  final String keyId;
  final String? keyName;
}

class AgentSetDimensionValue {
  const AgentSetDimensionValue({
    required this.entered,
    required this.unit,
  });

  final String entered;
  final String unit;

  Map<String, Object?> toJson() => <String, Object?>{
        'entered': entered,
        'unit': unit,
      };
}

class AgentSetValidationResponse {
  AgentSetValidationResponse({
    required this.accepted,
    required List<AgentSetValidationIssue> warnings,
    required this.limits,
  }) : warnings = List<AgentSetValidationIssue>.unmodifiable(warnings);

  factory AgentSetValidationResponse.fromJson(Map<String, Object?> json) {
    final accepted = json['accepted'];
    if (accepted != true) {
      throw const FormatException('Expected accepted to be true.');
    }

    final warnings = json['warnings'];
    if (warnings is! List<Object?>) {
      throw const FormatException('Expected warnings to be a list.');
    }

    final limits = json['limits'];
    if (limits is! Map<String, Object?>) {
      throw const FormatException('Expected limits to be an object.');
    }

    return AgentSetValidationResponse(
      accepted: true,
      warnings: warnings
          .map((warning) {
            if (warning is! Map<String, Object?>) {
              throw const FormatException('Expected warning to be an object.');
            }
            return AgentSetValidationIssue.fromJson(warning);
          })
          .toList(growable: false),
      limits: AgentSetValidationLimits.fromJson(limits),
    );
  }

  final bool accepted;
  final List<AgentSetValidationIssue> warnings;
  final AgentSetValidationLimits limits;
}

class AgentSetValidationIssue {
  const AgentSetValidationIssue({
    required this.field,
    required this.dimension,
    required this.rule,
    required this.message,
    required this.limit,
  });

  factory AgentSetValidationIssue.fromJson(Map<String, Object?> json) {
    final field = json['field'];
    if (field is! String || field.isEmpty) {
      throw const FormatException('Expected field to be a non-empty string.');
    }

    final dimension = json['dimension'];
    if (dimension != null && dimension is! String) {
      throw const FormatException('Expected dimension to be a string or null.');
    }

    final rule = json['rule'];
    if (rule is! String || rule.isEmpty) {
      throw const FormatException('Expected rule to be a non-empty string.');
    }

    final message = json['message'];
    if (message is! String || message.isEmpty) {
      throw const FormatException('Expected message to be a non-empty string.');
    }

    final limit = json['limit'];
    if (limit != null && limit is! num && limit is! String) {
      throw const FormatException('Expected limit to be a number, string, or null.');
    }

    return AgentSetValidationIssue(
      field: field,
      dimension: dimension as String?,
      rule: rule,
      message: message,
      limit: limit,
    );
  }

  final String field;
  final String? dimension;
  final String rule;
  final String message;
  final Object? limit;
}

class AgentSetValidationLimits {
  AgentSetValidationLimits({
    required this.numericMin,
    required this.maxDecimalPlaces,
    required this.loadMaxKilograms,
    required this.loadMaxDecimalPlaces,
    required this.addedLoadWarnKilograms,
    required this.assistedLoadWarnKilograms,
    required this.repsMax,
    required this.repsWarnAbove,
    required this.durationMaxSeconds,
    required this.durationWarnAboveSeconds,
    required this.distanceMaxKilometers,
    required this.distanceWarnAboveKilometers,
    required this.rpeMin,
    required this.rpeMax,
    required this.rpeStep,
    required this.speedWarnAboveKilometersPerHour,
    required List<String> allowedSides,
  }) : allowedSides = List<String>.unmodifiable(allowedSides);

  factory AgentSetValidationLimits.fromJson(Map<String, Object?> json) {
    final allowedSides = json['allowedSides'];
    if (allowedSides is! List<Object?> ||
        allowedSides.any((value) => value is! String || value.isEmpty)) {
      throw const FormatException('Expected allowedSides to be strings.');
    }

    return AgentSetValidationLimits(
      numericMin: _readNum(json, 'numericMin'),
      maxDecimalPlaces: _readNum(json, 'maxDecimalPlaces'),
      loadMaxKilograms: _readNum(json, 'loadMaxKilograms'),
      loadMaxDecimalPlaces: _readNum(json, 'loadMaxDecimalPlaces'),
      addedLoadWarnKilograms: _readNum(json, 'addedLoadWarnKilograms'),
      assistedLoadWarnKilograms: _readNum(json, 'assistedLoadWarnKilograms'),
      repsMax: _readNum(json, 'repsMax'),
      repsWarnAbove: _readNum(json, 'repsWarnAbove'),
      durationMaxSeconds: _readNum(json, 'durationMaxSeconds'),
      durationWarnAboveSeconds: _readNum(json, 'durationWarnAboveSeconds'),
      distanceMaxKilometers: _readNum(json, 'distanceMaxKilometers'),
      distanceWarnAboveKilometers: _readNum(json, 'distanceWarnAboveKilometers'),
      rpeMin: _readNum(json, 'rpeMin'),
      rpeMax: _readNum(json, 'rpeMax'),
      rpeStep: _readNum(json, 'rpeStep'),
      speedWarnAboveKilometersPerHour:
          _readNum(json, 'speedWarnAboveKilometersPerHour'),
      allowedSides: allowedSides.cast<String>(),
    );
  }

  final num numericMin;
  final num maxDecimalPlaces;
  final num loadMaxKilograms;
  final num loadMaxDecimalPlaces;
  final num addedLoadWarnKilograms;
  final num assistedLoadWarnKilograms;
  final num repsMax;
  final num repsWarnAbove;
  final num durationMaxSeconds;
  final num durationWarnAboveSeconds;
  final num distanceMaxKilometers;
  final num distanceWarnAboveKilometers;
  final num rpeMin;
  final num rpeMax;
  final num rpeStep;
  final num speedWarnAboveKilometersPerHour;
  final List<String> allowedSides;
}

num _readNum(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('Expected $key to be a number.');
  }

  return value;
}
`;
}

function generateAccountClasses(): string {
  return `
class AccountDeletionResponse {
  const AccountDeletionResponse({
    required this.deletionRequestedAt,
    required this.localReplicaPreserved,
  });

  factory AccountDeletionResponse.fromJson(Map<String, Object?> json) {
    final deletionRequestedAt = json['deletionRequestedAt'];
    if (deletionRequestedAt is! String || deletionRequestedAt.isEmpty) {
      throw const FormatException(
        'Expected deletionRequestedAt to be a non-empty string.',
      );
    }

    final localReplicaPreserved = json['localReplicaPreserved'];
    if (localReplicaPreserved != true) {
      throw const FormatException(
        'Expected localReplicaPreserved to be true.',
      );
    }

    return AccountDeletionResponse(
      deletionRequestedAt: deletionRequestedAt,
      localReplicaPreserved: true,
    );
  }

  final String deletionRequestedAt;
  final bool localReplicaPreserved;

  Map<String, Object?> toJson() => <String, Object?>{
        'deletionRequestedAt': deletionRequestedAt,
        'localReplicaPreserved': localReplicaPreserved,
      };
}
`;
}

function generateImportedDataPurgeClasses(): string {
  return `
class ImportedDataPurgeResponse {
  const ImportedDataPurgeResponse({
    required this.accepted,
    required this.duplicate,
    required this.batchId,
    required this.serverClock,
    required this.source,
    required this.scope,
    required this.tombstonedCounts,
  });

  factory ImportedDataPurgeResponse.fromJson(Map<String, Object?> json) {
    final accepted = json['accepted'];
    if (accepted != true) {
      throw const FormatException('Expected accepted to be true.');
    }

    final duplicate = json['duplicate'];
    if (duplicate is! bool) {
      throw const FormatException('Expected duplicate to be a boolean.');
    }

    final batchId = _readNonEmptyString(json, 'batchId');
    final serverClock = _readNonEmptyString(json, 'serverClock');
    final source = _readNonEmptyString(json, 'source');
    final scope = _readNonEmptyString(json, 'scope');
    final tombstonedCounts = json['tombstonedCounts'];
    if (tombstonedCounts is! Map<String, Object?>) {
      throw const FormatException('Expected tombstonedCounts to be an object.');
    }

    return ImportedDataPurgeResponse(
      accepted: true,
      duplicate: duplicate,
      batchId: batchId,
      serverClock: serverClock,
      source: source,
      scope: scope,
      tombstonedCounts:
          ImportedDataPurgeCounts.fromJson(tombstonedCounts),
    );
  }

  final bool accepted;
  final bool duplicate;
  final String batchId;
  final String serverClock;
  final String source;
  final String scope;
  final ImportedDataPurgeCounts tombstonedCounts;
}

class ImportedDataPurgeCounts {
  const ImportedDataPurgeCounts({
    required this.externalActivities,
    required this.metricReadings,
    required this.monitoringSeries,
    required this.materializedSets,
    required this.activityLinks,
  });

  factory ImportedDataPurgeCounts.fromJson(Map<String, Object?> json) {
    return ImportedDataPurgeCounts(
      externalActivities: _readNonNegativeInt(json, 'externalActivities'),
      metricReadings: _readNonNegativeInt(json, 'metricReadings'),
      monitoringSeries: _readNonNegativeInt(json, 'monitoringSeries'),
      materializedSets: _readNonNegativeInt(json, 'materializedSets'),
      activityLinks: _readNonNegativeInt(json, 'activityLinks'),
    );
  }

  final int externalActivities;
  final int metricReadings;
  final int monitoringSeries;
  final int materializedSets;
  final int activityLinks;
}

String _readNonEmptyString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected $key to be a non-empty string.');
  }
  return value;
}

int _readNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('Expected $key to be a non-negative integer.');
  }
  return value;
}
`;
}

function generateIntegrationImportClasses(): string {
  return `
class IntegrationCredentialIssueResponse {
  const IntegrationCredentialIssueResponse({
    required this.credential,
    required this.secret,
  });

  factory IntegrationCredentialIssueResponse.fromJson(
      Map<String, Object?> json) {
    final credential = _integrationObject(json, 'credential');
    final secret = _integrationString(json, 'secret');
    return IntegrationCredentialIssueResponse(
      credential: IntegrationCredentialMetadata.fromJson(credential),
      secret: secret,
    );
  }

  final IntegrationCredentialMetadata credential;
  final String secret;
}

class IntegrationCredentialListResponse {
  const IntegrationCredentialListResponse({required this.credentials});

  factory IntegrationCredentialListResponse.fromJson(
      Map<String, Object?> json) {
    return IntegrationCredentialListResponse(
      credentials: _integrationObjectList(json, 'credentials')
          .map(IntegrationCredentialMetadata.fromJson)
          .toList(growable: false),
    );
  }

  final List<IntegrationCredentialMetadata> credentials;
}

class IntegrationCredentialRevokeResponse {
  const IntegrationCredentialRevokeResponse({required this.revoked});

  factory IntegrationCredentialRevokeResponse.fromJson(
      Map<String, Object?> json) {
    final revoked = json['revoked'];
    if (revoked != true) {
      throw const FormatException('Expected revoked to be true.');
    }
    return const IntegrationCredentialRevokeResponse(revoked: true);
  }

  final bool revoked;
}

class IntegrationCredentialMetadata {
  const IntegrationCredentialMetadata({
    required this.id,
    required this.source,
    required this.name,
    required this.createdAt,
    required this.revoked,
    required this.scope,
    this.prefix,
    this.start,
    this.lastUsedAt,
  });

  factory IntegrationCredentialMetadata.fromJson(Map<String, Object?> json) {
    final prefix = json['prefix'];
    if (prefix != null && prefix is! String) {
      throw const FormatException('Expected prefix to be a string or null.');
    }
    final start = json['start'];
    if (start != null && start is! String) {
      throw const FormatException('Expected start to be a string or null.');
    }
    final lastUsedAt = json['lastUsedAt'];
    if (lastUsedAt != null && lastUsedAt is! String) {
      throw const FormatException('Expected lastUsedAt to be a string or null.');
    }
    final revoked = json['revoked'];
    if (revoked is! bool) {
      throw const FormatException('Expected revoked to be a boolean.');
    }

    return IntegrationCredentialMetadata(
      id: _integrationString(json, 'id'),
      source: _integrationString(json, 'source'),
      name: _integrationString(json, 'name'),
      prefix: prefix as String?,
      start: start as String?,
      createdAt: _integrationString(json, 'createdAt'),
      lastUsedAt: lastUsedAt as String?,
      revoked: revoked,
      scope: _integrationObject(json, 'scope'),
    );
  }

  final String id;
  final String source;
  final String name;
  final String? prefix;
  final String? start;
  final String createdAt;
  final String? lastUsedAt;
  final bool revoked;
  final Map<String, Object?> scope;
}

class IntegrationImportProfileResponse {
  const IntegrationImportProfileResponse({
    required this.credential,
    required this.dataClasses,
    required this.enabledDataClasses,
    required this.fitImportEnabled,
    required this.manualFitImport,
  });

  factory IntegrationImportProfileResponse.fromJson(
      Map<String, Object?> json) {
    final fitImportEnabled = json['fitImportEnabled'];
    if (fitImportEnabled is! bool) {
      throw const FormatException(
          'Expected fitImportEnabled to be a boolean.');
    }

    final enabledDataClasses = json['enabledDataClasses'];
    if (enabledDataClasses is! List<Object?> ||
        enabledDataClasses.any((item) => item is! String)) {
      throw const FormatException(
          'Expected enabledDataClasses to be a string list.');
    }

    return IntegrationImportProfileResponse(
      credential: IntegrationImportProfileCredential.fromJson(
        _integrationObject(json, 'credential'),
      ),
      dataClasses: _integrationObjectList(json, 'dataClasses')
          .map(IntegrationImportDataClassAccess.fromJson)
          .toList(growable: false),
      enabledDataClasses: enabledDataClasses.cast<String>(),
      fitImportEnabled: fitImportEnabled,
      manualFitImport: IntegrationManualFitImport.fromJson(
        _integrationObject(json, 'manualFitImport'),
      ),
    );
  }

  final IntegrationImportProfileCredential credential;
  final List<IntegrationImportDataClassAccess> dataClasses;
  final List<String> enabledDataClasses;
  final bool fitImportEnabled;
  final IntegrationManualFitImport manualFitImport;
}

class IntegrationImportProfileCredential {
  const IntegrationImportProfileCredential({
    required this.id,
    required this.name,
    required this.source,
  });

  factory IntegrationImportProfileCredential.fromJson(
      Map<String, Object?> json) {
    return IntegrationImportProfileCredential(
      id: _integrationString(json, 'id'),
      name: _integrationString(json, 'name'),
      source: _integrationString(json, 'source'),
    );
  }

  final String id;
  final String name;
  final String source;
}

class IntegrationImportDataClassAccess {
  const IntegrationImportDataClassAccess({
    required this.dataClass,
    required this.enabled,
  });

  factory IntegrationImportDataClassAccess.fromJson(
      Map<String, Object?> json) {
    final enabled = json['enabled'];
    if (enabled is! bool) {
      throw const FormatException('Expected enabled to be a boolean.');
    }
    return IntegrationImportDataClassAccess(
      dataClass: _integrationString(json, 'dataClass'),
      enabled: enabled,
    );
  }

  final String dataClass;
  final bool enabled;
}

class IntegrationManualFitImport {
  const IntegrationManualFitImport({
    required this.enabled,
    required this.uploadPath,
  });

  factory IntegrationManualFitImport.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    if (enabled != true) {
      throw const FormatException('Expected manual FIT import to be enabled.');
    }
    return IntegrationManualFitImport(
      enabled: true,
      uploadPath: _integrationString(json, 'uploadPath'),
    );
  }

  final bool enabled;
  final String uploadPath;
}

class CanonicalImportResponse {
  const CanonicalImportResponse({
    required this.accepted,
    required this.duplicate,
    required this.idempotencyKey,
    required this.batchId,
    required this.serverClock,
    required this.activities,
    required this.metricReadings,
    required this.seriesAccepted,
    required this.reviewFlags,
    required this.materializedWorkouts,
    required this.activityLinks,
    required this.activityLinkSuggestions,
  });

  factory CanonicalImportResponse.fromJson(Map<String, Object?> json) {
    final accepted = json['accepted'];
    if (accepted != true) {
      throw const FormatException('Expected accepted to be true.');
    }
    final duplicate = json['duplicate'];
    if (duplicate is! bool) {
      throw const FormatException('Expected duplicate to be a boolean.');
    }

    return CanonicalImportResponse(
      accepted: true,
      duplicate: duplicate,
      idempotencyKey: _integrationString(json, 'idempotencyKey'),
      batchId: _integrationString(json, 'batchId'),
      serverClock: _integrationString(json, 'serverClock'),
      activities: _integrationObjectList(json, 'activities'),
      metricReadings: _integrationObjectList(json, 'metricReadings'),
      seriesAccepted: _integrationNonNegativeInt(json, 'seriesAccepted'),
      reviewFlags: _integrationObjectList(json, 'reviewFlags'),
      materializedWorkouts:
          _integrationObjectList(json, 'materializedWorkouts'),
      activityLinks: _integrationObjectList(json, 'activityLinks'),
      activityLinkSuggestions:
          _integrationObjectList(json, 'activityLinkSuggestions'),
    );
  }

  final bool accepted;
  final bool duplicate;
  final String idempotencyKey;
  final String batchId;
  final String serverClock;
  final List<Map<String, Object?>> activities;
  final List<Map<String, Object?>> metricReadings;
  final int seriesAccepted;
  final List<Map<String, Object?>> reviewFlags;
  final List<Map<String, Object?>> materializedWorkouts;
  final List<Map<String, Object?>> activityLinks;
  final List<Map<String, Object?>> activityLinkSuggestions;
}

String _integrationString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected $key to be a non-empty string.');
  }
  return value;
}

int _integrationNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('Expected $key to be a non-negative integer.');
  }
  return value;
}

Map<String, Object?> _integrationObject(
    Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $key to be an object.');
  }
  return value;
}

List<Map<String, Object?>> _integrationObjectList(
    Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('Expected $key to be a list.');
  }
  return value
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw FormatException('Expected $key items to be objects.');
        }
        return item;
      })
      .toList(growable: false);
}
`;
}

function generateSyncClasses(): string {
  return `
class DevicePushTokenRegistrationResponse {
  const DevicePushTokenRegistrationResponse({
    required this.registered,
  });

  factory DevicePushTokenRegistrationResponse.fromJson(
      Map<String, Object?> json) {
    final registered = json['registered'];
    if (registered is! bool) {
      throw const FormatException('Expected registered to be a boolean.');
    }

    return DevicePushTokenRegistrationResponse(registered: registered);
  }

  final bool registered;
}

class SyncPushChange {
  const SyncPushChange({
    required this.id,
    required this.payload,
    required this.updatedAt,
    required this.activityLogId,
    required this.actor,
    required this.batchId,
    required this.beforeImage,
    required this.afterImage,
    required this.occurredAt,
    this.deletedAt,
  });

  final String id;
  final Map<String, Object?> payload;
  final String updatedAt;
  final String? deletedAt;
  final String activityLogId;
  final String actor;
  final String batchId;
  final Map<String, Object?>? beforeImage;
  final Map<String, Object?>? afterImage;
  final String occurredAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'payload': payload,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
        'activityLogId': activityLogId,
        'actor': actor,
        'batchId': batchId,
        'beforeImage': beforeImage,
        'afterImage': afterImage,
        'occurredAt': occurredAt,
      };
}

class SyncPushResponse {
  const SyncPushResponse({
    required this.protocolVersion,
    required this.accepted,
    required this.serverClock,
    required this.applied,
  });

  factory SyncPushResponse.fromJson(Map<String, Object?> json) {
    final protocolVersion = json['protocolVersion'];
    if (protocolVersion is! int) {
      throw const FormatException('Expected protocolVersion to be an integer.');
    }

    final accepted = json['accepted'];
    if (accepted is! List<Object?> ||
        accepted.any((value) => value is! String || value.isEmpty)) {
      throw const FormatException('Expected accepted to be a list of ids.');
    }

    final serverClock = json['serverClock'];
    if (serverClock is! String || serverClock.isEmpty) {
      throw const FormatException(
          'Expected serverClock to be a non-empty string.');
    }

    final applied = json['applied'];
    if (applied is! List<Object?>) {
      throw const FormatException('Expected applied to be a list.');
    }

    return SyncPushResponse(
      protocolVersion: protocolVersion,
      accepted: accepted.cast<String>(),
      serverClock: serverClock,
      applied: applied
          .map((change) {
            if (change is! Map<String, Object?>) {
              throw const FormatException(
                  'Expected applied change to be an object.');
            }
            return SyncAppliedChange.fromJson(change);
          })
          .toList(growable: false),
    );
  }

  final int protocolVersion;
  final List<String> accepted;
  final String serverClock;
  final List<SyncAppliedChange> applied;
}

class SyncAppliedChange {
  const SyncAppliedChange({
    required this.id,
    required this.updatedAt,
    required this.deviceId,
  });

  factory SyncAppliedChange.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Expected id to be a non-empty string.');
    }

    final updatedAt = json['updatedAt'];
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw const FormatException(
          'Expected updatedAt to be a non-empty string.');
    }

    final deviceId = json['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const FormatException(
          'Expected deviceId to be a non-empty string.');
    }

    return SyncAppliedChange(
      id: id,
      updatedAt: updatedAt,
      deviceId: deviceId,
    );
  }

  final String id;
  final String updatedAt;
  final String deviceId;
}

class SyncPulledChange {
  const SyncPulledChange({
    required this.entity,
    required this.id,
    required this.deviceId,
    required this.payload,
    required this.updatedAt,
    this.deletedAt,
    this.activityLogId,
    this.actor,
    this.batchId,
    this.beforeImage,
    this.afterImage,
    this.occurredAt,
  });

  factory SyncPulledChange.fromJson(Map<String, Object?> json) {
    final entity = json['entity'];
    if (entity is! String || entity.isEmpty) {
      throw const FormatException('Expected entity to be a non-empty string.');
    }

    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Expected id to be a non-empty string.');
    }

    final deviceId = json['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const FormatException(
          'Expected deviceId to be a non-empty string.');
    }

    final payload = json['payload'];
    if (payload is! Map<String, Object?>) {
      throw const FormatException('Expected payload to be an object.');
    }

    final updatedAt = json['updatedAt'];
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw const FormatException(
          'Expected updatedAt to be a non-empty string.');
    }

    final deletedAt = json['deletedAt'];
    if (deletedAt != null && deletedAt is! String) {
      throw const FormatException('Expected deletedAt to be a string or null.');
    }

    const envelopeFields = <String>[
      'activityLogId',
      'actor',
      'batchId',
      'beforeImage',
      'afterImage',
      'occurredAt',
    ];
    final providedEnvelopeFieldCount =
        envelopeFields.where(json.containsKey).length;
    if (providedEnvelopeFieldCount != 0 &&
        providedEnvelopeFieldCount != envelopeFields.length) {
      throw const FormatException(
        'Expected activity-log sync metadata as a complete envelope.',
      );
    }

    final activityLogId = json['activityLogId'];
    if (activityLogId != null &&
        (activityLogId is! String || activityLogId.isEmpty)) {
      throw const FormatException(
          'Expected activityLogId to be a non-empty string.');
    }

    final actor = json['actor'];
    if (actor != null && (actor is! String || actor.isEmpty)) {
      throw const FormatException('Expected actor to be a non-empty string.');
    }

    final batchId = json['batchId'];
    if (batchId != null && (batchId is! String || batchId.isEmpty)) {
      throw const FormatException('Expected batchId to be a non-empty string.');
    }

    final beforeImage = json['beforeImage'];
    if (beforeImage != null && beforeImage is! Map<String, Object?>) {
      throw const FormatException(
          'Expected beforeImage to be an object or null.');
    }

    final afterImage = json['afterImage'];
    if (afterImage != null && afterImage is! Map<String, Object?>) {
      throw const FormatException(
          'Expected afterImage to be an object or null.');
    }

    final occurredAt = json['occurredAt'];
    if (occurredAt != null && (occurredAt is! String || occurredAt.isEmpty)) {
      throw const FormatException(
          'Expected occurredAt to be a non-empty string.');
    }

    return SyncPulledChange(
      entity: entity,
      id: id,
      deviceId: deviceId,
      payload: payload,
      updatedAt: updatedAt,
      deletedAt: deletedAt as String?,
      activityLogId: activityLogId as String?,
      actor: actor as String?,
      batchId: batchId as String?,
      beforeImage: beforeImage as Map<String, Object?>?,
      afterImage: afterImage as Map<String, Object?>?,
      occurredAt: occurredAt as String?,
    );
  }

  final String entity;
  final String id;
  final String deviceId;
  final Map<String, Object?> payload;
  final String updatedAt;
  final String? deletedAt;
  final String? activityLogId;
  final String? actor;
  final String? batchId;
  final Map<String, Object?>? beforeImage;
  final Map<String, Object?>? afterImage;
  final String? occurredAt;
}

class SyncPullResponse {
  const SyncPullResponse({
    required this.protocolVersion,
    required this.fullResyncRequired,
    required this.changes,
    required this.nextCursor,
    required this.serverClock,
  });

  factory SyncPullResponse.fromJson(Map<String, Object?> json) {
    final protocolVersion = json['protocolVersion'];
    if (protocolVersion is! int) {
      throw const FormatException('Expected protocolVersion to be an integer.');
    }

    final fullResyncRequired = json['fullResyncRequired'];
    if (fullResyncRequired != null && fullResyncRequired is! bool) {
      throw const FormatException(
          'Expected fullResyncRequired to be a boolean.');
    }

    final changes = json['changes'];
    if (changes is! List<Object?>) {
      throw const FormatException('Expected changes to be a list.');
    }

    final nextCursor = json['nextCursor'];
    if (nextCursor != null && nextCursor is! String) {
      throw const FormatException('Expected nextCursor to be a string or null.');
    }

    final serverClock = json['serverClock'];
    if (serverClock is! String || serverClock.isEmpty) {
      throw const FormatException(
          'Expected serverClock to be a non-empty string.');
    }

    return SyncPullResponse(
      protocolVersion: protocolVersion,
      fullResyncRequired: fullResyncRequired as bool? ?? false,
      changes: changes
          .map((change) {
            if (change is! Map<String, Object?>) {
              throw const FormatException('Expected change to be an object.');
            }
            return SyncPulledChange.fromJson(change);
          })
          .toList(growable: false),
      nextCursor: nextCursor as String?,
      serverClock: serverClock,
    );
  }

  final int protocolVersion;
  final bool fullResyncRequired;
  final List<SyncPulledChange> changes;
  final String? nextCursor;
  final String serverClock;
}`;
}

function generateMonitoringSeriesClasses(): string {
  return `
class MonitoringSeriesBlobResponse {
  const MonitoringSeriesBlobResponse({
    required this.seriesId,
    required this.source,
    required this.externalId,
    required this.seriesType,
    required this.externalActivityId,
    required this.sampleCount,
    required this.encoding,
    required this.compression,
    required this.sha256,
    required this.uncompressedByteLength,
    required this.compressedByteLength,
    required this.blobBase64,
    required this.updatedAt,
  });

  factory MonitoringSeriesBlobResponse.fromJson(Map<String, Object?> json) {
    final seriesId = json['seriesId'];
    if (seriesId is! String || seriesId.isEmpty) {
      throw const FormatException('Expected seriesId to be a non-empty string.');
    }

    final source = json['source'];
    if (source is! String || source.isEmpty) {
      throw const FormatException('Expected source to be a non-empty string.');
    }

    final externalId = json['externalId'];
    if (externalId is! String || externalId.isEmpty) {
      throw const FormatException(
        'Expected externalId to be a non-empty string.',
      );
    }

    final seriesType = json['seriesType'];
    if (seriesType is! String || seriesType.isEmpty) {
      throw const FormatException(
        'Expected seriesType to be a non-empty string.',
      );
    }

    final externalActivityId = json['externalActivityId'];
    if (externalActivityId != null &&
        (externalActivityId is! String || externalActivityId.isEmpty)) {
      throw const FormatException(
        'Expected externalActivityId to be a non-empty string or null.',
      );
    }

    final sampleCount = json['sampleCount'];
    if (sampleCount is! int || sampleCount < 1) {
      throw const FormatException('Expected sampleCount to be a positive int.');
    }

    final encoding = json['encoding'];
    if (encoding != 'canonical-series-delta-json-v1') {
      throw const FormatException(
        'Expected encoding to be canonical-series-delta-json-v1.',
      );
    }

    final compression = json['compression'];
    if (compression != 'gzip') {
      throw const FormatException('Expected compression to be gzip.');
    }

    final sha256 = json['sha256'];
    if (sha256 is! String || sha256.isEmpty) {
      throw const FormatException('Expected sha256 to be a non-empty string.');
    }

    final uncompressedByteLength = json['uncompressedByteLength'];
    if (uncompressedByteLength is! int || uncompressedByteLength < 1) {
      throw const FormatException(
        'Expected uncompressedByteLength to be a positive int.',
      );
    }

    final compressedByteLength = json['compressedByteLength'];
    if (compressedByteLength is! int || compressedByteLength < 1) {
      throw const FormatException(
        'Expected compressedByteLength to be a positive int.',
      );
    }

    final blobBase64 = json['blobBase64'];
    if (blobBase64 is! String || blobBase64.isEmpty) {
      throw const FormatException(
        'Expected blobBase64 to be a non-empty string.',
      );
    }

    final updatedAt = json['updatedAt'];
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw const FormatException('Expected updatedAt to be a non-empty string.');
    }

    return MonitoringSeriesBlobResponse(
      seriesId: seriesId,
      source: source,
      externalId: externalId,
      seriesType: seriesType,
      externalActivityId: externalActivityId as String?,
      sampleCount: sampleCount,
      encoding: encoding as String,
      compression: compression as String,
      sha256: sha256,
      uncompressedByteLength: uncompressedByteLength,
      compressedByteLength: compressedByteLength,
      blobBase64: blobBase64,
      updatedAt: updatedAt,
    );
  }

  final String seriesId;
  final String source;
  final String externalId;
  final String seriesType;
  final String? externalActivityId;
  final int sampleCount;
  final String encoding;
  final String compression;
  final String sha256;
  final int uncompressedByteLength;
  final int compressedByteLength;
  final String blobBase64;
  final String updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'seriesId': seriesId,
        'source': source,
        'externalId': externalId,
        'seriesType': seriesType,
        'externalActivityId': externalActivityId,
        'sampleCount': sampleCount,
        'encoding': encoding,
        'compression': compression,
        'sha256': sha256,
        'uncompressedByteLength': uncompressedByteLength,
        'compressedByteLength': compressedByteLength,
        'blobBase64': blobBase64,
        'updatedAt': updatedAt,
      };
}
`;
}

function generatePropertyReader(property: DartProperty): string {
  const valueRead = `final ${property.jsonName} = json['${escapeDartString(
    property.jsonName
  )}'];`;

  if (property.literalValue !== undefined) {
    return `${valueRead}
if (${property.jsonName} != '${escapeDartString(property.literalValue)}') {
  throw FormatException('Expected ${property.jsonName} to be ${escapeDartString(
    property.literalValue
  )}, got $${property.jsonName}.');
}`;
  }

  const minLengthCheck =
    property.minLength !== undefined && property.minLength > 0
      ? ` || ${property.jsonName}.isEmpty`
      : "";

  return `${valueRead}
if (${property.jsonName} is! String${minLengthCheck}) {
  throw const FormatException('Expected ${property.jsonName} to be a non-empty string.');
}`;
}

function resolveResponseSchema(
  document: OpenApiDocument,
  operation: OpenApiOperation
): { schemaName: string; schema: JsonObject } {
  const responses = operation.responses ?? {};
  const okResponse = getObject(responses, "200");
  const content = getObject(okResponse, "content");
  const jsonContent = getObject(content, "application/json");
  const schema = getObject(jsonContent, "schema");
  return resolveSchema(document, schema);
}

function resolveSchema(
  document: OpenApiDocument,
  schema: JsonObject
): { schemaName: string; schema: JsonObject } {
  const reference = getOptionalString(schema, "$ref");
  if (reference === undefined) {
    throw new Error("Response schemas must be component references.");
  }

  const prefix = "#/components/schemas/";
  if (!reference.startsWith(prefix)) {
    throw new Error(`Unsupported schema reference: ${reference}`);
  }

  const schemaName = reference.slice(prefix.length);
  const resolved = document.components?.schemas?.[schemaName];
  if (resolved === undefined) {
    throw new Error(`Missing schema reference target: ${reference}`);
  }

  return { schemaName, schema: resolved };
}

function assertSupportedObjectSchema(schemaName: string, schema: JsonObject) {
  if (schema.type !== "object") {
    throw new Error(`${schemaName} must be an object schema.`);
  }

  readDartProperties(schemaName, schema);
}

function readDartProperties(schemaName: string, schema: JsonObject): DartProperty[] {
  const properties = getObject(schema, "properties");
  const required = getStringArray(schema, "required");
  const result: DartProperty[] = [];

  for (const propertyName of Object.keys(properties).sort()) {
    if (!required.includes(propertyName)) {
      throw new Error(`${schemaName}.${propertyName} must be required.`);
    }

    const propertySchema = getObject(properties, propertyName);
    const literalValue = getOptionalLiteralString(propertySchema);
    const type = getOptionalString(propertySchema, "type");

    if (literalValue === undefined && type !== "string") {
      throw new Error(`${schemaName}.${propertyName} must be a string schema.`);
    }

    result.push({
      dartType: "String",
      jsonName: propertyName,
      literalValue,
      minLength: getOptionalNumber(propertySchema, "minLength")
    });
  }

  return result;
}

function getObject(source: unknown, key: string): JsonObject {
  if (!isObject(source)) {
    throw new Error(`Expected an object before reading ${key}.`);
  }

  const value = source[key];
  if (!isObject(value)) {
    throw new Error(`Expected ${key} to be an object.`);
  }

  return value;
}

function getStringArray(source: JsonObject, key: string): string[] {
  const value = source[key];
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new Error(`Expected ${key} to be a string array.`);
  }

  return value;
}

function getOptionalLiteralString(source: JsonObject): string | undefined {
  const constValue = source.const;
  if (typeof constValue === "string") {
    return constValue;
  }

  const enumValue = source.enum;
  if (
    Array.isArray(enumValue) &&
    enumValue.length === 1 &&
    typeof enumValue[0] === "string"
  ) {
    return enumValue[0];
  }

  return undefined;
}

function getOptionalString(source: JsonObject, key: string): string | undefined {
  const value = source[key];
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new Error(`Expected ${key} to be a string.`);
  }

  return value;
}

function getOptionalNumber(source: JsonObject, key: string): number | undefined {
  const value = source[key];
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "number") {
    throw new Error(`Expected ${key} to be a number.`);
  }

  return value;
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function indent(value: string, spaces: number): string {
  const prefix = " ".repeat(spaces);
  return value
    .split("\n")
    .map((line) => (line.length === 0 ? "" : `${prefix}${line}`))
    .join("\n");
}

function escapeDartString(value: string): string {
  return value.replaceAll("\\", "\\\\").replaceAll("'", "\\'");
}
