import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/biometric_authenticator.dart';
import '../services/protocols_lock_store.dart';
import '../services/protocols_pin_hasher.dart';

/// The Supplements lock's state machine (PROTOCOLS.md §8,
///):
///
/// - [disabled]: no lock configured — the Supplements surface renders freely,
///   same as before this slice.
/// - [locked]: a lock IS configured and the surface must not render any
///   Compound/Dose content until biometric/PIN succeeds.
/// - [unlocked]: a lock is configured and the current in-memory session has
///   already authenticated — the surface renders normally until the app
///   leaves the foreground, at which point it re-locks (see
///   `ProtocolsLockController.didChangeAppLifecycleState`).
/// - [unavailable]: secure storage could not be read, so the controller cannot
///   safely determine whether the lock is configured. The UI fails closed and
///   keeps Compound/Dose content hidden until storage is readable again.
///
/// LOAD-BEARING: this state machine is a DEVICE/UI control ONLY.
/// It changes what THIS DEVICE renders locally. It never touches sync —
/// Compounds/Doses keep syncing like all data on the normal LWW rails
/// (the server stays system of record) regardless of lock status —
/// and it is NOT an agent scope wall (the agent boundary is a separate, later
/// milestone, M30/, held). Nothing in this file, or anywhere this
/// state is read, may filter sync rows or agent-visible data by lock status.
enum ProtocolsLockStatus { disabled, locked, unlocked, unavailable }

class ProtocolsLockState {
  const ProtocolsLockState({required this.status, required this.hasPin});

  final ProtocolsLockStatus status;

  /// Whether a PIN has been configured (independent of biometric support) —
  /// drives the Settings UI (e.g. offering "Change PIN" vs "Set a PIN").
  final bool hasPin;

  bool get isEnabled => status != ProtocolsLockStatus.disabled;
  bool get isLocked => status == ProtocolsLockStatus.locked;
  bool get isUnavailable => status == ProtocolsLockStatus.unavailable;

  ProtocolsLockState copyWith({ProtocolsLockStatus? status, bool? hasPin}) {
    return ProtocolsLockState(
      status: status ?? this.status,
      hasPin: hasPin ?? this.hasPin,
    );
  }

  static const initial = ProtocolsLockState(
    status: ProtocolsLockStatus.disabled,
    hasPin: false,
  );
}

final protocolsLockControllerProvider =
    AsyncNotifierProvider<ProtocolsLockController, ProtocolsLockState>(
  ProtocolsLockController.new,
);

class ProtocolsLockController extends AsyncNotifier<ProtocolsLockState>
    with WidgetsBindingObserver {
  ProtocolsLockController({ProtocolsPinHasher? hasher})
      : _hasher = hasher ?? const ProtocolsPinHasher();

  final ProtocolsPinHasher _hasher;

  @override
  Future<ProtocolsLockState> build() async {
    final store = ref.watch(protocolsLockStoreProvider);
    late final bool enabled;
    late final bool hasPin;
    try {
      enabled = await store.isEnabled();
      hasPin = await store.readPinHash() != null;
    } catch (_) {
      return const ProtocolsLockState(
        status: ProtocolsLockStatus.unavailable,
        hasPin: false,
      );
    }

    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));

    // A lock configured on a PRIOR run always starts locked on a fresh
    // (cold-start) build — sticky across process restarts, not just
    // backgrounding (acceptance: "survives backgrounding").
    return ProtocolsLockState(
      status:
          enabled ? ProtocolsLockStatus.locked : ProtocolsLockStatus.disabled,
      hasPin: hasPin,
    );
  }

  /// Re-locks whenever the app leaves the foreground (inactive, paused,
  /// hidden, detached) — the single mechanism behind BOTH acceptance
  /// criteria "hidden at a glance...app switcher" and "survives
  /// backgrounding...re-locks on resume": once locked, every
  /// `ProtocolsLockGate` in the widget tree (regardless of which Supplements
  /// screen is currently on top of the Navigator stack) immediately swaps its
  /// rendered content for the lock screen — so a screenshot taken during the
  /// OS's transition-to-background snapshot, or a resumed lent phone, never
  /// shows Compound/Dose content.
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState != AppLifecycleState.resumed) {
      _relockIfEnabled();
    }
  }

  void _relockIfEnabled() {
    final current = state.value;
    if (current == null || current.status != ProtocolsLockStatus.unlocked) {
      return;
    }
    state = AsyncData(current.copyWith(status: ProtocolsLockStatus.locked));
  }

  /// Attempts a biometric/device-credential unlock. On success the current
  /// session unlocks; on failure (or cancellation) the surface stays locked.
  Future<bool> unlockWithBiometrics() async {
    if (state.value?.status != ProtocolsLockStatus.locked) {
      return false;
    }
    final authenticator = ref.read(biometricAuthenticatorProvider);
    final success = await authenticator.authenticate(
      reason: 'Unlock Supplements',
    );
    if (success) {
      _setUnlocked();
    }
    return success;
  }

  /// Attempts a PIN unlock against the stored hash. A wrong PIN returns false
  /// and leaves the surface locked; there is no lockout/backoff here — this is
  /// a device/UI convenience gate, not a security boundary for sync or the
  /// agent surface.
  Future<bool> unlockWithPin(String pin) async {
    if (state.value?.status != ProtocolsLockStatus.locked) {
      return false;
    }
    final store = ref.read(protocolsLockStoreProvider);
    final storedHash = await store.readPinHash();
    if (storedHash == null) {
      return false;
    }
    final matches = await _hasher.verify(pin, storedHash);
    if (matches) {
      _setUnlocked();
    }
    return matches;
  }

  void _setUnlocked() {
    final current = state.value;
    if (current == null || current.status != ProtocolsLockStatus.locked) {
      return;
    }
    state = AsyncData(current.copyWith(status: ProtocolsLockStatus.unlocked));
  }

  /// Whether a candidate PIN is well-formed (4-8 digits) before attempting to
  /// hash/store it.
  bool isValidPin(String pin) => _hasher.isValidPin(pin);

  /// Configures/replaces the PIN and enables the lock. Deliberately lands on
  /// [ProtocolsLockStatus.locked] rather than leaving the just-configured
  /// session unlocked: a conservative default so "enabling the lock" always
  /// immediately gates the surface, with no window where it silently stays
  /// open.
  Future<void> enableLock(String pin) async {
    if (!_hasher.isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'must be 4-8 digits');
    }
    final store = ref.read(protocolsLockStoreProvider);
    final hash = await _hasher.hash(pin);
    await store.writePinHash(hash);
    await store.setEnabled(true);
    state = AsyncData(
      const ProtocolsLockState(
          status: ProtocolsLockStatus.locked, hasPin: true),
    );
  }

  /// Disables the lock and forgets the PIN hash. Requires the CALLER to have
  /// already authenticated this session (`status == unlocked`) — refuses
  /// otherwise, so a locked surface can never be turned off from Settings
  /// without first proving possession, even though Settings itself sits
  /// outside the gate.
  Future<bool> disableLock() async {
    final current = state.value;
    if (current == null || current.status != ProtocolsLockStatus.unlocked) {
      return false;
    }
    final store = ref.read(protocolsLockStoreProvider);
    await store.setEnabled(false);
    await store.clearPin();
    state = AsyncData(
      const ProtocolsLockState(
          status: ProtocolsLockStatus.disabled, hasPin: false),
    );
    return true;
  }
}
