import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final clientCrashReporterProvider = Provider<ClientCrashReporter>((ref) {
  return SentryClientCrashReporter(
    config: ClientCrashReportingConfig.fromEnvironment(),
  );
});

abstract interface class ClientCrashReporter {
  Future<void> setEnabled(bool enabled);

  Future<void> captureException(
    Object throwable,
    StackTrace stackTrace, {
    Hint? hint,
  });

  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint});
}

abstract interface class SentryFlutterSdk {
  bool get isEnabled;

  Future<void> init(
    FutureOr<void> Function(SentryFlutterOptions options) configure,
  );

  Future<void> close();

  Future<SentryId> captureException(
    Object throwable, {
    Object? stackTrace,
    Hint? hint,
  });

  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint});
}

class DefaultSentryFlutterSdk implements SentryFlutterSdk {
  const DefaultSentryFlutterSdk();

  @override
  bool get isEnabled => Sentry.isEnabled;

  @override
  Future<void> init(
    FutureOr<void> Function(SentryFlutterOptions options) configure,
  ) {
    return SentryFlutter.init(configure);
  }

  @override
  Future<void> close() => Sentry.close();

  @override
  Future<SentryId> captureException(
    Object throwable, {
    Object? stackTrace,
    Hint? hint,
  }) {
    return Sentry.captureException(
      throwable,
      stackTrace: stackTrace,
      hint: hint,
    );
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) {
    return Sentry.addBreadcrumb(breadcrumb, hint: hint);
  }
}

class ClientCrashReportingConfig {
  const ClientCrashReportingConfig({
    required this.dsn,
    this.environment,
    this.release,
  });

  factory ClientCrashReportingConfig.fromEnvironment() {
    return const ClientCrashReportingConfig(
      dsn: String.fromEnvironment('PRN_SENTRY_DSN'),
      environment: String.fromEnvironment('PRN_SENTRY_ENVIRONMENT'),
      release: String.fromEnvironment('PRN_APP_RELEASE'),
    );
  }

  final String dsn;
  final String? environment;
  final String? release;

  bool get hasDsn => dsn.trim().isNotEmpty;
}

class SentryClientCrashReporter implements ClientCrashReporter {
  SentryClientCrashReporter({
    required this.config,
    this.sdk = const DefaultSentryFlutterSdk(),
  });

  final ClientCrashReportingConfig config;
  final SentryFlutterSdk sdk;

  var _enabled = false;
  var _initialized = false;

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!enabled || !config.hasDsn) {
      _enabled = false;
      if (_initialized || sdk.isEnabled) {
        await sdk.close();
      }
      _initialized = false;
      return;
    }

    _enabled = true;
    if (_initialized && sdk.isEnabled) {
      return;
    }

    await sdk.init((options) {
      configureClientCrashReportingOptions(options, config);
    });
    _initialized = true;
  }

  @override
  Future<void> captureException(
    Object throwable,
    StackTrace stackTrace, {
    Hint? hint,
  }) async {
    if (!_enabled || !_initialized || !sdk.isEnabled) {
      return;
    }
    await sdk.captureException(
      throwable,
      stackTrace: stackTrace,
      hint: hint,
    );
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb breadcrumb, {Hint? hint}) async {
    if (!_enabled || !_initialized || !sdk.isEnabled) {
      return;
    }
    final scrubbed = scrubClientCrashBreadcrumb(breadcrumb, hint ?? Hint());
    if (scrubbed == null) {
      return;
    }
    await sdk.addBreadcrumb(scrubbed, hint: hint);
  }
}

void ensureClientCrashReportingBindingInitialized() {
  SentryWidgetsFlutterBinding.ensureInitialized();
}

void configureClientCrashReportingOptions(
  SentryFlutterOptions options,
  ClientCrashReportingConfig config,
) {
  options
    ..dsn = config.dsn
    ..environment = _nonEmpty(config.environment)
    ..release = _nonEmpty(config.release)
    ..sendDefaultPii = false
    ..attachStacktrace = true
    ..enableAutoSessionTracking = false
    ..enableAutoPerformanceTracing = false
    ..enableFramesTracking = false
    ..enableAutoNativeBreadcrumbs = false
    ..enableAppLifecycleBreadcrumbs = false
    ..enableWindowMetricBreadcrumbs = false
    ..enableBrightnessChangeBreadcrumbs = false
    ..enableTextScaleChangeBreadcrumbs = false
    ..enableMemoryPressureBreadcrumbs = false
    ..enableUserInteractionBreadcrumbs = false
    ..enableUserInteractionTracing = false
    ..enablePrintBreadcrumbs = false
    ..recordHttpBreadcrumbs = false
    ..captureFailedRequests = false
    ..sendClientReports = false
    ..reportPackages = false
    ..attachScreenshot = false
    ..tracesSampleRate = null
    ..maxRequestBodySize = MaxRequestBodySize.never
    ..beforeSend = scrubClientCrashEvent
    ..beforeBreadcrumb = scrubClientCrashBreadcrumb;
}

SentryEvent? scrubClientCrashEvent(SentryEvent event, Hint _) {
  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    platform: event.platform,
    release: event.release,
    dist: event.dist,
    environment: event.environment,
    level: event.level,
    sdk: event.sdk,
    contexts: Contexts(device: _scrubDevice(event.contexts.device)),
    exceptions: _scrubExceptions(event.exceptions),
    threads: _scrubThreads(event.threads),
    breadcrumbs: _scrubBreadcrumbs(event.breadcrumbs),
    type: event.type,
  );
}

Breadcrumb? scrubClientCrashBreadcrumb(Breadcrumb? breadcrumb, Hint _) {
  if (breadcrumb == null) {
    return null;
  }
  final data = _scrubBreadcrumbData(breadcrumb.data);
  return Breadcrumb(
    category: breadcrumb.category,
    data: data.isEmpty ? null : data,
    level: breadcrumb.level,
    timestamp: breadcrumb.timestamp,
    type: breadcrumb.type,
  );
}

List<SentryException>? _scrubExceptions(List<SentryException>? exceptions) {
  if (exceptions == null) {
    return null;
  }
  return [
    for (final exception in exceptions)
      SentryException(
        type: exception.type,
        value: filteredCrashValue,
        stackTrace: _scrubStackTrace(exception.stackTrace),
        threadId: exception.threadId,
      ),
  ];
}

List<SentryThread>? _scrubThreads(List<SentryThread>? threads) {
  if (threads == null) {
    return null;
  }
  return [
    for (final thread in threads)
      SentryThread(
        id: thread.id,
        crashed: thread.crashed,
        current: thread.current,
        stacktrace: _scrubStackTrace(thread.stacktrace),
      ),
  ];
}

SentryStackTrace? _scrubStackTrace(SentryStackTrace? stackTrace) {
  if (stackTrace == null) {
    return null;
  }
  return SentryStackTrace(
    frames: [
      for (final frame in stackTrace.frames)
        SentryStackFrame(
          fileName: frame.fileName,
          function: frame.function,
          module: frame.module,
          lineNo: frame.lineNo,
          colNo: frame.colNo,
          inApp: frame.inApp,
          package: frame.package,
          native: frame.native,
          platform: frame.platform,
        ),
    ],
    lang: stackTrace.lang,
    snapshot: stackTrace.snapshot,
  );
}

SentryDevice? _scrubDevice(SentryDevice? device) {
  if (device == null) {
    return null;
  }
  return SentryDevice(
    family: device.family,
    model: device.model,
    manufacturer: device.manufacturer,
    brand: device.brand,
    arch: device.arch,
    deviceType: device.deviceType,
    simulator: device.simulator,
  );
}

List<Breadcrumb>? _scrubBreadcrumbs(List<Breadcrumb>? breadcrumbs) {
  if (breadcrumbs == null) {
    return null;
  }
  return [
    for (final breadcrumb in breadcrumbs)
      if (scrubClientCrashBreadcrumb(breadcrumb, Hint()) case final scrubbed?)
        scrubbed,
  ];
}

Map<String, dynamic> _scrubBreadcrumbData(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) {
    return const <String, dynamic>{};
  }

  final scrubbed = <String, dynamic>{};
  for (final entry in data.entries) {
    if (!_allowedBreadcrumbDataKeys.contains(_normalizedKey(entry.key))) {
      continue;
    }
    if (entry.value is String && _containsSensitiveString(entry.value)) {
      continue;
    }
    scrubbed[entry.key] = entry.value;
  }
  return scrubbed;
}

bool _containsSensitiveString(Object? value) {
  if (value is! String) {
    return false;
  }
  return _emailPattern.hasMatch(value) ||
      value.toLowerCase().contains('bearer ');
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String _normalizedKey(String key) {
  return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

const filteredCrashValue = '[Filtered]';

const _allowedBreadcrumbDataKeys = <String>{
  'method',
  'status',
  'statuscode',
  'duration',
  'requestbodysize',
  'responsebodysize',
  'starttimestamp',
  'endtimestamp',
};

final _emailPattern = RegExp(
  r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
  caseSensitive: false,
);
