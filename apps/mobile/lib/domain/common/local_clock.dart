/// Local clock and local date rules shared by every authored domain that
/// stores an instant with a frozen UTC offset (Doses, Meals).
///
/// This library depends on no domain types, so nutrition and protocols code
/// can both use it without depending on each other. The server twin of
/// [localDateAtOffset] is `localDateAtOffset` in `apps/server/src/timezone.ts`;
/// the golden vector `m39-meal-validation.json` pins the two.
library;

/// The clock reading of [instant] where it was taken (D2): the instant at the
/// frozen [timezoneOffsetMinutes], as a UTC `DateTime` whose fields are that
/// clock, so formatting and date parts read them as they are. With a null
/// offset (an event with a frozen offset logged before offsets were recorded)
/// it is [instant] in the device's current zone, as a local `DateTime`.
///
/// The one place an event's clock is worked out. A Dose's row, its edit sheet
/// and the local date `editDose` freezes all read it here, so a fix here
/// reaches every reader at once and a row can never disagree with its edit
/// sheet about when the Dose was taken.
DateTime clockAtOffset(DateTime instant, int? timezoneOffsetMinutes) {
  return timezoneOffsetMinutes == null
      ? instant.toLocal()
      : instant.toUtc().add(Duration(minutes: timezoneOffsetMinutes));
}

/// The calendar date of [instant] read at the frozen [offsetMinutes]: the
/// date parts of [clockAtOffset]. A null offset (a Meal written before
/// offsets were recorded) uses the device's current zone.
///
/// This is the single rule that writes `meals.local_date` in the app: a Meal's
/// local date is always derived from its `started_at` and its frozen offset,
/// never set on its own. It returns a plain record so this library needs no
/// nutrition types; nutrition code wraps it in a `NutritionDayDate`.
///
/// The TypeScript twin is `localDateAtOffset` in `apps/server/src/timezone.ts`,
/// and both are pinned by the golden vector `m39-meal-validation.json`.
({int year, int month, int day}) localDateAtOffset(
  DateTime instant,
  int? offsetMinutes,
) {
  final clock = clockAtOffset(instant, offsetMinutes);
  return (year: clock.year, month: clock.month, day: clock.day);
}
