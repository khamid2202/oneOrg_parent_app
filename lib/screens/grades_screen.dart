import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/children.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/states.dart';
import '../widgets/theme.dart';

typedef Json = Map<String, dynamic>;

enum _Period { thisWeek, lastWeek, days30 }

/// The dates each period asks the server for. Weeks start on Monday.
Map<String, String> _rangeOf(_Period p) {
  final now = DateTime.now();
  final monday = mondayOf(now);
  return switch (p) {
    _Period.thisWeek => {'start_date': iso(monday), 'end_date': today()},
    _Period.lastWeek => {
        'start_date': iso(monday.subtract(const Duration(days: 7))),
        'end_date': iso(monday.subtract(const Duration(days: 1))),
      },
    _Period.days30 => {'start_date': daysAgo(30), 'end_date': today()},
  };
}

/// The five parts of a daily score (20 + 10 + 30 + 20 + 20 = 100). Coming on
/// time adds nothing; coming late takes points off (`attendance_score` ≤ 0).
const _categories = ['materials', 'homework_done', 'homework', 'activity', 'notes'];
const _categoryMax = {'materials': 20, 'homework_done': 10, 'homework': 30, 'activity': 20, 'notes': 20};

/// Lessons graded before grading v2 keep their old numbers: five categories
/// of 20, attendance being one of them, homework not split in two.
bool _isV1(Json row) => asNum(row['grading_version']) == 1;
const _v1Categories = ['attendance', 'materials', 'homework', 'activity', 'notes'];

List<String> _categoriesOf(Json row) => _isV1(row) ? _v1Categories : _categories;

int _maxOf(Json row, String key) => _isV1(row) ? 20 : _categoryMax[key]!;

String _labelOf(Json row, String key) =>
    _isV1(row) && key == 'homework' ? 'grades.category.homeworkOld' : 'grades.category.$key';

/// The Baholar tab, or (with [subjectId]) a pushed page showing only that
/// subject's grades, opened from a lesson in the timetable.
class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key, this.subjectId, this.subjectName});
  final Object? subjectId;
  final String? subjectName;
  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  _Period _period = _Period.thisWeek;
  Object? _subjectId;
  int? _childId;

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final locked = widget.subjectId != null;
    if (_childId != child.id) {
      _childId = child.id;
      _subjectId = widget.subjectId;
      _period = _Period.thisWeek;
    }
    final api = context.read<ParentApi>();
    final range = _rangeOf(_period);

    final page = Query<Json>(
      cacheKey: 'grades:${child.id}:${range['start_date']}:${range['end_date']}:all',
      load: () => api.grades(child.id, {...range, 'limit': 200}),
      builder: (context, allQ) {
        // Every subject of the period, for the filter chips.
        final seen = <Object, String>{};
        for (final row in (allQ.data?['result'] as List? ?? const []).cast<Json>()) {
          final id = row['subject_id'];
          if (id != null) seen.putIfAbsent(id, () => '${row['subject'] ?? ''}');
        }
        final subjects = seen.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            if (!locked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(context.t('nav.grades'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            // On their own line: the week labels are too long to share it with the title.
            PillRow(children: [
              for (final p in _Period.values)
                Pill(
                  label: context.t('grades.period.${p.name}'),
                  selected: _period == p,
                  onTap: () => setState(() => _period = p),
                ),
            ]),
            const SizedBox(height: 12),
            if (!locked && subjects.length > 1) ...[
              PillRow(children: [
                Pill(
                  label: context.t('grades.allSubjects'),
                  selected: _subjectId == null,
                  onTap: () => setState(() => _subjectId = null),
                ),
                for (final s in subjects)
                  Pill(label: s.value, selected: _subjectId == s.key, onTap: () => setState(() => _subjectId = s.key)),
              ]),
              const SizedBox(height: 12),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _subjectId == null
                  ? _body(allQ)
                  : Query<Json>(
                      cacheKey: 'grades:${child.id}:${range['start_date']}:${range['end_date']}:$_subjectId',
                      load: () => api.grades(child.id, {...range, 'subject_id': _subjectId, 'limit': 200}),
                      builder: (context, q) => _body(q),
                    ),
            ),
          ],
        );
      },
    );
    if (!locked) return page;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName ?? context.t('nav.grades'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: context.c.line),
        ),
      ),
      body: page,
    );
  }

  Widget _body(Snap<Json> q) {
    if (q.loading) return const LoadingState();
    final data = q.data;
    if (data == null) return ErrorState(error: q.error, onRetry: q.reload);
    final rows = (data['result'] as List? ?? const []).cast<Json>();
    if (rows.isEmpty) return EmptyState(text: context.t('grades.empty'));
    final summary = (data['meta'] as Map?)?['summary'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((asNum(summary?['lessons']) ?? 0) > 0) ...[_Summary(summary: summary!), const SizedBox(height: 16)],
        for (final (i, day) in _byDay(rows).indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          _DayHeader(day: day.key, rows: day.value),
          PanelList(children: [for (final r in day.value) _GradeRow(key: ValueKey(r['lesson_instance_id']), row: r)]),
        ],
      ],
    );
  }

  /// Lessons grouped by day, newest day first, keeping the server's order inside a day.
  static List<MapEntry<String, List<Json>>> _byDay(List<Json> rows) {
    final days = <String, List<Json>>{};
    for (final r in rows) {
      days.putIfAbsent(dayOf(r['date']), () => []).add(r);
    }
    return days.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
  }
}

/// "Juma, 20 noyabr" with that day's average score on the right.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.rows});
  final String day;
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final scores = [for (final r in rows) asNum(r['score'])].whereType<num>().toList();
    final avg = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(day.isEmpty ? '—' : Fmt(context.lang).dayLong(day),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.c.muted)),
          ),
          if (avg != null)
            Text(fmtNum(avg.round()),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor(context, avg))),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});
  final Map summary;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final avg = asNum(summary['average_score']) ?? 0;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('grades.average'), style: TextStyle(fontSize: 12, color: c.muted)),
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${avg.round()}',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: scoreColor(context, avg))),
                      TextSpan(text: ' / 100', style: TextStyle(fontSize: 16, color: c.muted)),
                    ])),
                  ],
                ),
              ),
              Text(context.t('grades.lessons', {'count': summary['lessons']}),
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          // Category averages count new-scheme lessons only: none in this
          // period (only older lessons) means no bars, not bars at 0.
          if (summary['average_materials'] != null) const SizedBox(height: 12),
          if (summary['average_materials'] != null)
          for (final key in _categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Builder(builder: (context) {
                final value = (asNum(summary['average_$key']) ?? 0).toDouble();
                return Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(context.t('grades.category.$key'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (value / _categoryMax[key]!).clamp(0, 1),
                          minHeight: 6,
                          backgroundColor: c.sunken,
                          color: c.accent,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${value.round()}/${_categoryMax[key]}',
                          textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                );
              }),
            ),
          if ((asNum(summary['average_attendance']) ?? 0) < 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.t('grades.lateAverage', {
                  'points': (-(asNum(summary['average_attendance']) ?? 0)).toStringAsFixed(1),
                }),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _GradeRow extends StatefulWidget {
  const _GradeRow({super.key, required this.row});
  final Json row;
  @override
  State<_GradeRow> createState() => _GradeRowState();
}

class _GradeRowState extends State<_GradeRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final c = context.c;
    final f = Fmt(context.lang);
    final score = asNum(row['score']);
    final madeUp = row['is_made_up'] == true;
    final status = row['attendance_status'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${row['subject'] ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (status != null && status != 'present')
                            AttendanceBadge(status: status, minutesLate: row['minutes_late']),
                          if (!_isV1(row) && (asNum(row['attendance_score']) ?? 0) < 0)
                            Text(fmtNum(row['attendance_score']),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (madeUp)
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: fmtNum(row['total'] ?? 0),
                        style: TextStyle(color: c.muted, decoration: TextDecoration.lineThrough)),
                    const TextSpan(text: ' → '),
                    TextSpan(
                        text: fmtNum(score),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scoreColor(context, score))),
                  ]))
                else
                  Text(fmtNum(score),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scoreColor(context, score))),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more, size: 20, color: c.muted),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final (i, key) in _categoriesOf(row).indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                          decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            children: [
                              Text('${fmtNum(row['${key}_score'])}/${_maxOf(row, key)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(context.t(_labelOf(row, key)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: c.muted)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (madeUp && row['makeup_at'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.t('grades.madeUp', {
                        'date': f.day(DateTime.parse('${row['makeup_at']}').toLocal()),
                        'score': fmtNum(row['makeup_score']),
                      }),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ),
                if (row['comment'] != null && '${row['comment']}'.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(8)),
                    child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12), children: [
                      TextSpan(text: '${context.t('grades.comment')}: ', style: TextStyle(color: c.muted)),
                      TextSpan(text: '${row['comment']}'),
                    ])),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
