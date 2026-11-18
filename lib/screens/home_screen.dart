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
import 'lesson_row.dart';
import 'more_screens.dart';

typedef Json = Map<String, dynamic>;

/// Tab indexes in [Shell].
const kTabSchedule = 1, kTabGrades = 2;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpen});
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final children = context.watch<Children>();
    final child = children.child!;
    final api = context.read<ParentApi>();
    final day = today();
    return RefreshIndicator(
      onRefresh: () async {
        // Drop what this screen shows so every card loads again.
        context.read<QueryCache>().clear();
        await children.load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(Fmt(context.lang).dayLong(DateTime.now()),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.c.muted)),
          const SizedBox(height: 12),
          for (final c in children.list) ...[
            ChildCard(child: c, onOpen: onOpen),
            const SizedBox(height: 14),
          ],
          SectionTitle(context.t('home.todayFor', {'name': child.shortName})),
          QueryView<Json>(
            cacheKey: 'today:${child.id}:$day',
            load: () => api.todayLessons(child.id),
            isEmpty: (d) => _lessons(d).isEmpty,
            emptyText: context.t('schedule.empty'),
            builder: (context, data, _) =>
                PanelList(children: [for (final l in _lessons(data)) LessonRow(lesson: l)]),
          ),
        ],
      ),
    );
  }
}

List<Json> _lessons(Json data) =>
    ((data['result'] as Map?)?['lessons'] as List? ?? const []).cast<Json>();

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.hint, this.valueColor, required this.onTap});
  final String label, value;
  final String? hint;
  final Color? valueColor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.sunken,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: valueColor ?? c.ink)),
              const SizedBox(height: 2),
              Text(hint ?? ' ', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One child's day at a glance. Each tile opens that child's full page.
class ChildCard extends StatelessWidget {
  const ChildCard({super.key, required this.child, required this.onOpen});
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

    return Panel(
      padding: const EdgeInsets.all(16),
      child: Query<Json>(
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
                  Avatar(name: child.fullName, url: child.picture, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(child.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(
                          [child.className, child.teacherName].where((s) => s.isNotEmpty).join(' · ').ifEmpty(context.t('children.notEnrolled')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.c.muted),
                        ),
                      ],
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
              _TileGrid(
                children: [
                  Query<Json>(
                    cacheKey: 'today:$id:$day',
                    load: () => api.todayLessons(id),
                    builder: (context, q) {
                      final lessons = q.data == null ? const <Json>[] : _lessons(q.data!);
                      final changes = lessons.where((l) => lessonChange(l) != null).length;
                      return _Tile(
                        label: context.t('home.lessonsToday'),
                        value: q.data != null ? '${lessons.length}' : pending(q),
                        hint: changes > 0
                            ? context.t('home.changes', {'count': changes})
                            : lessons.isNotEmpty
                                ? '${hm(lessons.first['start_time'])}–${hm(lessons.last['end_time'])}'
                                : null,
                        valueColor: changes > 0 ? const Color(0xFFD97706) : null,
                        onTap: () => open(() => onOpen(kTabSchedule)),
                      );
                    },
                  ),
                  Query<Json>(
                    cacheKey: 'grades:$id:30:latest',
                    load: () => api.grades(id, {'start_date': daysAgo(30), 'end_date': day, 'limit': 1}),
                    builder: (context, q) {
                      final summary = (q.data?['meta'] as Map?)?['summary'] as Map?;
                      final latest = (q.data?['result'] as List?)?.firstOrNull as Map?;
                      final avg = asNum(summary?['average_score']);
                      final has = (asNum(summary?['lessons']) ?? 0) > 0 && avg != null;
                      return _Tile(
                        label: context.t('home.average30'),
                        value: has ? '${avg.round()}' : pending(q),
                        hint: latest == null ? null : '${latest['subject']}: ${fmtNum(latest['score'])}',
                        valueColor: has ? scoreColor(context, avg) : null,
                        onTap: () => open(() => onOpen(kTabGrades)),
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
                    cacheKey: 'calendar:$id:next:$day',
                    load: () => api.calendar(id, day, daysAhead(14)),
                    builder: (context, q) {
                      final event = (q.data?['result'] as List?)?.firstOrNull as Map?;
                      return _Tile(
                        label: context.t('home.nextEvent'),
                        value: event != null ? f.day(event['start_date'] as Object) : pending(q),
                        hint: event?['title'] as String? ?? (q.data != null ? context.t('home.noEvents') : null),
                        onTap: () => push(const CalendarScreen()),
                      );
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Two tiles per row; each row is as tall as its tallest tile, so larger
/// system text never clips.
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
                  const SizedBox(width: 8),
                  Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
                ],
              ),
            ),
          ],
        ],
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
