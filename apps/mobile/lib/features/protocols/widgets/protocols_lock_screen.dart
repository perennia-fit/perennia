import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../controllers/protocols_lock_controller.dart';
import '../services/biometric_authenticator.dart';

/// Gates a Supplements screen behind the PIN/biometric lock (
/// PROTOCOLS.md §8). Wrap EVERY screen that renders Compound/Dose
/// content with this — both `CompoundListScreen` (reached from the Settings
/// tile and the Home overflow entry) and `ProtocolsDayView` (reached from
/// `CompoundListScreen`'s FAB) — so that whichever one happens to be on top
/// of the Navigator stack independently reacts to the SAME shared
/// `protocolsLockControllerProvider` state: the instant the app backgrounds
/// (or a fresh app start finds a lock already configured), every mounted
/// `ProtocolsLockGate` swaps its content for the lock screen, regardless of
/// which Supplements screen the user was last looking at.
///
/// When no lock is configured (`disabled`), this renders [child] directly —
/// the surface behaves exactly as it did before this slice.
class ProtocolsLockGate extends ConsumerWidget {
  const ProtocolsLockGate({super.key, required this.child});

  final Widget child;

  static const lockScreenKey = Key('protocols.lock.screen');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockState = ref.watch(protocolsLockControllerProvider).value;

    // While the store's initial read is still in flight, render nothing
    // rather than risk a one-frame flash of Compound/Dose content ahead of
    // finding out a lock is configured.
    if (lockState == null) {
      return Scaffold(backgroundColor: context.colors.background);
    }
    if (lockState.isUnavailable) {
      return const _ProtocolsLockUnavailableScreen(
        key: ProtocolsLockGate.lockScreenKey,
      );
    }
    if (lockState.isLocked) {
      return const _ProtocolsLockScreen(key: ProtocolsLockGate.lockScreenKey);
    }
    return child;
  }
}

class _ProtocolsLockUnavailableScreen extends StatelessWidget {
  const _ProtocolsLockUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: const Text('Supplements'),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: AppDimens.base),
                Text(
                  'Supplements lock unavailable',
                  textAlign: TextAlign.center,
                  style:
                      context.textStyles.h2.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppDimens.base),
                Text(
                  'Supplements stays hidden because the device secure storage '
                  'could not be read.',
                  textAlign: TextAlign.center,
                  style: context.textStyles.body
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProtocolsLockScreen extends StatelessWidget {
  const _ProtocolsLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: const Text('Supplements'),
      ),
      // A locked surface renders NO Dose/Compound content whatsoever — only
      // this neutral unlock prompt (hide-at-a-glance: a lent phone, a
      // screenshot, or the app switcher's backgrounding snapshot all see only
      // this screen).
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: colors.textSecondary),
                const SizedBox(height: AppDimens.base),
                Text(
                  'Supplements is locked',
                  style:
                      context.textStyles.h2.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppDimens.base),
                const ProtocolsUnlockForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The reusable unlock form: a biometric button (when the device supports
/// it) plus PIN entry — shared between the full-screen lock gate above and
/// the "confirm to disable the lock" step in Settings
/// (`protocols_lock_settings.dart`), so there is exactly ONE authentication
/// UI in the app, not two.
class ProtocolsUnlockForm extends ConsumerStatefulWidget {
  const ProtocolsUnlockForm({
    super.key,
    this.onUnlocked,
    this.message = 'Unlock to view your log.',
  });

  /// Called after a successful biometric/PIN unlock — the controller has
  /// already flipped to `unlocked` by the time this fires.
  final VoidCallback? onUnlocked;
  final String message;

  static const pinFieldKey = Key('protocols.lock.pinField');
  static const unlockPinButtonKey = Key('protocols.lock.unlockPin');
  static const unlockBiometricButtonKey = Key('protocols.lock.unlockBiometric');
  static const errorTextKey = Key('protocols.lock.error');

  @override
  ConsumerState<ProtocolsUnlockForm> createState() =>
      _ProtocolsUnlockFormState();
}

class _ProtocolsUnlockFormState extends ConsumerState<ProtocolsUnlockForm> {
  final _pinController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final unlocked = await ref
        .read(protocolsLockControllerProvider.notifier)
        .unlockWithPin(pin);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (!unlocked) {
        _error = 'Incorrect PIN';
      }
    });
    if (unlocked) {
      _pinController.clear();
      widget.onUnlocked?.call();
    }
  }

  Future<void> _tryBiometrics() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final unlocked = await ref
        .read(protocolsLockControllerProvider.notifier)
        .unlockWithBiometrics();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (!unlocked) {
        _error = 'Biometric authentication failed';
      }
    });
    if (unlocked) {
      widget.onUnlocked?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final biometricSupported =
        ref.watch(protocolsBiometricSupportedProvider).value ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: context.textStyles.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppDimens.base),
        if (biometricSupported) ...[
          SizedBox(
            height: AppDimens.touchTarget,
            child: FilledButton.icon(
              key: ProtocolsUnlockForm.unlockBiometricButtonKey,
              style: FilledButton.styleFrom(backgroundColor: colors.save),
              onPressed: _busy ? null : _tryBiometrics,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock with biometrics'),
            ),
          ),
          const SizedBox(height: AppDimens.base),
          Text(
            'or enter your PIN',
            textAlign: TextAlign.center,
            style: context.textStyles.caption
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.dense),
        ],
        TextField(
          key: ProtocolsUnlockForm.pinFieldKey,
          controller: _pinController,
          obscureText: true,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'PIN', counterText: ''),
          onSubmitted: (_) => _submitPin(),
        ),
        const SizedBox(height: AppDimens.dense),
        SizedBox(
          height: AppDimens.touchTarget,
          child: FilledButton(
            key: ProtocolsUnlockForm.unlockPinButtonKey,
            onPressed: _busy ? null : _submitPin,
            child: const Text('Unlock'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppDimens.dense),
          Text(
            _error!,
            key: ProtocolsUnlockForm.errorTextKey,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
