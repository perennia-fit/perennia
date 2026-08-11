import 'package:flutter/foundation.dart';

/// The account-level half of the user's Settings, the portion that
/// syncs as a singleton row and is agent-writable. Device-level settings
/// (screen-on, crash reporting, auto-backup) are deliberately absent — they
/// stay in the local JSON file with no server row.
///
/// This is a storage-layer value (snake_case-free, string-typed enums) so the
/// `data/` layer never imports the `features/settings` `AppSettings` type; the
/// settings repository merges this into `AppSettings` at load and splits it back
/// out at save. Values are stored exactly as chosen (self-description).
@immutable
class AccountSettings {
  const AccountSettings({
    required this.themePreference,
    required this.unitSystem,
    required this.weekStartDay,
    required this.defaultWeightIncrement,
    required this.homeScreenDisplay,
    required this.prTrackingEnabled,
    required this.markSetsCompleteByDefault,
    required this.autoSelectNextSet,
  });

  /// Canonical defaults, identical to `AppSettings.defaults`' account half and
  /// the server `AGENT_SETTINGS_DEFAULTS`.
  static const defaults = AccountSettings(
    themePreference: 'system',
    unitSystem: 'metric',
    weekStartDay: 'monday',
    defaultWeightIncrement: 2.5,
    homeScreenDisplay: 'comfortable',
    prTrackingEnabled: true,
    markSetsCompleteByDefault: false,
    autoSelectNextSet: true,
  );

  final String themePreference;
  final String unitSystem;
  final String weekStartDay;
  final double defaultWeightIncrement;
  final String homeScreenDisplay;
  final bool prTrackingEnabled;
  final bool markSetsCompleteByDefault;
  final bool autoSelectNextSet;

  AccountSettings copyWith({
    String? themePreference,
    String? unitSystem,
    String? weekStartDay,
    double? defaultWeightIncrement,
    String? homeScreenDisplay,
    bool? prTrackingEnabled,
    bool? markSetsCompleteByDefault,
    bool? autoSelectNextSet,
  }) {
    return AccountSettings(
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
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AccountSettings &&
            runtimeType == other.runtimeType &&
            themePreference == other.themePreference &&
            unitSystem == other.unitSystem &&
            weekStartDay == other.weekStartDay &&
            defaultWeightIncrement == other.defaultWeightIncrement &&
            homeScreenDisplay == other.homeScreenDisplay &&
            prTrackingEnabled == other.prTrackingEnabled &&
            markSetsCompleteByDefault == other.markSetsCompleteByDefault &&
            autoSelectNextSet == other.autoSelectNextSet;
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
      );
}
