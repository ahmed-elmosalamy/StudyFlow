import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/core/time/local_date.dart';

void main() {
  group('LocalDate parsing and formatting', () {
    test('parses YYYY-MM-DD and formats with padding', () {
      final date = LocalDate.parse('2026-10-29');

      expect(date.year, 2026);
      expect(date.month, 10);
      expect(date.day, 29);
      expect(date.toString(), '2026-10-29');
      expect(LocalDate(2026, 1, 5).toString(), '2026-01-05');
    });

    test('rejects malformed and impossible dates', () {
      for (final value in [
        '2026-1-01',
        '2026-01-1',
        '2026/01/01',
        'not-a-date',
        '2026-02-30',
        '2026-13-01',
      ]) {
        expect(
          () => LocalDate.parse(value),
          throwsFormatException,
          reason: value,
        );
      }
      expect(() => LocalDate(2026, 2, 30), throwsArgumentError);
    });
  });

  group('LocalDate arithmetic', () {
    test('addDays crosses month and year boundaries', () {
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2024, 2, 28).addDays(1), LocalDate(2024, 2, 29));
      expect(LocalDate(2024, 3, 1).addDays(-1), LocalDate(2024, 2, 29));
      expect(LocalDate(2026, 10, 29).addDays(0), LocalDate(2026, 10, 29));
    });
  });

  group('LocalDate weekday', () {
    test('uses ISO-8601 numbering from Monday to Sunday', () {
      expect(LocalDate(2026, 10, 26).weekday, 1);
      expect(LocalDate(2026, 10, 29).weekday, 4);
      expect(LocalDate(2026, 11, 1).weekday, 7);
    });
  });

  group('LocalDate comparisons', () {
    test('compares calendar days', () {
      final earlier = LocalDate(2026, 10, 28);
      final later = LocalDate(2026, 10, 29);

      expect(earlier.isBefore(later), isTrue);
      expect(later.isBefore(earlier), isFalse);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier.isAfter(later), isFalse);
      expect(earlier.isSameDay(LocalDate(2026, 10, 28)), isTrue);
      expect(earlier.isSameDay(later), isFalse);
      expect(earlier.compareTo(later), lessThan(0));
    });
  });
}
