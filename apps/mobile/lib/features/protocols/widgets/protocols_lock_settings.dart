import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../controllers/protocols_lock_controller.dart';
import 'protocols_lock_screen.dart';

/// The Settings "Lock Supplements" control: a toggle that, when
/// turned on, opens a PIN configure sheet (mirrors the `SwitchListTile` +
/// configure-flow pattern used elsewhere in Settings); when turned off,
/// requires the user to re-authenticate first (`ProtocolsUnlockForm`) before
/// the lock is actually disabled — so a lent phone can never bypass the lock
/// by simply flipping this switch in Settings, even though Settings itself
/// sits outside the gate.
///
/// LOAD-BEARING: this toggle controls a DEVICE/UI-only setting.
/// It never changes what syncs (Compounds/Doses keep syncing like all data,
///) and it never filters agent-visible data (the agent boundary is
/// a separate, later milestone — M30, held).
class ProtocolsLockSettingsTile extends ConsumerWidget {
  const ProtocolsLockSettingsTile({super.key});

  static const switchKey = Key('settings.protocolsLock.enabled');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockState = ref.watch(protocolsLockControllerProvider).value;
    final isUnavailable = lockState?.isUnavailable ?? false;
    final isEnabled = lockState?.isEnabled ?? false;

    return SwitchListTile(
      key: switchKey,
      contentPadding: EdgeInsets.zero,
      title: const Text('Lock Supplements'),
      subtitle: Text(
        isUnavailable
            ? 'Supplements stays hidden because secure storage is unavailable'
            : 'Require biometrics or a PIN to open the Supplements section',
      ),
      value: isEnabled,
      onChanged: lockState == null || isUnavailable
          ? null
          : (value) {
              unawaited(
                value
                    ? _openConfigureSheet(context)
                    : _openDisableSheet(context, ref),
              );
            },
    );
  }

  Future<void> _openConfigureSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: const ProtocolsLockConfigureSheet(),
      ),
    );
  }

  Future<void> _openDisableSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ProtocolsLockDisableSheet(
          onUnlocked: () async {
            await ref
                .read(protocolsLockControllerProvider.notifier)
                .disableLock();
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
          },
        ),
      ),
    );
  }
}

/// Set-a-PIN sheet shown when the Settings toggle turns the lock ON. Saves
/// through `ProtocolsLockController.enableLock`, which itself validates the
/// PIN format and never stores it in plaintext (`ProtocolsPinHasher`).
class ProtocolsLockConfigureSheet extends ConsumerStatefulWidget {
  const ProtocolsLockConfigureSheet({super.key});

  static const pinFieldKey = Key('protocols.lockConfigure.pin');
  static const confirmFieldKey = Key('protocols.lockConfigure.confirm');
  static const saveButtonKey = Key('protocols.lockConfigure.save');
  static const errorTextKey = Key('protocols.lockConfigure.error');

  @override
  ConsumerState<ProtocolsLockConfigureSheet> createState() =>
      _ProtocolsLockConfigureSheetState();
}

class _ProtocolsLockConfigureSheetState
    extends ConsumerState<ProtocolsLockConfigureSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    final controller = ref.read(protocolsLockControllerProvider.notifier);

    if (!controller.isValidPin(pin)) {
      setState(() => _error = 'PIN must be 4-8 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    await controller.enableLock(pin);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set a PIN',
              style: context.textStyles.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDimens.dense),
            Text(
              'Used to unlock Supplements when biometrics are unavailable. '
              '4-8 digits.',
              style:
                  context.textStyles.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: ProtocolsLockConfigureSheet.pinFieldKey,
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration:
                  const InputDecoration(labelText: 'PIN', counterText: ''),
            ),
            const SizedBox(height: AppDimens.dense),
            TextField(
              key: ProtocolsLockConfigureSheet.confirmFieldKey,
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppDimens.dense),
              Text(
                _error!,
                key: ProtocolsLockConfigureSheet.errorTextKey,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppDimens.base),
            SizedBox(
              height: AppDimens.touchTarget,
              child: FilledButton(
                key: ProtocolsLockConfigureSheet.saveButtonKey,
                style: FilledButton.styleFrom(backgroundColor: colors.save),
                onPressed: _saving ? null : _save,
                child: const Text('Turn on lock'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "confirm to disable" step shown when the Settings toggle turns the
/// lock OFF. Reuses `ProtocolsUnlockForm` (the SAME authentication UI as the
/// full-screen lock gate) so there is one auth surface, not two; on success
/// invokes [onUnlocked], which the caller wires to
/// `ProtocolsLockController.disableLock()`.
class ProtocolsLockDisableSheet extends StatelessWidget {
  const ProtocolsLockDisableSheet({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confirm to turn off the lock',
              style: context.textStyles.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDimens.base),
            ProtocolsUnlockForm(
              message: 'Authenticate to turn off the Supplements lock.',
              onUnlocked: onUnlocked,
            ),
          ],
        ),
      ),
    );
  }
}
