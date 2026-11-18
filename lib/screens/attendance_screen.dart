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

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final api = context.read<ParentApi>();
    final from = iso(_month);
    final to = iso(DateTime(_month.year, _month.month + 1, 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        MonthNav(month: _month, onChange: (m) => setState(() => _month = m), max: DateTime.now()),
        const SizedBox(height: 8),
        QueryView<List<Json>>(
          cacheKey: 'attendance-lessons:${child.id}:$from',
          load: () => _loadLessons(api, child.id, from, to),
          isEmpty: (rows) => rows.isEmpty,
          emptyText: context.t('attendance.empty'),
          builder: (context, rows, _) => _Summary(month: _month, rows: rows),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.month, required this.rows});
  final DateTime month;
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final byStatus = {for (final s in _statuses) s: rows.where((r) => r['attendance_status'] == s).toList()};
    // Late still means the child came.
    final attended = byStatus['present']!.length + byStatus['late']!.length;
    final rate = rows.isEmpty ? 0 : (attended * 100 / rows.length).round();
    final rateColor = scoreColor(context, rate);

    Widget card(String status) => Expanded(
          child: _StatusCard(
            status: status,
            count: byStatus[status]!.length,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AttendanceDetailScreen(status: status, month: month, rows: byStatus[status]!),
            )),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(context.t('attendance.rate'),
                        style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w500)),
                  ),
                  Text('$rate%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: rateColor)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rate / 100,
                  minHeight: 8,
                  color: rateColor,
                  backgroundColor: c.line,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('attendance.attendedOf', {'present': attended, 'total': rows.length}),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [card('present'), const SizedBox(width: 12), card('late')]),
        const SizedBox(height: 12),
        Row(children: [card('absent'), const SizedBox(width: 12), card('excused')]),
        const SizedBox(height: 12),
        Text(context.t('attendance.tapHint'),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.count, required this.onTap});
  final String status;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final colors = attendanceColors(context, status);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
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
              Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: colors.fg, height: 1)),
              const SizedBox(height: 4),
              Text(context.t('attendance.status.$status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text(context.t('attendance.lessonsWord'), style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lessons of one status in a month, by day, with time, subject and
/// minutes late.
class AttendanceDetailScreen extends StatelessWidget {
  const AttendanceDetailScreen({super.key, required this.status, required this.month, required this.rows});
  final String status;
  final DateTime month;
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
        title: Text('${context.t('attendance.status.$status')} · ${f.month(month)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                            Text(context.t('attendance.lessonCount', {'count': rows.length}),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            if (status == 'late' && minutesLate > 0)
                              Text(context.t('attendance.totalLate', {'count': fmtNum(minutesLate)}),
                                  style: TextStyle(fontSize: 13, color: c.muted)),
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
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: e.key, style: const TextStyle(fontSize: 13)),
                            TextSpan(
                                text: '  ${e.value}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.fg)),
                          ])),
                        ),
                    ],
                  ),
                ],
                for (final day in days) ...[
                  const SizedBox(height: 20),
                  SectionTitle(f.dayLong(day)),
                  PanelList(children: [
                    for (final r in byDay[day]!) _LessonRow(row: r, status: status),
                  ]),
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
            child: Text(time.length >= 5 ? time.substring(0, 5) : '—',
                style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: Text('${row['subject'] ?? '—'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
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
