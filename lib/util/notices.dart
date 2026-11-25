/// Reads the parts of an inbox notification out of the text the server sends.
///
/// The server's notifications carry no structured score or status: a grade
/// arrives as title "Ali Valiyev: yangi baho", body "Lab · 90/100 · 25.11.2026".
/// This picks the pieces back out so the inbox can show a score ring, a
/// status chip or a +/- badge, and it works for rows already in the inbox.
/// Anything it can't read falls back to the plain title and body.
library;

/// What the inbox filters by. Keep in step with the server's notification
/// types (student-events.notifier.ts); anything else is [other].
enum NoticeKind { grade, exam, attendance, behavior, point, other }

class Notice {
  const Notice({
    required this.kind,
    required this.headline,
    this.subject,
    this.details = const [],
    this.score,
    this.maxScore,
    this.points,
    this.status,
    this.positive,
  });

  final NoticeKind kind;

  /// The title without the child's name in front ("yangi baho").
  final String headline;

  /// The lesson's subject, when the body names one.
  final String? subject;

  /// The rest of the body (date, exam period, reason), in order.
  final List<String> details;

  /// Grade or exam score, and what it is out of (null when not given).
  final num? score, maxScore;

  /// Signed points for a [NoticeKind.point] notice ("+3 ball" → 3).
  final int? points;

  /// Attendance status: present, late, absent or excused.
  final String? status;

  /// Behaviour: true for good behaviour, false for a note, null if unknown.
  final bool? positive;

  /// Score as a share of [maxScore] from 0 to 100; grades are out of 100.
  num? get percent {
    final s = score, m = maxScore;
    if (s == null) return null;
    if (m == null || m == 0) return kind == NoticeKind.grade ? s : null;
    return s * 100 / m;
  }

  static Notice parse(Map<String, dynamic> n) {
    final kind = switch ('${n['type'] ?? n['data']?['type'] ?? ''}') {
      'grade' => NoticeKind.grade,
      'exam' => NoticeKind.exam,
      'attendance' => NoticeKind.attendance,
      'behavior' => NoticeKind.behavior,
      'point' => NoticeKind.point,
      _ => NoticeKind.other,
    };
    final title = '${n['title'] ?? ''}'.trim();
    final body = '${n['body'] ?? ''}'.trim();
    // Child notices are titled "<name>: <what>"; the inbox shows the child
    // separately, so the name is dropped. Other notices keep their title.
    final colon = title.indexOf(': ');
    final headline = kind != NoticeKind.other && colon > 0 ? title.substring(colon + 2).trim() : title;
    final parts = body.isEmpty ? <String>[] : body.split(' · ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    switch (kind) {
      case NoticeKind.grade:
      case NoticeKind.exam:
        num? score, max;
        String? subject;
        final rest = <String>[];
        for (final p in parts) {
          final m = _score.firstMatch(p);
          if (score == null && m != null) {
            score = num.parse(m.group(1)!);
            max = m.group(2) == null ? null : num.parse(m.group(2)!);
          } else if (subject == null && rest.isEmpty) {
            subject = p;
          } else {
            rest.add(p);
          }
        }
        return Notice(
          kind: kind,
          headline: headline,
          subject: subject,
          details: rest,
          score: score,
          maxScore: max ?? (kind == NoticeKind.grade && score != null ? 100 : null),
        );
      case NoticeKind.point:
        final m = RegExp(r'^([+\-−]?)\s*(\d+)').firstMatch(headline);
        final points = m == null ? null : int.parse(m.group(2)!) * (m.group(1)!.isEmpty || m.group(1) == '+' ? 1 : -1);
        return Notice(
          kind: kind,
          headline: headline,
          subject: parts.firstOrNull,
          details: parts.skip(1).toList(),
          points: points,
        );
      case NoticeKind.attendance:
        return Notice(
          kind: kind,
          headline: headline,
          details: parts,
          status: _attendance[headline.toLowerCase()],
        );
      case NoticeKind.behavior:
        final h = headline.toLowerCase();
        return Notice(
          kind: kind,
          headline: headline,
          details: parts,
          positive: _goodBehavior.contains(h) ? true : (_behaviorNote.contains(h) ? false : null),
        );
      case NoticeKind.other:
        return Notice(kind: kind, headline: headline, details: parts);
    }
  }

  /// "90/100", "20/40", "85.5" (a score without a maximum).
  static final _score = RegExp(r'^(\d+(?:\.\d+)?)(?:\s*/\s*(\d+(?:\.\d+)?))?$');

  // The server's labels in each language (ATTENDANCE_LABELS, BEHAVIOR_TITLES).
  static const _attendance = {
    'keldi': 'present',
    'kechikdi': 'late',
    'kelmadi': 'absent',
    'sababli': 'excused',
    'присутствует': 'present',
    'опоздание': 'late',
    'отсутствует': 'absent',
    'отсутствует по уважительной причине': 'excused',
    'present': 'present',
    'late': 'late',
    'absent': 'absent',
    'excused absence': 'excused',
  };
  static const _goodBehavior = {'yaxshi xulq', 'хорошее поведение', 'good behaviour'};
  static const _behaviorNote = {"xulq bo'yicha eslatma", 'xulq boʻyicha eslatma', 'замечание по поведению', 'behaviour note'};
}
