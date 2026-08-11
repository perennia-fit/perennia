import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/settings/account_settings.dart';
import '../../../domain/training/training_day.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  // the account-level half of AppSettings is a synced
  // Drift singleton; the device-level half stays in the local JSON file. The
  // split repository merges the two on load and splits them back on save so no
  // screen or key changes.
  return SplitSettingsRepository(
    deviceStore: FileSettingsRepository.openDefault(),
    accountSettings: ref.watch(trainingRepositoriesProvider).accountSettings,
  );
});

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

abstract interface class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

class FileSettingsRepository implements SettingsRepository {
  const FileSettingsRepository({
    required Future<File> Function() settingsFile,
  }) : _settingsFile = settingsFile;

  factory FileSettingsRepository.openDefault() {
    return FileSettingsRepository(settingsFile: _defaultSettingsFile);
  }

  final Future<File> Function() _settingsFile;

  @override
  Future<AppSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return AppSettings.defaults;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return AppSettings.fromJson(decoded);
      }
    } on Object {
      return AppSettings.defaults;
    }
    return AppSettings.defaults;
  }

  @override
  Future<void> save(AppSettings settings) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  static Future<File> _defaultSettingsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'settings.json'));
  }
}

/// The composite repository that splits `AppSettings` along the account/device
/// line: the account-level half loads from / saves to the synced
/// Drift `user_settings` singleton (`accountSettings`), while the device-level
/// half stays in the local JSON file (`deviceStore`). The two merge into one
/// `AppSettings` on load and split back apart on save, so the controllers and
/// screens see the same merged object with no key or behavior change.
///
/// The JSON file keeps mirroring the *full* `AppSettings` shape (both halves) so
/// Backup/Restore is unchanged; the Drift row is the source of truth
/// for the account fields once it exists. On first load with no Drift row, the
/// account half of the existing JSON is migrated into the row exactly once.
class SplitSettingsRepository implements SettingsRepository {
  SplitSettingsRepository({
    required SettingsRepository deviceStore,
    required AccountSettingsRepository accountSettings,
  })  : _deviceStore = deviceStore,
        _accountSettings = accountSettings;

  final SettingsRepository _deviceStore;
  final AccountSettingsRepository _accountSettings;

  @override
  Future<AppSettings> load() async {
    final fromJson = await _deviceStore.load();
    final accountRow = await _accountSettings.load();
    if (accountRow == null) {
      // One-time migration: seed the synced row from the JSON's account half so
      // existing users keep their theme/units/etc. after the split. Idempotent —
      // once the row exists this branch never runs again.
      await _accountSettings.save(fromJson.toAccountSettings());
      return fromJson;
    }
    return fromJson.mergeAccountSettings(accountRow);
  }

  @override
  Future<void> save(AppSettings settings) async {
    // Device half + full backup mirror to JSON; account half to the synced row.
    await _deviceStore.save(settings);
    await _accountSettings.save(settings.toAccountSettings());
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([AppSettings initial = AppSettings.defaults])
      : _settings = initial;

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).load();
  }

  Future<void> setThemePreference(AppThemePreference preference) {
    return _update((settings) {
      return settings.copyWith(themePreference: preference);
    });
  }

  Future<void> setUnitSystem(UnitSystem unitSystem) {
    return _update((settings) {
      return settings.copyWith(unitSystem: unitSystem);
    });
  }

  Future<void> setWeekStartDay(WeekStartDay weekStartDay) {
    return _update((settings) {
      return settings.copyWith(weekStartDay: weekStartDay);
    });
  }

  Future<void> setDefaultWeightIncrement(double increment) {
    return _update((settings) {
      return settings.copyWith(defaultWeightIncrement: increment);
    });
  }

  Future<void> setHomeScreenDisplay(HomeScreenDisplay display) {
    return _update((settings) {
      return settings.copyWith(homeScreenDisplay: display);
    });
  }

  Future<void> setPrTrackingEnabled(bool enabled) {
    return _update((settings) {
      return settings.copyWith(prTrackingEnabled: enabled);
    });
  }

  Future<void> setMarkSetsCompleteByDefault(bool enabled) {
    return _update((settings) {
      return settings.copyWith(markSetsCompleteByDefault: enabled);
    });
  }

  Future<void> setAutoSelectNextSet(bool enabled) {
    return _update((settings) {
      return settings.copyWith(autoSelectNextSet: enabled);
    });
  }

  Future<void> setRestTimerSoundsEnabled(bool enabled) {
    return _update((settings) {
      return settings.copyWith(restTimerSoundsEnabled: enabled);
    });
  }

  Future<void> setKeepScreenOn(bool enabled) {
    return _update((settings) {
      return settings.copyWith(keepScreenOn: enabled);
    });
  }

  Future<void> setCrashReportingEnabled(bool enabled) {
    return _update((settings) {
      return settings.copyWith(crashReportingEnabled: enabled);
    });
  }

  Future<void> setAutoBackupEnabled(bool enabled) {
    return _update((settings) {
      return settings.copyWith(autoBackupEnabled: enabled);
    });
  }

  Future<void> setAutoBackupFolder({
    required String uri,
    required String label,
  }) {
    return _update((settings) {
      return settings.copyWith(
        autoBackupEnabled: true,
        autoBackupFolderUri: uri,
        autoBackupFolderLabel: label,
        autoBackupLastStatus: AutoBackupStatus.idle,
      );
    });
  }

  Future<void> setAutoBackupEncryptionPassphrase(String? passphrase) {
    return _update((settings) {
      final normalized = passphrase?.trim();
      return settings.copyWith(
        autoBackupEncryptionPassphrase:
            normalized == null || normalized.isEmpty ? null : normalized,
      );
    });
  }

  Future<void> _update(
      AppSettings Function(AppSettings settings) transform) async {
    final repository = ref.read(settingsRepositoryProvider);
    final current = state.value ?? await repository.load();
    final next = transform(current);
    state = AsyncData<AppSettings>(next);
    await repository.save(next);
  }
}

@immutable
class AppSettings {
  const AppSettings({
    this.themePreference = AppThemePreference.system,
    this.unitSystem = UnitSystem.metric,
    this.weekStartDay = WeekStartDay.monday,
    this.defaultWeightIncrement = 2.5,
    this.homeScreenDisplay = HomeScreenDisplay.comfortable,
    this.prTrackingEnabled = true,
    this.markSetsCompleteByDefault = false,
    this.autoSelectNextSet = true,
    this.restTimerSoundsEnabled = true,
    this.keepScreenOn = false,
    this.crashReportingEnabled = false,
    this.autoBackupEnabled = false,
    this.autoBackupFolderUri,
    this.autoBackupFolderLabel,
    this.autoBackupEncryptionPassphrase,
    this.autoBackupLastRunAt,
    this.autoBackupLastSuccessfulRunAt,
    this.autoBackupLastStatus = AutoBackupStatus.idle,
  }) : assert(defaultWeightIncrement > 0);

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      themePreference: _enumValue(
        AppThemePreference.values,
        json['themePreference'],
        AppThemePreference.system,
      ),
      unitSystem: _enumValue(
        UnitSystem.values,
        json['unitSystem'],
        UnitSystem.metric,
      ),
      weekStartDay: _enumValue(
        WeekStartDay.values,
        json['weekStartDay'],
        WeekStartDay.monday,
      ),
      defaultWeightIncrement:
          _positiveDouble(json['defaultWeightIncrement'], 2.5),
      homeScreenDisplay: _enumValue(
        HomeScreenDisplay.values,
        json['homeScreenDisplay'],
        HomeScreenDisplay.comfortable,
      ),
      prTrackingEnabled: json['prTrackingEnabled'] is bool
          ? json['prTrackingEnabled']! as bool
          : true,
      markSetsCompleteByDefault: json['markSetsCompleteByDefault'] is bool
          ? json['markSetsCompleteByDefault']! as bool
          : false,
      autoSelectNextSet: json['autoSelectNextSet'] is bool
          ? json['autoSelectNextSet']! as bool
          : true,
      restTimerSoundsEnabled: json['restTimerSoundsEnabled'] is bool
          ? json['restTimerSoundsEnabled']! as bool
          : true,
      keepScreenOn:
          json['keepScreenOn'] is bool ? json['keepScreenOn']! as bool : false,
      crashReportingEnabled: json['crashReportingEnabled'] is bool
          ? json['crashReportingEnabled']! as bool
          : false,
      autoBackupEnabled: json['autoBackupEnabled'] is bool
          ? json['autoBackupEnabled']! as bool
          : false,
      autoBackupFolderUri: _optionalString(json['autoBackupFolderUri']),
      autoBackupFolderLabel: _optionalString(json['autoBackupFolderLabel']),
      autoBackupEncryptionPassphrase:
          _optionalString(json['autoBackupEncryptionPassphrase']),
      autoBackupLastRunAt: _optionalDate(json['autoBackupLastRunAt']),
      autoBackupLastSuccessfulRunAt:
          _optionalDate(json['autoBackupLastSuccessfulRunAt']),
      autoBackupLastStatus: _enumValue(
        AutoBackupStatus.values,
        json['autoBackupLastStatus'],
        AutoBackupStatus.idle,
      ),
    );
  }

  static const defaults = AppSettings();

  final AppThemePreference themePreference;
  final UnitSystem unitSystem;
  final WeekStartDay weekStartDay;
  final double defaultWeightIncrement;
  final HomeScreenDisplay homeScreenDisplay;
  final bool prTrackingEnabled;
  final bool markSetsCompleteByDefault;
  final bool autoSelectNextSet;

  /// Device-level (never synced): whether the rest/interval timer plays its
  /// 3-2-1 prepare beep and end alert (paired haptic + notification sound).
  /// When off, cues go silent/visual-only; never bypasses silent mode or DND.
  final bool restTimerSoundsEnabled;
  final bool keepScreenOn;
  final bool crashReportingEnabled;
  final bool autoBackupEnabled;
  final String? autoBackupFolderUri;
  final String? autoBackupFolderLabel;
  final String? autoBackupEncryptionPassphrase;
  final DateTime? autoBackupLastRunAt;
  final DateTime? autoBackupLastSuccessfulRunAt;
  final AutoBackupStatus autoBackupLastStatus;

  bool get autoBackupNeedsFolderGrant =>
      autoBackupEnabled &&
      (autoBackupFolderUri == null ||
          autoBackupLastStatus == AutoBackupStatus.skippedMissingFolderGrant);

  ThemeMode get themeMode {
    return switch (themePreference) {
      AppThemePreference.system => ThemeMode.system,
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
    };
  }

  TrainingDayDate weekStartFor(TrainingDayDate localDate) {
    final date = localDate.toLocalDateTime();
    final startWeekday = weekStartDay.dateTimeWeekday;
    final delta = (date.weekday - startWeekday + 7) % 7;
    return TrainingDayDate.fromDateTime(date.subtract(Duration(days: delta)));
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'themePreference': themePreference.name,
      'unitSystem': unitSystem.name,
      'weekStartDay': weekStartDay.name,
      'defaultWeightIncrement': defaultWeightIncrement,
      'homeScreenDisplay': homeScreenDisplay.name,
      'prTrackingEnabled': prTrackingEnabled,
      'markSetsCompleteByDefault': markSetsCompleteByDefault,
      'autoSelectNextSet': autoSelectNextSet,
      'restTimerSoundsEnabled': restTimerSoundsEnabled,
      'keepScreenOn': keepScreenOn,
      'crashReportingEnabled': crashReportingEnabled,
      'autoBackupEnabled': autoBackupEnabled,
      'autoBackupFolderUri': autoBackupFolderUri,
      'autoBackupFolderLabel': autoBackupFolderLabel,
      'autoBackupEncryptionPassphrase': autoBackupEncryptionPassphrase,
      'autoBackupLastRunAt': autoBackupLastRunAt?.toUtc().toIso8601String(),
      'autoBackupLastSuccessfulRunAt':
          autoBackupLastSuccessfulRunAt?.toUtc().toIso8601String(),
      'autoBackupLastStatus': autoBackupLastStatus.name,
    };
  }

  AppSettings copyWith({
    AppThemePreference? themePreference,
    UnitSystem? unitSystem,
    WeekStartDay? weekStartDay,
    double? defaultWeightIncrement,
    HomeScreenDisplay? homeScreenDisplay,
    bool? prTrackingEnabled,
    bool? markSetsCompleteByDefault,
    bool? autoSelectNextSet,
    bool? restTimerSoundsEnabled,
    bool? keepScreenOn,
    bool? crashReportingEnabled,
    bool? autoBackupEnabled,
    Object? autoBackupFolderUri = _copyWithSentinel,
    Object? autoBackupFolderLabel = _copyWithSentinel,
    Object? autoBackupEncryptionPassphrase = _copyWithSentinel,
    Object? autoBackupLastRunAt = _copyWithSentinel,
    Object? autoBackupLastSuccessfulRunAt = _copyWithSentinel,
    AutoBackupStatus? autoBackupLastStatus,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      unitSystem: unitSystem ?? this.unitSystem,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      defaultWeightIncrement:
          defaultWeightIncrement ?? this.defaultWeightIncrement,
      homeScreenDisplay: homeScreenDisplay ?? this.homeScreenDisplay,
      prTrackingEnabled: prTrackingEnabled ?? this.prTrackingEnabled,
      markSetsCompleteByDefault:
          markSetsCompleteByDefault ?? this.markSetsCompleteByDefault,
      autoSelectNextSet: autoSelectNextSet ?? this.autoSelectNextSet,
      restTimerSoundsEnabled:
          restTimerSoundsEnabled ?? this.restTimerSoundsEnabled,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      crashReportingEnabled:
          crashReportingEnabled ?? this.crashReportingEnabled,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupFolderUri: autoBackupFolderUri == _copyWithSentinel
          ? this.autoBackupFolderUri
          : autoBackupFolderUri as String?,
      autoBackupFolderLabel: autoBackupFolderLabel == _copyWithSentinel
          ? this.autoBackupFolderLabel
          : autoBackupFolderLabel as String?,
      autoBackupEncryptionPassphrase:
          autoBackupEncryptionPassphrase == _copyWithSentinel
              ? this.autoBackupEncryptionPassphrase
              : autoBackupEncryptionPassphrase as String?,
      autoBackupLastRunAt: autoBackupLastRunAt == _copyWithSentinel
          ? this.autoBackupLastRunAt
          : autoBackupLastRunAt as DateTime?,
      autoBackupLastSuccessfulRunAt:
          autoBackupLastSuccessfulRunAt == _copyWithSentinel
              ? this.autoBackupLastSuccessfulRunAt
              : autoBackupLastSuccessfulRunAt as DateTime?,
      autoBackupLastStatus: autoBackupLastStatus ?? this.autoBackupLastStatus,
    );
  }

  /// The account-level half of this settings object, in the storage-layer
  /// `AccountSettings` shape the synced Drift row uses.
  AccountSettings toAccountSettings() {
    return AccountSettings(
      themePreference: themePreference.name,
      unitSystem: unitSystem.name,
      weekStartDay: weekStartDay.name,
      defaultWeightIncrement: defaultWeightIncrement,
      homeScreenDisplay: homeScreenDisplay.name,
      prTrackingEnabled: prTrackingEnabled,
      markSetsCompleteByDefault: markSetsCompleteByDefault,
      autoSelectNextSet: autoSelectNextSet,
    );
  }

  /// Overlays the synced account-level fields onto this object, keeping the
  /// device-level half untouched. Unknown enum strings fall back to the current
  /// value (the row is validated on write, but a forward-compat guard is cheap).
  AppSettings mergeAccountSettings(AccountSettings account) {
    return copyWith(
      themePreference: _enumValue(
        AppThemePreference.values,
        account.themePreference,
        themePreference,
      ),
      unitSystem: _enumValue(
        UnitSystem.values,
        account.unitSystem,
        unitSystem,
      ),
      weekStartDay: _enumValue(
        WeekStartDay.values,
        account.weekStartDay,
        weekStartDay,
      ),
      defaultWeightIncrement: account.defaultWeightIncrement > 0
          ? account.defaultWeightIncrement
          : defaultWeightIncrement,
      homeScreenDisplay: _enumValue(
        HomeScreenDisplay.values,
        account.homeScreenDisplay,
        homeScreenDisplay,
      ),
      prTrackingEnabled: account.prTrackingEnabled,
      markSetsCompleteByDefault: account.markSetsCompleteByDefault,
      autoSelectNextSet: account.autoSelectNextSet,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppSettings &&
            runtimeType == other.runtimeType &&
            themePreference == other.themePreference &&
            unitSystem == other.unitSystem &&
            weekStartDay == other.weekStartDay &&
            defaultWeightIncrement == other.defaultWeightIncrement &&
            homeScreenDisplay == other.homeScreenDisplay &&
            prTrackingEnabled == other.prTrackingEnabled &&
            markSetsCompleteByDefault == other.markSetsCompleteByDefault &&
            autoSelectNextSet == other.autoSelectNextSet &&
            restTimerSoundsEnabled == other.restTimerSoundsEnabled &&
            keepScreenOn == other.keepScreenOn &&
            crashReportingEnabled == other.crashReportingEnabled &&
            autoBackupEnabled == other.autoBackupEnabled &&
            autoBackupFolderUri == other.autoBackupFolderUri &&
            autoBackupFolderLabel == other.autoBackupFolderLabel &&
            autoBackupEncryptionPassphrase ==
                other.autoBackupEncryptionPassphrase &&
            autoBackupLastRunAt == other.autoBackupLastRunAt &&
            autoBackupLastSuccessfulRunAt ==
                other.autoBackupLastSuccessfulRunAt &&
            autoBackupLastStatus == other.autoBackupLastStatus;
  }

  @override
  int get hashCode => Object.hash(
        themePreference,
        unitSystem,
        weekStartDay,
        defaultWeightIncrement,
        homeScreenDisplay,
        prTrackingEnabled,
        markSetsCompleteByDefault,
        autoSelectNextSet,
        restTimerSoundsEnabled,
        keepScreenOn,
        crashReportingEnabled,
        autoBackupEnabled,
        autoBackupFolderUri,
        autoBackupFolderLabel,
        autoBackupEncryptionPassphrase,
        autoBackupLastRunAt,
        autoBackupLastSuccessfulRunAt,
        autoBackupLastStatus,
      );
}

enum AppThemePreference {
  system,
  light,
  dark;

  String get label {
    return switch (this) {
      AppThemePreference.system => 'System',
      AppThemePreference.light => 'Light',
      AppThemePreference.dark => 'Dark',
    };
  }
}

enum UnitSystem {
  metric,
  imperial;

  String get label {
    return switch (this) {
      UnitSystem.metric => 'Metric',
      UnitSystem.imperial => 'Imperial',
    };
  }
}

enum WeekStartDay {
  monday,
  sunday;

  String get label {
    return switch (this) {
      WeekStartDay.monday => 'Monday',
      WeekStartDay.sunday => 'Sunday',
    };
  }

  int get dateTimeWeekday {
    return switch (this) {
      WeekStartDay.monday => DateTime.monday,
      WeekStartDay.sunday => DateTime.sunday,
    };
  }
}

enum HomeScreenDisplay {
  comfortable,
  compact;

  String get label {
    return switch (this) {
      HomeScreenDisplay.comfortable => 'Comfortable',
      HomeScreenDisplay.compact => 'Compact',
    };
  }
}

enum AutoBackupStatus {
  idle,
  succeeded,
  skippedMissingFolderGrant,
  failed,
  unsupported;

  String get label {
    return switch (this) {
      AutoBackupStatus.idle => 'Not run yet',
      AutoBackupStatus.succeeded => 'Backed up',
      AutoBackupStatus.skippedMissingFolderGrant => 'Folder access needed',
      AutoBackupStatus.failed => 'Backup failed',
      AutoBackupStatus.unsupported => 'Unavailable',
    };
  }
}

const _copyWithSentinel = Object();

T _enumValue<T extends Enum>(
  Iterable<T> values,
  Object? rawValue,
  T fallback,
) {
  if (rawValue is! String) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == rawValue) {
      return value;
    }
  }
  return fallback;
}

double _positiveDouble(Object? rawValue, double fallback) {
  final parsed = switch (rawValue) {
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
  if (parsed == null || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

String? _optionalString(Object? rawValue) {
  if (rawValue is String && rawValue.isNotEmpty) {
    return rawValue;
  }
  return null;
}

DateTime? _optionalDate(Object? rawValue) {
  final raw = _optionalString(rawValue);
  if (raw == null) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}
