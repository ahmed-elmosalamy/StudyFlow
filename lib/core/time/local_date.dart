final class LocalDate implements Comparable<LocalDate> {
  factory LocalDate(int year, int month, int day) {
    if (!_isValid(year, month, day)) {
      throw ArgumentError('Invalid local date: $year-$month-$day.');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  factory LocalDate.parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Local date must use YYYY-MM-DD.', value);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (!_isValid(year, month, day)) {
      throw FormatException('Invalid local date.', value);
    }
    return LocalDate._(year, month, day);
  }

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  static bool _isValid(int year, int month, int day) {
    final normalized = DateTime.utc(year, month, day);
    return normalized.year == year &&
        normalized.month == month &&
        normalized.day == day;
  }

  LocalDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day).add(Duration(days: days));
    return LocalDate(shifted.year, shifted.month, shifted.day);
  }

  bool isBefore(LocalDate other) => compareTo(other) < 0;

  bool isAfter(LocalDate other) => compareTo(other) > 0;

  bool isSameDay(LocalDate other) => compareTo(other) == 0;

  int get weekday => DateTime.utc(year, month, day).weekday;

  @override
  int compareTo(LocalDate other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) {
      return byYear;
    }
    final byMonth = month.compareTo(other.month);
    if (byMonth != 0) {
      return byMonth;
    }
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is LocalDate &&
        other.year == year &&
        other.month == month &&
        other.day == day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() {
    final paddedYear = year.toString().padLeft(4, '0');
    final paddedMonth = month.toString().padLeft(2, '0');
    final paddedDay = day.toString().padLeft(2, '0');
    return '$paddedYear-$paddedMonth-$paddedDay';
  }
}
