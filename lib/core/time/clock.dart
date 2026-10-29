import 'local_date.dart';

abstract class Clock {
  LocalDate get today;

  int get nowMinuteOfDay;
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  LocalDate get today {
    final now = DateTime.now();
    return LocalDate(now.year, now.month, now.day);
  }

  @override
  int get nowMinuteOfDay {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }
}
