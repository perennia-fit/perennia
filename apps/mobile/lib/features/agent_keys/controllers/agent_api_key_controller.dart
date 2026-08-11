import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/repositories/auth_repository.dart';
import '../repositories/agent_api_key_repository.dart';

final agentApiKeyControllerProvider =
    AsyncNotifierProvider<AgentApiKeyController, AgentApiKeyState>(
  AgentApiKeyController.new,
);

class AgentApiKeyController extends AsyncNotifier<AgentApiKeyState> {
  @override
  Future<AgentApiKeyState> build() async {
    final authState = await ref.watch(authControllerProvider.future);
    final session = authState.session;
    if (session == null) {
      return AgentApiKeyState();
    }
    final keys = await ref.watch(agentApiKeyRepositoryProvider).list(session);
    return AgentApiKeyState(keys: keys);
  }

  Future<void> refresh() async {
    final session = await _signedInSession();
    final previous = state.value ?? AgentApiKeyState();
    state = const AsyncLoading<AgentApiKeyState>();
    state = await AsyncValue.guard(() async {
      final keys = await ref.read(agentApiKeyRepositoryProvider).list(session);
      return previous.copyWith(keys: keys, clearCreatedKey: true);
    });
  }

  Future<void> createKey(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      return;
    }

    final session = await _signedInSession();
    state = const AsyncLoading<AgentApiKeyState>();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(agentApiKeyRepositoryProvider);
      final created = await repository.create(session: session, name: name);
      final keys = await repository.list(session);
      return AgentApiKeyState(keys: keys, createdKey: created);
    });
  }

  Future<void> revokeKey(String keyId) async {
    final session = await _signedInSession();
    final previous = state.value ?? AgentApiKeyState();
    state = const AsyncLoading<AgentApiKeyState>();
    state = await AsyncValue.guard(() async {
      await ref
          .read(agentApiKeyRepositoryProvider)
          .revoke(session: session, keyId: keyId);
      return previous.copyWith(
        keys: previous.keys.where((key) => key.id != keyId).toList(
              growable: false,
            ),
        clearCreatedKey: true,
      );
    });
  }

  void dismissCreatedSecret() {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData<AgentApiKeyState>(
      current.copyWith(clearCreatedKey: true),
    );
  }

  Future<AuthSession> _signedInSession() async {
    final session = (await ref.read(authControllerProvider.future)).session;
    if (session == null) {
      throw const AgentApiKeyException('Sign in to manage agent keys.');
    }
    return session;
  }
}

@immutable
final class AgentApiKeyState {
  AgentApiKeyState({
    List<AgentApiKeyRecord> keys = const <AgentApiKeyRecord>[],
    this.createdKey,
  }) : keys = List<AgentApiKeyRecord>.unmodifiable(keys);

  final List<AgentApiKeyRecord> keys;
  final CreatedAgentApiKey? createdKey;

  AgentApiKeyState copyWith({
    List<AgentApiKeyRecord>? keys,
    CreatedAgentApiKey? createdKey,
    bool clearCreatedKey = false,
  }) {
    return AgentApiKeyState(
      keys: keys ?? this.keys,
      createdKey: clearCreatedKey ? null : createdKey ?? this.createdKey,
    );
  }
}

class AgentApiKeyException implements Exception {
  const AgentApiKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}
