import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _lockEnabledKey = 'protocols.lock.enabled';
const _lockPinHashKey = 'protocols.lock.pinHash';

/// Persists the Supplements lock's enabled flag + PIN hash. Mirrors
/// `SecureAuthSessionTokenStore` (features/auth/repositories/auth_repository.dart)
/// — the same `flutter_secure_storage` dependency, the same
/// abstract-interface-plus-concrete-impl shape, so `ProtocolsLockController`
/// can be tested with an in-memory fake (no platform keychain/keystore).
///
/// NEVER stores the PIN itself — only a salted PBKDF2 hash
/// (`ProtocolsPinHasher`). This is device/UI-only state: it has nothing to do
/// with sync (Compounds/Doses keep syncing on the normal LWW rails)
/// and nothing to do with the agent boundary (a later milestone).
abstract interface class ProtocolsLockStore {
  Future<bool> isEnabled();

  Future<void> setEnabled(bool enabled);

  Future<String?> readPinHash();

  Future<void> writePinHash(String hash);

  Future<void> clearPin();
}

final protocolsLockStoreProvider = Provider<ProtocolsLockStore>((ref) {
  return SecureProtocolsLockStore();
});

class SecureProtocolsLockStore implements ProtocolsLockStore {
  SecureProtocolsLockStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<bool> isEnabled() async {
    final value = await _storage.read(key: _lockEnabledKey);
    return value == 'true';
  }

  @override
  Future<void> setEnabled(bool enabled) {
    return _storage.write(
      key: _lockEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  @override
  Future<String?> readPinHash() {
    return _storage.read(key: _lockPinHashKey);
  }

  @override
  Future<void> writePinHash(String hash) {
    return _storage.write(key: _lockPinHashKey, value: hash);
  }

  @override
  Future<void> clearPin() {
    return _storage.delete(key: _lockPinHashKey);
  }
}
