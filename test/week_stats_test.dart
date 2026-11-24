import 'package:flutter_test/flutter_test.dart';
import 'package:oneorg_parents/screens/dashboard.dart';

void main() {
  // Week of Monday 2026-11-23; last week starts 2026-11-16.
  final monday = DateTime(2026, 11, 23);
  Map<String, dynamic> row(String date, num score, {String subject = 'Math', String status = 'present'}) =>
      {'date': date, 'score': score, 'subject': subject, 'subject_id': 1, 'attendance_status': status};

  final rows = [
    row('2026-11-16', 80), // last Mon
    row('2026-11-17', 60, status: 'absent'), // last Tue
    row('2026-11-20', 100, subject: 'Art'), // last Fri
    row('2026-11-23', 90), // this Mon
    row('2026-11-24', 70), // this Tue
  ];

  test('on Monday, last week is compared up to Monday only', () {
    final s = WeekStats.from(rows, monday, today: DateTime(2026, 11, 23));
    expect(s.avgBefore, 80);
    expect(s.attendBefore, 100);
    // The chart still has the whole of last week.
    expect(s.previous, [80, 60, null, null, 100]);
    // Art only had a grade later last week, so it is not compared.
    expect(s.subjects.map((x) => x.name), ['Math']);
  });

  test('on Tuesday, Monday–Tuesday against Monday–Tuesday', () {
    final s = WeekStats.from(rows, monday, today: DateTime(2026, 11, 24));
    expect(s.avgNow, 80);
    expect(s.avgBefore, 70);
    expect(s.attendBefore, 50);
    expect(s.subjects.single.before, 70);
  });
}
