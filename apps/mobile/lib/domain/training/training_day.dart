class TrainingDayDate implements Comparable<TrainingDayDate> {
  const TrainingDayDate({
    required this.year,
    required this.month,
    required this.day,
  })  : assert(month >= 1 && month <= 12),
        assert(day >= 1 && day <= 31);

  factory TrainingDayDate.fromDateTime(DateTime value) {
    final local = value.toLocal();
    return TrainingDayDate(
      year: local.year,
      month: local.month,
      day: local.day,
    );
  }

  factory TrainingDayDate.parse(String value) {
    final match = _storagePattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Expected a YYYY-MM-DD training day.', value);
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Invalid training day date.', value);
    }

    return TrainingDayDate(year: year, month: month, day: day);
  }

  static final _storagePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  String get storageValue {
    final paddedYear = year.toString().padLeft(4, '0');
    final paddedMonth = month.toString().padLeft(2, '0');
    final paddedDay = day.toString().padLeft(2, '0');
    return '$paddedYear-$paddedMonth-$paddedDay';
  }

  DateTime toLocalDateTime() => DateTime(year, month, day);

  DateTime atLocalTimeOf(DateTime timeOfDay) {
    return DateTime(
      year,
      month,
      day,
      timeOfDay.hour,
      timeOfDay.minute,
      timeOfDay.second,
      timeOfDay.millisecond,
      timeOfDay.microsecond,
    );
  }

  /// This date as UTC midnight, where the calendar arithmetic below runs, as
  /// `ProtocolDayDate`'s does: adding whole days to a local midnight would
  /// land on the wrong date whenever the span crosses a daylight-saving
  /// change.
  DateTime utcMidnight() => DateTime.utc(year, month, day);

  /// The date [days] calendar days after this one (before it, when negative).
  TrainingDayDate addDays(int days) {
    final next = DateTime.utc(year, month, day + days);
    return TrainingDayDate(year: next.year, month: next.month, day: next.day);
  }

  /// The number of calendar days from [other] to this date: positive when
  /// this date is later, so `other.addDays(daysBetween(other)) == this`.
  int daysBetween(TrainingDayDate other) {
    return utcMidnight().difference(other.utcMidnight()).inDays;
  }

  /// The ISO 8601 weekday of this date: 1 is Monday and 7 is Sunday.
  int get isoWeekday => utcMidnight().weekday;

  /// Calendar order, compared field by field so it never builds a string.
  @override
  int compareTo(TrainingDayDate other) {
    if (year != other.year) {
      return year.compareTo(other.year);
    }
    if (month != other.month) {
      return month.compareTo(other.month);
    }
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TrainingDayDate &&
            runtimeType == other.runtimeType &&
            year == other.year &&
            month == other.month &&
            day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => storageValue;
}
