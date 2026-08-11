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

  TrainingDayDate addDays(int days) {
    final next = toLocalDateTime().add(Duration(days: days));
    return TrainingDayDate.fromDateTime(next);
  }

  @override
  int compareTo(TrainingDayDate other) {
    return storageValue.compareTo(other.storageValue);
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
