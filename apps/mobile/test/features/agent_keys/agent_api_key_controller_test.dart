import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/agent_keys/controllers/agent_api_key_controller.dart';
import 'package:perennia/features/agent_keys/repositories/agent_api_key_repository.dart';

void main() {
  group('AgentApiKeyState', () {
    test('defensively copies keys on construction', () {
      final keys = <AgentApiKeyRecord>[_record('coach-key')];

      final state = AgentApiKeyState(keys: keys);
      keys.clear();

      expect(state.keys, hasLength(1));
      expect(state.keys.single.id, 'coach-key');
      expect(() => state.keys.clear(), throwsUnsupportedError);
    });

    test('defensively copies keys in copyWith', () {
      final state = AgentApiKeyState(keys: [_record('coach-key')]);
      final replacementKeys = <AgentApiKeyRecord>[_record('assistant-key')];

      final copied = state.copyWith(keys: replacementKeys);
      replacementKeys.clear();

      expect(copied.keys, hasLength(1));
      expect(copied.keys.single.id, 'assistant-key');
      expect(() => copied.keys.clear(), throwsUnsupportedError);
    });
  });
}

AgentApiKeyRecord _record(String id) {
  return AgentApiKeyRecord(
    id: id,
    name: 'Garage assistant',
    createdAt: DateTime.utc(2026, 7, 9),
    lastUsedAt: null,
  );
}
