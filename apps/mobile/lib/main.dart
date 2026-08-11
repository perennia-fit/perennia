import 'package:flutter/material.dart';

import 'app.dart';
import 'features/settings/services/client_crash_reporting.dart';

void main() {
  ensureClientCrashReportingBindingInitialized();

  final crashReporter = SentryClientCrashReporter(
    config: ClientCrashReportingConfig.fromEnvironment(),
  );

  runApp(
    PerenniaRoot(
      extraOverrides: [
        clientCrashReporterProvider.overrideWith((ref) => crashReporter),
      ],
    ),
  );
}
