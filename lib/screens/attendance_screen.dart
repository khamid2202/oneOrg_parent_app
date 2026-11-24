import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/children.dart';
import '../util/dates.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/states.dart';
import '../widgets/theme.dart';

typedef Json = Map<String, dynamic>;

const _statuses = ['present', 'late', 'absent', 'excused'];

const _icons = {
  'present': Icons.check_circle_outline,
  'late': Icons.schedule,
  'absent': Icons.cancel_outlined,
  'excused': Icons.assignment_turned_in_outlined,
};

/// Every lesson of [from]..[to] with its attendance mark. Attendance is taken
/// per lesson and comes with the lesson's grade row (docs/parent/grades.md);
/// absent and excused lessons get a fixed 0, so they are listed too.
Future<List<Json>> _loadLessons(ParentApi api, int childId, String from, String to) async {
  const limit = 200;
  final rows = <Json>[];
  for (var page = 1; page <= 10; page++) {
    final data = await api.grades(childId, {'start_date': from, 'end_date': to, 'limit': limit, 'page': page});
    final batch = (data['result'] as List? ?? const []).cast<Json>();
    rows.addAll(batch);
    final total = asNum((data['meta'] as Map?)?['total']) ?? rows.length;
    if (batch.length < limit || rows.length >= total) break;
  }
  return rows.where((r) => _statuses.contains(r['attendance_status'])).toList();
}

enum _Period { thisWeek, lastWeek, days30 }

/// One period, the one before it to compare with, and the days to draw.
class _Range {
  _Range(this.period) {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final monday = mondayOf(now);
    switch (period) {
      case _Period.thisWeek:
        start = monday;
        end = day0;
        // Last week up to the same weekday; the chart still shows all of it.
        prevStart = monday.subtract(const Duration(days: 7));
        prevEnd = day0.subtract(const Duration(days: 7));
        span = 5;
      case _Period.lastWeek:
        start = monday.subtract(const Duration(days: 7));
        end = monday.subtract(const Duration(days: 1));
        prevStart = monday.subtract(const Duration(days: 14));
        prevEnd = monday.subtract(const Duration(days: 8));
        span = 5;
      case _Period.days30:
        start = day0.subtract(const Duration(days: 29));
        end = day0;
        prevStart = day0.subtract(const Duration(days: 59));
        prevEnd = day0.subtract(const Duration(days: 30));
        span = 30;
    }
  }

  final _Period period;
  late final DateTime start, end, prevStart, prevEnd;

  /// Days on the chart: Mon–Fri for a week (the weekend added when it had
  /// lessons), every calendar day for 30 days.
  late final int span;

  bool get weekly => period != _Period.days30;

  /// What to load: the period before through this one, in one go.
  String get from => iso(prevStart);
  String get to => iso(end);
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  _Period _period = _Period.thisWeek;
  String? _subject;
  int? _childId;

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    if (_childId != child.id) {
      _childId = child.id;
      _period = _Period.thisWeek;
      _subject = null;
    }
    final api = context.read<ParentApi>();
    final range = _Range(_period);

    return Query<List<Json>>(
      cacheKey: 'attendance-lessons:${child.id}:${range.from}:${range.to}',
      load: () => _loadLessons(api, child.id, range.from, range.to),
      builder: (context, q) {
        final all = q.data;
        final subjects = <String>{for (final r in all ?? const <Json>[]) '${r['subject'] ?? ''}'}.toList()..sort();
        final rows = _subject == null ? all : all?.where((r) => '${r['subject'] ?? ''}' == _subject).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                context.t('nav.attendance'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            PillRow(
              children: [
                for (final p in _Period.values)
                  Pill(
                    label: context.t('grades.period.${p.name}'),
                    selected: p == _period,
                    onTap: () => setState(() => _period = p),
                  ),
              ],
            ),
            if (subjects.length > 1) ...[
              const SizedBox(height: 8),
              PillRow(
                children: [
                  Pill(
                    label: context.t('grades.allSubjects'),
                    selected: _subject == null,
                    onTap: () => setState(() => _subject = null),
                  ),
                  for (final s in subjects)
                    Pill(label: s, selected: s == _subject, onTap: () => setState(() => _subject = s)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: q.error != null && all == null
                  ? ErrorState(error: q.error, onRetry: q.reload)
                  : _Body(range: range, rows: rows, loading: q.loading, subjectFiltered: _subject != null),
            ),
          ],
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.range, required this.rows, required this.loading, required this.subjectFiltered});
  final _Range range;
  final List<Json>? rows;
  final bool loading;
  final bool subjectFiltered;

  static bool _came(Json r) => r['attendance_status'] == 'present' || r['attendance_status'] == 'late';
  static double? _rate(Iterable<Json> rows) => rows.isEmpty ? null : 100 * rows.where(_came).length / rows.length;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = Fmt(context.lang);
    final all = rows;
    if (all == null) return const Padding(padding: EdgeInsets.only(top: 40), child: LoadingState());

    bool inside(Json r, DateTime a, DateTime b) {
      final d = toDate(r['date']);
      return !d.isBefore(a) && !d.isAfter(b);
    }

    final now = all.where((r) => inside(r, range.start, range.end)).toList();
    final before = all.where((r) => inside(r, range.prevStart, range.prevEnd)).toList();
    // The chart's dashed line: the whole previous week, even past today's weekday.
    final prevDrawn = range.period == _Period.thisWeek
        ? all.where((r) => inside(r, range.prevStart, range.start.subtract(const Duration(days: 1)))).toList()
        : before;

    // Days on the chart.
    var span = range.span;
    if (range.weekly) {
      for (final i in [5, 6]) {
        final hasLessons = [...now, ...prevDrawn].any((r) => toDate(r['date']).weekday - 1 == i);
        if (hasLessons) span = i + 1;
      }
    }
    final days = [for (var i = 0; i < span; i++) DateTime(range.start.year, range.start.month, range.start.day + i)];
    final prevDays = [
      for (var i = 0; i < span; i++) DateTime(range.prevStart.year, range.prevStart.month, range.prevStart.day + i),
    ];
    List<Json> on(List<Json> list, DateTime d) => list.where((r) => toDate(r['date']) == d).toList();

    final today = DateTime.now();
    final todayIndex = days.indexWhere((d) => d.year == today.year && d.month == today.month && d.day == today.day);
    final rate = _rate(now), rateBefore = _rate(before);
    final labels = [for (final d in days) range.weekly ? f.weekday(d) : '${d.day}'];
    final changeKey = 'attendance.vs.${range.period.name}';

    if (now.isEmpty && before.isEmpty && !loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(text: context.t('attendance.empty'), icon: Icons.event_busy),
      );
    }

    final byStatus = {for (final s in _statuses) s: now.where((r) => r['attendance_status'] == s).toList()};
    final byStatusBefore = {for (final s in _statuses) s: before.where((r) => r['attendance_status'] == s).length};
    final periodTitle = context.t('grades.period.${range.period.name}');

    Widget card(String status) => Expanded(
      child: _StatusCard(
        status: status,
        count: byStatus[status]!.length,
        // Counts only compare finished periods: today's lessons are still coming.
        before: before.isEmpty || range.period == _Period.thisWeek ? null : byStatusBefore[status],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AttendanceDetailScreen(status: status, period: periodTitle, rows: byStatus[status]!),
          ),
        ),
      ),
    );

    // Per subject: this period's rate over the previous one's.
    final subjectNames = <String>{for (final r in now) '${r['subject'] ?? ''}'}.toList();
    final subjectRows = [
      for (final name in subjectNames)
        (
          name: name,
          now: _rate(now.where((r) => '${r['subject'] ?? ''}' == name)),
          before: _rate(before.where((r) => '${r['subject'] ?? ''}' == name)),
        ),
    ]..sort((a, b) => (a.now ?? 0).compareTo(b.now ?? 0));

    String describe(int i) {
      final list = on(now, days[i]);
      if (list.isEmpty) return '${f.dayLong(days[i])} · —';
      final parts = [
        for (final s in _statuses)
          if (list.any((r) => r['attendance_status'] == s))
            '${list.where((r) => r['attendance_status'] == s).length} ${context.t('attendance.status.$s').toLowerCase()}',
      ];
      return '${f.day(days[i])} · ${parts.join(', ')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroChartCard(
          title: context.t('attendance.rate'),
          value: rate,
          before: rateBefore,
          loading: loading,
          unit: '%',
          badge: now.isEmpty
              ? null
              : context.t('attendance.attendedShort', {'present': now.where(_came).length, 'total': now.length}),
          note: now.isEmpty && !loading ? context.t('attendance.emptyYet') : null,
          current: [for (final (i, d) in days.indexed) (todayIndex >= 0 && i > todayIndex) ? null : _rate(on(now, d))],
          previous: [for (final d in prevDays) _rate(on(prevDrawn, d))],
          labels: labels,
          todayIndex: todayIndex >= 0 ? todayIndex : null,
          labelEvery: range.weekly ? 1 : 5,
          currentLabel: periodTitle,
          previousLabel: context.t('attendance.prev.${range.period.name}'),
          changeLabel: context.t(changeKey),
          changeSuffix: '%',
          bars: true,
        ),
        const SizedBox(height: 12),
        Row(children: [card('present'), const SizedBox(width: 12), card('late')]),
        const SizedBox(height: 12),
        Row(children: [card('absent'), const SizedBox(width: 12), card('excused')]),
        const SizedBox(height: 12),
        if (now.isNotEmpty)
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.t('attendance.daily'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(height: 4),
                DailyStackedBars(
                  key: ValueKey('${range.period}:$subjectFiltered:${now.length}'),
                  days: [
                    for (final (i, d) in days.indexed)
                      (
                        label: labels[i],
                        title: f.day(d),
                        counts: {
                          for (final s in _statuses) s: on(now, d).where((r) => r['attendance_status'] == s).length,
                        },
                      ),
                  ],
                  order: _statuses,
                  colorOf: (s) => attendanceColors(context, s).solid,
                  describe: describe,
                  labelEvery: range.weekly ? 1 : 5,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final s in _statuses)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: attendanceColors(context, s).solid,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(context.t('attendance.status.$s'), style: TextStyle(fontSize: 11, color: c.muted)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (!subjectFiltered && subjectRows.length > 1) ...[
          const SizedBox(height: 12),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.t('attendance.bySubject'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(context.t('attendance.bySubjectHint'), style: TextStyle(fontSize: 12, color: c.muted)),
                const SizedBox(height: 8),
                SubjectCompareBars(rows: subjectRows),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          context.t('attendance.tapHint'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.count, required this.onTap, this.before});
  final String status;
  final int count;

  /// The same count in the period before, for the change.
  final int? before;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final colors = attendanceColors(context, status);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(_icons[status], size: 20, color: colors.solid),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 20, color: c.muted),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$count',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: colors.fg, height: 1),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('attendance.status.$status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  Text(context.t('attendance.lessonsWord'), style: TextStyle(fontSize: 12, color: c.muted)),
                  const Spacer(),
                  if (before != null) _CountChange(status: status, now: count, before: before!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "▲ 2" against the period before. More "present" is good; more of the
/// others is not, so their colours flip.
class _CountChange extends StatelessWidget {
  const _CountChange({required this.status, required this.now, required this.before});
  final String status;
  final int now, before;
  @override
  Widget build(BuildContext context) {
    final d = now - before;
    if (d == 0) {
      return Text(
        '=',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.c.muted),
      );
    }
    final good = status == 'present' ? d > 0 : d < 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = good
        ? (dark ? const Color(0xFF34D399) : const Color(0xFF059669))
        : (dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48));
    return Text(
      '${d > 0 ? '▲' : '▼'} ${d.abs()}',
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
    );
  }
}

/// The lessons of one status in a period, by day, with time, subject and
/// minutes late.
class AttendanceDetailScreen extends StatelessWidget {
  const AttendanceDetailScreen({super.key, required this.status, required this.period, required this.rows});
  final String status;

  /// "Shu hafta", "30 kun"… for the title.
  final String period;
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = Fmt(context.lang);
    final colors = attendanceColors(context, status);

    // Newest day first; within a day, in lesson order.
    final byDay = <String, List<Json>>{};
    for (final r in rows) {
      byDay.putIfAbsent(dayOf(r['date']), () => []).add(r);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final list in byDay.values) {
      list.sort((a, b) => _time(a).compareTo(_time(b)));
    }

    final bySubject = <String, int>{};
    for (final r in rows) {
      final s = '${r['subject'] ?? '—'}';
      bySubject[s] = (bySubject[s] ?? 0) + 1;
    }
    final subjects = bySubject.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final minutesLate = rows.fold<num>(0, (s, r) => s + (asNum(r['minutes_late']) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${context.t('attendance.status.$status')} · $period',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: c.line),
        ),
      ),
      body: rows.isEmpty
          ? EmptyState(text: context.t('attendance.noneInStatus'), icon: _icons[status]!)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Panel(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(12)),
                        child: Icon(_icons[status], color: colors.solid),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t('attendance.lessonCount', {'count': rows.length}),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            if (status == 'late' && minutesLate > 0)
                              Text(
                                context.t('attendance.totalLate', {'count': fmtNum(minutesLate)}),
                                style: TextStyle(fontSize: 13, color: c.muted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (status != 'present' && subjects.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionTitle(context.t('attendance.bySubject')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in subjects)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: c.line),
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: e.key, style: const TextStyle(fontSize: 13)),
                                TextSpan(
                                  text: '  ${e.value}',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.fg),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                for (final day in days) ...[
                  const SizedBox(height: 20),
                  SectionTitle(f.dayLong(day)),
                  PanelList(
                    children: [for (final r in byDay[day]!) _LessonRow(row: r, status: status)],
                  ),
                ],
              ],
            ),
    );
  }

  static String _time(Json r) => '${r['start_time'] ?? ''}';
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.row, required this.status});
  final Json row;
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final time = '${row['start_time'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              time.length >= 5 ? time.substring(0, 5) : '—',
              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(
            child: Text(
              '${row['subject'] ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (status == 'present')
            Text(context.t('attendance.status.present'), style: TextStyle(fontSize: 12, color: c.muted))
          else
            AttendanceBadge(status: status, minutesLate: row['minutes_late']),
        ],
      ),
    );
  }
}
