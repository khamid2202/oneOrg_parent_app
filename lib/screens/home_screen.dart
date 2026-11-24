import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/children.dart';
import '../state/query_cache.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/theme.dart';
import 'dashboard.dart';
import 'grades_screen.dart';
import 'more_screens.dart';
import '../widgets/charts.dart';

typedef Json = Map<String, dynamic>;

/// Tab indexes in [Shell].
const kTabGrades = 2;
const kTabAttendance = 3;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpen});
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final children = context.watch<Children>();
    return RefreshIndicator(
      onRefresh: () async {
        // Drop what this screen shows so every card loads again.
        context.read<QueryCache>().clear();
        await children.load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            Fmt(context.lang).dayLong(DateTime.now()),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.c.muted),
          ),
          const SizedBox(height: 12),
          if (children.child case final c?) ChildSummary(key: ValueKey(c.id), child: c, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    this.hint,
    this.hintWidget,
    this.valueColor,
    required this.onTap,
  });
  final String label, value;
  final IconData icon;
  final Color tint;
  final String? hint;
  final Widget? hintWidget;
  final Color? valueColor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: tint),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: valueColor ?? c.ink),
              ),
              const SizedBox(height: 2),
              hintWidget ??
                  Text(
                    hint ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected child's day at a glance, flat on the page; the top bar
/// already names the child. Each tile opens the full page.
class ChildSummary extends StatelessWidget {
  const ChildSummary({super.key, required this.child, required this.onOpen});
  final Child child;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ParentApi>();
    final day = today();
    final id = child.id;
    final now = DateTime.now();
    final monthStart = iso(DateTime(now.year, now.month));
    final f = Fmt(context.lang);

    void open(VoidCallback go) {
      context.read<Children>().select(id);
      go();
    }

    void push(Widget screen) => open(() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
    String pending(Snap<Json> s) => s.loading ? '…' : '—';

    // This week and last, in one request every dashboard section shares.
    final monday = WeekStats.mondayOf(now);
    Widget week(Widget Function(Snap<Json> q, WeekStats? stats) build) => Query<Json>(
      cacheKey: 'grades:$id:dash:${iso(monday)}',
      load: () =>
          api.grades(id, {'start_date': iso(monday.subtract(const Duration(days: 7))), 'end_date': day, 'limit': 200}),
      builder: (context, q) {
        final rows = (q.data?['result'] as List?)?.cast<Json>();
        return build(q, rows == null ? null : WeekStats.from(rows, monday));
      },
    );

    return Query<Json>(
      cacheKey: 'attendance:$id:$day',
      load: () => api.attendance(id, {'date': day, 'limit': 5}),
      builder: (context, attendanceQ) {
        final rows = (attendanceQ.data?['attendance'] as List? ?? const []).cast<Json>();
        final attendance = rows.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      child.className,
                      child.teacherName,
                    ].where((s) => s.isNotEmpty).join(' · ').ifEmpty(context.t('children.notEnrolled')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: context.c.muted),
                  ),
                ),
                if (attendance != null)
                  AttendanceBadge(status: '${attendance['status']}')
                // A failed request is not "not marked": say nothing then.
                else if (attendanceQ.data != null)
                  Text(context.t('home.notMarked'), style: TextStyle(fontSize: 12, color: context.c.muted)),
              ],
            ),
            if (attendance?['reason'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${attendance!['reason']}', style: TextStyle(fontSize: 12, color: context.c.muted)),
              ),
            const SizedBox(height: 12),
            week((q, stats) => WeekHero(stats: stats, loading: q.loading, onTap: () => open(() => onOpen(kTabGrades)))),
            const SizedBox(height: 12),
            _TileGrid(
              children: [
                week((q, stats) {
                  final now = stats?.attendNow;
                  return _Tile(
                    label: context.t('dash.attendance'),
                    icon: Icons.event_available,
                    tint: const Color(0xFF0EA5E9),
                    value: now == null ? pending(q) : '${now.round()}%',
                    valueColor: now == null ? null : scoreColor(context, now),
                    hintWidget: DeltaText(now: now, before: stats?.attendBefore, suffix: '%'),
                    onTap: () => open(() => onOpen(kTabAttendance)),
                  );
                }),
                Query<Json>(
                  cacheKey: 'dollars:$id',
                  // No dates: the all-time sum is the cashier balance, 10 points = $1.
                  load: () => api.points(id, {'limit': 1}),
                  builder: (context, q) {
                    final total = asNum((q.data?['meta'] as Map?)?['total_points']);
                    final dollars = total == null ? null : total / 10;
                    return _Tile(
                      label: context.t('home.dollars'),
                      icon: Icons.attach_money,
                      tint: const Color(0xFF059669),
                      value: dollars != null ? _money(dollars) : pending(q),
                      valueColor: dollars != null && dollars < 0 ? const Color(0xFFDC2626) : null,
                      onTap: () => push(const PointsScreen()),
                    );
                  },
                ),
                Query<Json>(
                  cacheKey: 'ranking:$id:${day.substring(0, 7)}',
                  load: () => api.ranking(id, monthStart, day),
                  builder: (context, q) {
                    final meta = q.data?['meta'] as Map?;
                    final points = asNum(meta?['current_student_points']) ?? 0;
                    final rank = meta?['current_student_rank'];
                    return _Tile(
                      label: context.t('home.pointsMonth'),
                      icon: Icons.emoji_events_outlined,
                      tint: const Color(0xFFD97706),
                      value: meta != null ? fmtNum(points) : pending(q),
                      // With no points the whole class ties for 1st; say nothing.
                      hint: rank != null && points > 0
                          ? context.t('home.rank', {'rank': rank, 'total': meta?['total_students']})
                          : null,
                      onTap: () => push(const PointsScreen()),
                    );
                  },
                ),
                Query<Json>(
                  // Same data as the Exams page, so opening it is instant.
                  cacheKey: 'exams:$id',
                  load: () => api.exams(id),
                  builder: (context, q) {
                    final exams = (q.data?['result'] as List? ?? const []).cast<Json>();
                    // The newest exam period: its date and name.
                    final latest = exams.isEmpty
                        ? null
                        : exams.reduce(
                            (a, b) => dayOf(a['exam_period_date']).compareTo(dayOf(b['exam_period_date'])) >= 0 ? a : b,
                          );
                    final date = dayOf(latest?['exam_period_date']);
                    return _Tile(
                      label: context.t('nav.exams'),
                      icon: Icons.school_outlined,
                      tint: const Color(0xFF7C3AED),
                      value: latest == null ? pending(q) : (date.isEmpty ? '${exams.length}' : f.day(date)),
                      hint:
                          latest?['exam_period_name'] as String? ?? (q.data != null ? context.t('exams.empty') : null),
                      onTap: () => push(const ExamsScreen()),
                    );
                  },
                ),
                Query<Json>(
                  cacheKey: 'calendar:$id:next:$day',
                  load: () => api.calendar(id, day, daysAhead(14)),
                  builder: (context, q) {
                    final event = (q.data?['result'] as List?)?.firstOrNull as Map?;
                    return _Tile(
                      label: context.t('home.nextEvent'),
                      icon: Icons.celebration_outlined,
                      tint: const Color(0xFFDB2777),
                      value: event != null ? f.day(event['start_date'] as Object) : pending(q),
                      hint: event?['title'] as String? ?? (q.data != null ? context.t('home.noEvents') : null),
                      onTap: () => push(const CalendarScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            week(
              (q, stats) => stats == null
                  ? const SizedBox.shrink()
                  : SubjectsPanel(
                      stats: stats,
                      onOpen: (subjectId, name) => push(GradesScreen(subjectId: subjectId, subjectName: name)),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Two tiles per row; each row is as tall as its tallest tile, so larger
/// system text never clips. An odd last tile takes the whole row.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              if (i + 1 < children.length) ...[const SizedBox(width: 8), Expanded(child: children[i + 1])],
            ],
          ),
        ),
      ],
    ],
  );
}

/// "$12.5", "-$3", "$1 250"
String _money(num dollars) {
  final [whole, cents] = dollars.abs().toStringAsFixed(2).split('.');
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ' ');
  final tail = cents == '00' ? '' : '.${cents.replaceAll(RegExp(r'0$'), '')}';
  return '${dollars < 0 ? '-' : ''}\$$grouped$tail';
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
