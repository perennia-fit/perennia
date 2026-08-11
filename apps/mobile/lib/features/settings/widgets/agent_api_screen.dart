import 'package:flutter/material.dart';

import '../../agent_keys/widgets/agent_api_key_management.dart';
import 'settings_shared.dart';

/// Settings → Agent API: create, list, and revoke agent API keys.
class AgentApiScreen extends StatelessWidget {
  const AgentApiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubScreen(
      title: 'Agent API',
      children: [
        AgentApiKeyManagement(),
      ],
    );
  }
}
