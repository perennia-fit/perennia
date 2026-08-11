import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/perennia_api_client.dart';
import '../../auth/repositories/auth_repository.dart';

typedef AgentApiClientFactory = PerenniaApiClient Function(
  Uri baseUrl,
);

final agentApiKeyRepositoryProvider = Provider<AgentApiKeyRepository>((ref) {
  return HttpAgentApiKeyRepository();
});

abstract interface class AgentApiKeyRepository {
  Future<List<AgentApiKeyRecord>> list(AuthSession session);

  Future<CreatedAgentApiKey> create({
    required AuthSession session,
    required String name,
  });

  Future<void> revoke({
    required AuthSession session,
    required String keyId,
  });
}

class HttpAgentApiKeyRepository implements AgentApiKeyRepository {
  HttpAgentApiKeyRepository({AgentApiClientFactory? apiClientFactory})
      : _apiClientFactory = apiClientFactory ?? _defaultApiClient;

  final AgentApiClientFactory _apiClientFactory;

  @override
  Future<List<AgentApiKeyRecord>> list(AuthSession session) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      final response = await client.listAgentApiKeys(
        bearerToken: session.token,
      );
      return _activeRecords(response.keys);
    } finally {
      client.close();
    }
  }

  @override
  Future<CreatedAgentApiKey> create({
    required AuthSession session,
    required String name,
  }) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      final response = await client.createAgentApiKey(
        bearerToken: session.token,
        name: name.trim(),
      );
      return CreatedAgentApiKey(
        record: _toRecord(response.key),
        secret: response.secret,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<void> revoke({
    required AuthSession session,
    required String keyId,
  }) async {
    final client = _apiClientFactory(session.serverUrl);
    try {
      await client.revokeAgentApiKey(
        bearerToken: session.token,
        keyId: keyId,
      );
    } finally {
      client.close();
    }
  }
}

class InMemoryAgentApiKeyRepository implements AgentApiKeyRepository {
  InMemoryAgentApiKeyRepository({
    List<AgentApiKeyRecord> initialKeys = const <AgentApiKeyRecord>[],
  }) : _keys = List<AgentApiKeyRecord>.of(initialKeys);

  final List<AgentApiKeyRecord> _keys;
  final createdNames = <String>[];
  final revokedKeyIds = <String>[];
  var _nextKeyNumber = 1;

  List<AgentApiKeyRecord> get keys => List<AgentApiKeyRecord>.unmodifiable(
        _keys.where((key) => !revokedKeyIds.contains(key.id)),
      );

  @override
  Future<List<AgentApiKeyRecord>> list(AuthSession session) async {
    return keys;
  }

  @override
  Future<CreatedAgentApiKey> create({
    required AuthSession session,
    required String name,
  }) async {
    final normalizedName = name.trim();
    createdNames.add(normalizedName);
    final keyNumber = _nextKeyNumber++;
    final record = AgentApiKeyRecord(
      id: 'agent-key-$keyNumber',
      name: normalizedName,
      prefix: 'prn_agent_',
      start: 'start$keyNumber',
      createdAt: DateTime.utc(2026, 6, 24, 7, keyNumber),
      lastUsedAt: null,
    );
    _keys.insert(0, record);
    return CreatedAgentApiKey(
      record: record,
      secret: 'prn_agent_secret_$keyNumber',
    );
  }

  @override
  Future<void> revoke({
    required AuthSession session,
    required String keyId,
  }) async {
    revokedKeyIds.add(keyId);
  }
}

@immutable
class CreatedAgentApiKey {
  const CreatedAgentApiKey({
    required this.record,
    required this.secret,
  });

  final AgentApiKeyRecord record;
  final String secret;
}

@immutable
class AgentApiKeyRecord {
  const AgentApiKeyRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
    this.prefix,
    this.start,
  });

  final String id;
  final String name;
  final String? prefix;
  final String? start;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

List<AgentApiKeyRecord> _activeRecords(List<AgentApiKeyMetadata> keys) {
  return keys
      .where((key) => !key.revoked)
      .map(_toRecord)
      .toList(growable: false);
}

AgentApiKeyRecord _toRecord(AgentApiKeyMetadata key) {
  return AgentApiKeyRecord(
    id: key.id,
    name: key.name,
    prefix: key.prefix,
    start: key.start,
    createdAt: DateTime.parse(key.createdAt).toUtc(),
    lastUsedAt:
        key.lastUsedAt == null ? null : DateTime.parse(key.lastUsedAt!).toUtc(),
  );
}

PerenniaApiClient _defaultApiClient(Uri baseUrl) {
  return PerenniaApiClient(baseUrl: baseUrl);
}
