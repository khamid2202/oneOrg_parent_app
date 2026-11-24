import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../l10n/strings.dart';
import '../state/children.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/theme.dart';
import 'grades_screen.dart';

typedef Json = Map<String, dynamic>;

/// What changed about a lesson: "cancel", "cover", "merge", or null.
String? lessonChange(Json lesson) {
  final sub = lesson['substitution'];
  if (sub is Map && sub['type'] != null) return '${sub['type']}';
  return lesson['status'] == 'cancelled' ? 'cancel' : null;
}

List<Json> _list(Object? v) => (v as List? ?? const []).cast<Json>();

/// The week as a strip of days, a points/average line, then the chosen day
/// as a timeline: times on the left, each lesson a card with its grade.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _date = DateTime.now();

  static bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _go(DateTime d) => setState(() => _date = d);

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);
    final c = context.c;
    final now = DateTime.now();
    final day = iso(_date);
    final monday = mondayOf(_date);
    final from = iso(monday), to = iso(monday.add(const Duration(days: 6)));
    final thisDay = today();

    // One request each for the week: grades (badges + average) and events (day marks).
    return Query<Json>(
      cacheKey: 'grades:${child.id}:week:$from',
      load: () => api.grades(child.id, {'start_date': from, 'end_date': to, 'limit': 200}),
      builder: (context, gradesQ) => Query<Json>(
        cacheKey: 'calendar:${child.id}:week:$from',
        load: () => api.calendar(child.id, from, to),
        builder: (context, eventsQ) {
          final events = _list(eventsQ.data?['result']);
          final grades = _list(gradesQ.data?['result']);
          final average = asNum(((gradesQ.data?['meta'] as Map?)?['summary'] as Map?)?['average_score']);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(context.t('schedule.heading'),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text(f.month(_date), style: TextStyle(fontSize: 14, color: c.muted))),
                  if (!_same(_date, now))
                    Pill(label: context.t('common.today'), selected: false, onTap: () => _go(now)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.t('common.previous'),
                    onPressed: () => _go(_date.subtract(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.t('common.next'),
                    onPressed: () => _go(_date.add(const Duration(days: 7))),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 3, right: i == 6 ? 0 : 3),
                        child: _DayChip(
                          date: monday.add(Duration(days: i)),
                          selected: _same(monday.add(Duration(days: i)), _date),
                          today: _same(monday.add(Duration(days: i)), now),
                          hasEvent: events.any((e) => _covers(e, monday.add(Duration(days: i)))),
                          onTap: () => _go(monday.add(Duration(days: i))),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Query<Json>(
                    cacheKey: 'ranking:${child.id}:${thisDay.substring(0, 7)}',
                    load: () => api.ranking(child.id, iso(DateTime(now.year, now.month)), thisDay),
                    builder: (context, q) {
                      final points = asNum((q.data?['meta'] as Map?)?['current_student_points']);
                      return Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text(
                            context.t('schedule.points', {'n': points == null ? '—' : fmtNum(points)}),
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: c.muted),
                      children: [
                        TextSpan(text: '${context.t('schedule.weekAverage')}: '),
                        TextSpan(
                          text: average == null ? '—' : '${average.round()}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: scoreColor(context, average)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              QueryView<Json>(
                cacheKey: 'schedule:${child.id}:$day',
                load: () => api.schedule(child.id, day),
                isEmpty: (d) => _lessons(d).isEmpty,
                emptyText: context.t('schedule.empty'),
                builder: (context, data, _) {
                  final lessons = _lessons(data)
                    ..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
                  final scores = _scoresFor(day, grades);
                  return Column(
                    children: [
                      for (final (i, l) in lessons.indexed)
                        _TimelineRow(
                          lesson: l,
                          score: l['lesson_type'] == 'text' ? null : scores['${l['subject']}']?.removeAt(0),
                          first: i == 0,
                          last: i == lessons.length - 1,
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// The day's scores per subject, in lesson order. Grades carry no time, so a
  /// subject taught twice that day gets its scores oldest first.
  static Map<String, List<num?>> _scoresFor(String day, List<Json> grades) {
    final out = <String, List<num?>>{};
    for (final g in grades.reversed) {
      if (g['date'] != day) continue;
      (out['${g['subject']}'] ??= []).add(asNum(g['score']));
    }
    return out;
  }

  static bool _covers(Json e, DateTime day) {
    final start = DateTime.tryParse('${e['start_date']}'.split('T').first);
    final end = DateTime.tryParse('${e['end_date'] ?? e['start_date']}'.split('T').first) ?? start;
    if (start == null || end == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static List<Json> _lessons(Json data) => _list((data['result'] as Map?)?['lessons']).toList();
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.selected,
    required this.today,
    required this.hasEvent,
    required this.onTap,
  });
  final DateTime date;
  final bool selected, today, hasEvent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = Fmt(context.lang);
    final sunday = date.weekday == DateTime.sunday;
    final fg = selected ? Colors.white : (sunday ? c.muted : c.ink);
    return Material(
      color: selected ? c.accent : c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.accent : (today ? c.accent : c.line), width: today && !selected ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Text(f.weekday(date), style: TextStyle(fontSize: 12, color: selected ? Colors.white70 : c.muted)),
              const SizedBox(height: 2),
              Text('${date.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
              const SizedBox(height: 3),
              // A school event that day (holiday, exam, trip).
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasEvent ? (selected ? Colors.white : const Color(0xFFF59E0B)) : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Start and end time on the left, a dotted rail, then the lesson card.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.lesson, required this.score, required this.first, required this.last});
  final Json lesson;
  final num? score;
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isBreak = lesson['lesson_type'] == 'text';
    const timeStyle = TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(hm(lesson['start_time']), style: timeStyle.copyWith(color: c.ink, fontWeight: FontWeight.w600)),
                  Text(hm(lesson['end_time']), style: timeStyle.copyWith(color: c.muted)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: CustomPaint(painter: _RailPainter(color: c.line, dot: isBreak ? c.line : c.accent, first: first, last: last)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: isBreak ? _BreakCard(lesson: lesson) : _LessonCard(lesson: lesson, score: score),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.color, required this.dot, required this.first, required this.last});
  final Color color, dot;
  final bool first, last;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const top = 8.0;
    final bottom = size.height - 12 - 6;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, first ? top : 0), Offset(x, last ? bottom : size.height), line);
    canvas.drawCircle(Offset(x, top), 5, Paint()..color = dot);
    canvas.drawCircle(Offset(x, bottom), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color || old.dot != dot || old.first != first || old.last != last;
}

/// A break or other plain timetable line ("Nonushta").
class _BreakCard extends StatelessWidget {
  const _BreakCard({required this.lesson});
  final Json lesson;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.local_cafe_outlined, size: 18, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${lesson['text'] ?? lesson['time_slot'] ?? ''}',
                style: TextStyle(fontSize: 13, color: c.muted)),
          ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson, required this.score});
  final Json lesson;
  final num? score;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final change = lessonChange(lesson);
    final cancelled = change == 'cancel';
    final sub = lesson['substitution'] as Map?;
    final substitute = sub?['substitute_teacher'] as String?;
    final teacher = lesson['teacher'] as String?;
    final room = lesson['room'];
    final title = lesson['subject'] ?? lesson['time_slot'] ?? context.t('schedule.lesson');
    final changeColor = cancelled ? const Color(0xFFF43F5E) : const Color(0xFFF59E0B);
    final subjectId = lesson['subject_id'];
    // Tapping a lesson shows that subject's grades.
    final VoidCallback? open = subjectId == null
        ? null
        : () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => GradesScreen(subjectId: subjectId, subjectName: '$title'),
            ));

    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: [
          if (!dark) BoxShadow(color: c.accent.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('$title',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cancelled ? c.muted : c.ink,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    )),
              ),
              if (score != null) _ScoreBadge(score: score!),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.school_outlined, size: 16, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13, color: c.muted),
                    children: [
                      if (substitute != null && !cancelled) ...[
                        TextSpan(text: teacher ?? '', style: const TextStyle(decoration: TextDecoration.lineThrough)),
                        TextSpan(text: ' → $substitute'),
                      ] else
                        TextSpan(text: teacher ?? ''),
                      if (room != null && '$room'.isNotEmpty)
                        TextSpan(text: '${teacher != null ? ' · ' : ''}${context.t('schedule.room', {'room': room})}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (open != null) Icon(Icons.chevron_right, size: 20, color: c.muted),
            ],
          ),
          if (change != null) ...[
            const SizedBox(height: 8),
            Badge2(
              text: context.t(kStrings['en']!.containsKey('schedule.change.$change')
                  ? 'schedule.change.$change'
                  : 'schedule.change.cover'),
              bg: changeColor.withValues(alpha: dark ? 0.2 : 0.12),
              fg: dark ? Color.lerp(changeColor, Colors.white, 0.35)! : Color.lerp(changeColor, Colors.black, 0.25)!,
            ),
          ],
          if (sub?['note'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${sub!['note']}', style: TextStyle(fontSize: 12, color: c.muted)),
            ),
        ],
      ),
    );
    if (open == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: open, child: card),
    );
  }
}

/// The lesson's score out of 100, coloured like everywhere else.
class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final num score;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: scoreColor(context, score), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 3),
            Text(fmtNum(score),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );
}
