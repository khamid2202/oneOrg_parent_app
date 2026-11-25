import 'package:flutter_test/flutter_test.dart';
import 'package:oneorg_parents/util/notices.dart';

void main() {
  test('reads a grade', () {
    final n = Notice.parse({
      'type': 'grade',
      'title': 'Abdullahodjayev Muhammadfozil: yangi baho',
      'body': 'Lab · 90/100 · 25.11.2026',
    });
    expect(n.kind, NoticeKind.grade);
    expect(n.headline, 'yangi baho');
    expect(n.subject, 'Lab');
    expect(n.score, 90);
    expect(n.maxScore, 100);
    expect(n.percent, 90);
    expect(n.details, ['25.11.2026']);
  });

  test('reads an exam out of 40, keeping the period', () {
    final n = Notice.parse({
      'type': 'exam',
      'title': 'Ali: imtihon natijasi',
      'body': 'Math · 20/40 · 2-week(November)',
    });
    expect(n.subject, 'Math');
    expect(n.score, 20);
    expect(n.maxScore, 40);
    expect(n.percent, 50);
    expect(n.details, ['2-week(November)']);
  });

  test('an exam score without a maximum has no percent', () {
    final n = Notice.parse({'type': 'exam', 'title': 'Ali: exam result', 'body': 'Math · 85.5'});
    expect(n.score, 85.5);
    expect(n.maxScore, isNull);
    expect(n.percent, isNull);
  });

  test('reads signed points', () {
    expect(Notice.parse({'type': 'point', 'title': 'Ali: +3 ball', 'body': 'Math · Helped'}).points, 3);
    final minus = Notice.parse({'type': 'point', 'title': 'Ali: -2 балла', 'body': 'Math'});
    expect(minus.points, -2);
    expect(minus.subject, 'Math');
  });

  test('reads attendance and behaviour in each language', () {
    expect(Notice.parse({'type': 'attendance', 'title': 'Ali: Kelmadi'}).status, 'absent');
    expect(Notice.parse({'type': 'attendance', 'title': 'Ali: Опоздание'}).status, 'late');
    expect(Notice.parse({'type': 'attendance', 'title': 'Ali: Excused absence'}).status, 'excused');
    expect(Notice.parse({'type': 'behavior', 'title': 'Ali: yaxshi xulq'}).positive, isTrue);
    expect(Notice.parse({'type': 'behavior', 'title': "Ali: xulq bo'yicha eslatma"}).positive, isFalse);
  });

  test('other notices keep their whole title', () {
    final n = Notice.parse({'type': 'general', 'title': 'School: closed on Friday', 'body': 'Holiday'});
    expect(n.kind, NoticeKind.other);
    expect(n.headline, 'School: closed on Friday');
    expect(n.details, ['Holiday']);
  });
}
