import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../auth/widgets/sign_in_screen.dart';
import '../controllers/agent_api_key_controller.dart';
import '../repositories/agent_api_key_repository.dart';

class AgentApiKeyManagement extends ConsumerStatefulWidget {
  const AgentApiKeyManagement({super.key});

  static const nameFieldKey = Key('agentApiKeys.nameField');
  static const createButtonKey = Key('agentApiKeys.createButton');
  static const createdSecretPanelKey = Key('agentApiKeys.createdSecret.panel');
  static const createdSecretTextKey = Key('agentApiKeys.createdSecret.text');
  static const copySecretButtonKey =
      Key('agentApiKeys.createdSecret.copyButton');
  static const dismissSecretButtonKey =
      Key('agentApiKeys.createdSecret.dismissButton');
  static const signInButtonKey = Key('agentApiKeys.signInButton');
  static const emptyListKey = Key('agentApiKeys.empty');

  static Key keyTileKey(String keyId) => Key('agentApiKeys.tile.$keyId');

  static Key revokeButtonKey(String keyId) => Key('agentApiKeys.revoke.$keyId');

  @override
  ConsumerState<AgentApiKeyManagement> createState() =>
      _AgentApiKeyManagementState();
}

class _AgentApiKeyManagementState extends ConsumerState<AgentApiKeyManagement> {
  late final TextEditingController _nameController;
  var _canCreate = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _nameController.addListener(_handleNameChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_handleNameChanged)
      ..dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    final canCreate = _nameController.text.trim().isNotEmpty;
    if (canCreate == _canCreate) {
      return;
    }
    setState(() {
      _canCreate = canCreate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState =
        ref.watch(authControllerProvider).value ?? AuthState.defaults;
    if (!authState.isSignedIn) {
      return const _SignedOutAgentKeys();
    }

    final asyncState = ref.watch(agentApiKeyControllerProvider);
    final isBusy = asyncState.isLoading;
    final value = asyncState.value ?? AgentApiKeyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreateAgentKeyForm(
          controller: _nameController,
          canCreate: _canCreate && !isBusy,
          onCreate: () {
            unawaited(_createKey());
          },
        ),
        if (value.createdKey != null) ...[
          const SizedBox(height: AppDimens.dense),
          _CreatedAgentKeySecret(createdKey: value.createdKey!),
        ],
        if (asyncState.hasError) ...[
          const SizedBox(height: AppDimens.dense),
          _AgentKeyError(error: asyncState.error!),
        ],
        const SizedBox(height: AppDimens.dense),
        if (isBusy)
          const LinearProgressIndicator(minHeight: 2)
        else
          _AgentKeyList(keys: value.keys),
      ],
    );
  }

  Future<void> _createKey() async {
    final controller = ref.read(agentApiKeyControllerProvider.notifier);
    final rawName = _nameController.text;
    await controller.createKey(rawName);
    if (!mounted) {
      return;
    }
    if (!ref.read(agentApiKeyControllerProvider).hasError) {
      _nameController.clear();
    }
  }
}

class _SignedOutAgentKeys extends StatelessWidget {
  const _SignedOutAgentKeys();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_outline),
      title: Text(l10n.agentKeysSignedOutTitle),
      trailing: SizedBox(
        height: AppDimens.touchTarget,
        child: OutlinedButton.icon(
          key: AgentApiKeyManagement.signInButtonKey,
          onPressed: () {
            unawaited(Navigator.of(context).pushNamed(SignInScreen.routeName));
          },
          icon: const Icon(Icons.login_outlined),
          label: Text(l10n.agentKeysSignIn),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _CreateAgentKeyForm extends StatelessWidget {
  const _CreateAgentKeyForm({
    required this.controller,
    required this.canCreate,
    required this.onCreate,
  });

  final TextEditingController controller;
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: AgentApiKeyManagement.nameFieldKey,
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.agentKeysNameLabel,
              prefixIcon: const Icon(Icons.smart_toy_outlined),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (canCreate) {
                onCreate();
              }
            },
          ),
          const SizedBox(height: AppDimens.dense),
          SizedBox(
            height: AppDimens.touchTarget,
            child: FilledButton.icon(
              key: AgentApiKeyManagement.createButtonKey,
              onPressed: canCreate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.agentKeysCreate),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatedAgentKeySecret extends ConsumerWidget {
  const _CreatedAgentKeySecret({required this.createdKey});

  final CreatedAgentApiKey createdKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.agentKeysSecretShownOnceSemanticLabel,
      child: DecoratedBox(
        key: AgentApiKeyManagement.createdSecretPanelKey,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.primary),
          borderRadius: AppRadii.cardMd,
          color: context.colors.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.key_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppDimens.dense),
                  Expanded(
                    child: Text(
                      l10n.agentKeysSecretShownOnceTitle,
                      style: context.textStyles.h2,
                    ),
                  ),
                  IconButton(
                    key: AgentApiKeyManagement.copySecretButtonKey,
                    tooltip: l10n.agentKeysCopySecretTooltip,
                    onPressed: () {
                      unawaited(
                        Clipboard.setData(
                          ClipboardData(text: createdKey.secret),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.agentKeysCopiedMessage)),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.dense),
              SelectableText(
                createdKey.secret,
                key: AgentApiKeyManagement.createdSecretTextKey,
                style: context.textStyles.body.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppDimens.dense),
              Text(
                l10n.agentKeysSecretWarning,
                style: context.textStyles.caption,
              ),
              const SizedBox(height: AppDimens.dense),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: AppDimens.touchTarget,
                  child: TextButton(
                    key: AgentApiKeyManagement.dismissSecretButtonKey,
                    onPressed: ref
                        .read(agentApiKeyControllerProvider.notifier)
                        .dismissCreatedSecret,
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textPrimary,
                    ),
                    child: Text(l10n.agentKeysDone),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentKeyError extends StatelessWidget {
  const _AgentKeyError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.error),
        borderRadius: AppRadii.cardMd,
        color: colorScheme.errorContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Text(
          error.toString(),
          style: context.textStyles.body.copyWith(
            color: colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _AgentKeyList extends StatelessWidget {
  const _AgentKeyList({required this.keys});

  final List<AgentApiKeyRecord> keys;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (keys.isEmpty) {
      return Padding(
        key: AgentApiKeyManagement.emptyListKey,
        padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
        child: Text(
          l10n.agentKeysEmpty,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < keys.length; index += 1) ...[
          _AgentKeyTile(record: keys[index]),
          if (index != keys.length - 1) Divider(color: context.colors.divider),
        ],
      ],
    );
  }
}

class _AgentKeyTile extends ConsumerWidget {
  const _AgentKeyTile({required this.record});

  final AgentApiKeyRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListTile(
      key: AgentApiKeyManagement.keyTileKey(record.id),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined),
      title: Text(record.name),
      subtitle: Text(_metadataLabel(l10n, record)),
      trailing: IconButton(
        key: AgentApiKeyManagement.revokeButtonKey(record.id),
        tooltip: l10n.agentKeysRevokeTooltip,
        onPressed: () {
          unawaited(
            ref
                .read(agentApiKeyControllerProvider.notifier)
                .revokeKey(record.id),
          );
        },
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

String _metadataLabel(AppLocalizations l10n, AgentApiKeyRecord record) {
  final created =
      DateFormat.yMMMd().add_Hm().format(record.createdAt.toLocal());
  final lastUsed = record.lastUsedAt == null
      ? l10n.agentKeysNeverUsed
      : DateFormat.yMMMd().add_Hm().format(record.lastUsedAt!.toLocal());
  return [
    if (record.start != null) l10n.agentKeysStarts(record.start!),
    l10n.agentKeysCreated(created),
    l10n.agentKeysLastUsed(lastUsed),
  ].join(' | ');
}
