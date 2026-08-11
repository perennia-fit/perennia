import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Hashes/verifies the Supplements-lock PIN — NEVER stores it in plaintext.
/// Mirrors the PBKDF2-HMAC-SHA256 derivation already used for the
/// portable archive passphrase (`PortableArchiveRepository._deriveArchiveKey`)
/// so the app has exactly one key-derivation approach.
///
/// The stored format is `iterations:saltBase64:hashBase64` — self-describing
/// so a future iteration bump doesn't invalidate previously-set PINs.
class ProtocolsPinHasher {
  const ProtocolsPinHasher({this.iterations = 100000});

  /// PBKDF2 iteration count. A field (not a static const) purely so tests can
  /// use a much lower count for speed without touching production code.
  final int iterations;

  static final RegExp _validPinPattern = RegExp(r'^\d{4,8}$');

  /// A PIN must be 4-8 digits — plenty for a device/UI-only local gate (never
  /// a cryptographic secret protecting sync or the agent boundary).
  bool isValidPin(String pin) => _validPinPattern.hasMatch(pin);

  Future<String> hash(String pin) async {
    final salt = _randomSalt();
    final bytes = await _derive(pin, salt, iterations);
    return '$iterations:${base64Encode(salt)}:${base64Encode(bytes)}';
  }

  Future<bool> verify(String pin, String stored) async {
    final parts = stored.split(':');
    if (parts.length != 3) {
      return false;
    }
    final storedIterations = int.tryParse(parts[0]);
    if (storedIterations == null || storedIterations <= 0) {
      return false;
    }
    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64Decode(parts[1]);
      expected = base64Decode(parts[2]);
    } on FormatException {
      return false;
    }
    final candidate = await _derive(pin, salt, storedIterations);
    return _constantTimeEquals(candidate, expected);
  }

  Future<List<int>> _derive(String pin, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return secretKey.extractBytes();
  }

  List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i += 1) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
