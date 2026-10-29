class ValidationException implements Exception {
  const ValidationException(this.message);

  final String message;

  @override
  String toString() => 'ValidationException: $message';
}

class ConflictException implements Exception {
  const ConflictException(this.message);

  final String message;

  @override
  String toString() => 'ConflictException: $message';
}

class NotFoundException implements Exception {
  const NotFoundException(this.message);

  final String message;

  @override
  String toString() => 'NotFoundException: $message';
}

abstract final class ValidationRules {
  static String validateTitle(String value, {String field = 'Title'}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      throw ValidationException('$field must be between 1 and 120 characters.');
    }
    return trimmed;
  }

  static void validateEstimateMinutes(int value) {
    if (value < 5 || value > 2400) {
      throw const ValidationException(
        'Estimate must be between 5 and 2400 minutes.',
      );
    }
  }

  static void validatePriority(int value) {
    if (value < 0 || value > 2) {
      throw const ValidationException('Priority must be 0, 1, or 2.');
    }
  }

  static void validateRemainingMinutes({
    required int remainingMinutes,
    required int estimateMinutes,
  }) {
    if (remainingMinutes < 0 || remainingMinutes > estimateMinutes) {
      throw const ValidationException(
        'Remaining minutes must be between 0 and the estimate.',
      );
    }
  }

  static void validateDailyLimitMinutes(int value) {
    if (value < 15 || value > 720) {
      throw const ValidationException(
        'Daily limit must be between 15 and 720 minutes.',
      );
    }
  }

  static void validateBlockLengthMinutes(int value) {
    if (value < 15 || value > 120) {
      throw const ValidationException(
        'Block length must be between 15 and 120 minutes.',
      );
    }
  }

  static void validateMinSessionMinutes({
    required int minSessionMinutes,
    required int blockLengthMinutes,
  }) {
    if (minSessionMinutes < 5 || minSessionMinutes > blockLengthMinutes ~/ 2) {
      throw ValidationException(
        'Minimum session must be at least 5 and at most half the block length '
        '(${blockLengthMinutes ~/ 2} minutes).',
      );
    }
  }

  static void validateBreakMinutes(int value) {
    if (value < 0 || value > 30) {
      throw const ValidationException(
        'Break must be between 0 and 30 minutes.',
      );
    }
  }

  static void validateHorizonDays(int value) {
    if (value < 7 || value > 30) {
      throw const ValidationException('Horizon must be between 7 and 30 days.');
    }
  }

  static void validateRevisionLengthMinutes(int value) {
    if (value < 10 || value > 60) {
      throw const ValidationException(
        'Revision length must be between 10 and 60 minutes.',
      );
    }
  }

  static void validateDate(String? value, {String field = 'Date'}) {
    if (value == null) {
      return;
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw ValidationException('$field must use YYYY-MM-DD.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw ValidationException('$field must be a valid date.');
    }
  }

  static void validateDateOrder({
    String? earliestDate,
    String? deadlineDate,
    String field = 'Deadline',
  }) {
    if (earliestDate == null || deadlineDate == null) {
      return;
    }
    if (deadlineDate.compareTo(earliestDate) < 0) {
      throw ValidationException('$field cannot be before the earliest date.');
    }
  }

  static void validateSessionTiming({
    required int startMinute,
    required int plannedMinutes,
  }) {
    if (startMinute < 0 || startMinute > 1439) {
      throw const ValidationException(
        'Start minute must be between 0 and 1439.',
      );
    }
    if (plannedMinutes <= 0) {
      throw const ValidationException(
        'Planned minutes must be greater than 0.',
      );
    }
    if (startMinute + plannedMinutes > 1440) {
      throw const ValidationException('A session cannot cross midnight.');
    }
  }

  static void validateActualMinutes(int? value) {
    if (value != null && value < 1) {
      throw const ValidationException('Actual minutes must be at least 1.');
    }
  }

  static void validateTimerSeconds(int value) {
    if (value < 0) {
      throw const ValidationException('Timer seconds cannot be negative.');
    }
  }

  static void validateAvailabilityWindow({
    required int weekday,
    required int startMinute,
    required int endMinute,
  }) {
    if (weekday < 1 || weekday > 7) {
      throw const ValidationException(
        'Weekday must be between 1 (Monday) and 7 (Sunday).',
      );
    }
    if (startMinute < 0 || startMinute > 1439) {
      throw const ValidationException(
        'Window start must be between 0 and 1439.',
      );
    }
    if (endMinute < 1 || endMinute > 1440) {
      throw const ValidationException('Window end must be between 1 and 1440.');
    }
    if (endMinute <= startMinute) {
      throw const ValidationException('Window end must be after its start.');
    }
  }

  static void validateAvailabilityOverlap({
    required int weekday,
    required int startMinute,
    required int endMinute,
    required Iterable<AvailabilityWindowRange> existing,
  }) {
    for (final window in existing) {
      if (window.weekday != weekday) {
        continue;
      }
      if (startMinute < window.endMinute && window.startMinute < endMinute) {
        throw const ValidationException(
          'Availability windows cannot overlap on the same weekday.',
        );
      }
    }
  }
}

typedef AvailabilityWindowRange = ({
  int weekday,
  int startMinute,
  int endMinute,
});
