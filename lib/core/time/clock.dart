import 'local_date.dart';

abstract class Clock {
  const Clock();

  DateTime get now;

  LocalDate get today {
    final value = now;
    return LocalDate(value.year, value.month, value.day);
  }

  int get nowMinuteOfDay {
    final value = now;
    return value.hour * 60 + value.minute;
  }
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime get now => DateTime.now();
}
