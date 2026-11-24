import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../util/dates.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/theme.dart';

typedef Json = Map<String, dynamic>;

/// This week against last week, worked out from one grades request that
/// covers last Monday through today.
class WeekStats {
  WeekStats._({
    required this.days,
    required this.current,
    required this.previous,
    required this.avgNow,
    required this.avgBefore,
    required this.lessonsNow,
    required this.attendNow,
    required this.attendBefore,
    required this.subjects,
  });

  final List<DateTime> days;
  final List<double?> current, previous;
  final double? avgNow, avgBefore;
  final int lessonsNow;

  /// Share of lessons attended (present or late), 0–100.
  final double? attendNow, attendBefore;
  final List<({int? id, String name, double? now, double? before})> subjects;

  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Last week counts only up to the same weekday as [today], so Monday is
  /// compared with Monday, Monday–Tuesday with Monday–Tuesday, and so on.
  /// The chart still draws all of last week.
  factory WeekStats.from(List<Json> rows, DateTime monday, {DateTime? today}) {
    final cutoff = (today ?? DateTime.now()).weekday - 1;
    final now = List.generate(7, (_) => <num>[]);
    final before = List.generate(7, (_) => <num>[]);
    final attend = [<bool>[], <bool>[]];
    final subjects = <String, ({int? id, List<num> now, List<num> before})>{};

    for (final r in rows) {
      final date = r['date'];
      if (date == null) continue;
      final diff = toDate(date).difference(monday).inDays;
      if (diff < -7 || diff > 6) continue;
      final thisWeek = diff >= 0;
      final day = thisWeek ? diff : diff + 7;
      // Last week after today's weekday: drawn, never compared.
      final compared = day <= cutoff;
      final status = r['attendance_status'];
      if (status != null && compared) attend[thisWeek ? 0 : 1].add(status == 'present' || status == 'late');
      final score = asNum(r['score']);
      if (score == null) continue;
      (thisWeek ? now : before)[day].add(score);
      if (!compared) continue;
      final name = '${r['subject'] ?? ''}';
      final s = subjects.putIfAbsent(name, () => (id: asNum(r['subject_id'])?.toInt(), now: <num>[], before: <num>[]));
      (thisWeek ? s.now : s.before).add(score);
    }

    double? avg(Iterable<num> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    double? pct(List<bool> v) => v.isEmpty ? null : 100 * v.where((x) => x).length / v.length;

    // Weekdays always; the weekend only when someone had lessons then.
    var count = 5;
    for (final i in [5, 6]) {
      if (now[i].isNotEmpty || before[i].isNotEmpty) count = i + 1;
    }

    final list =
        [
          for (final e in subjects.entries)
            if (e.value.now.isNotEmpty || e.value.before.isNotEmpty)
              (id: e.value.id, name: e.key, now: avg(e.value.now), before: avg(e.value.before), n: e.value.now.length),
        ]..sort((a, b) {
          // This week's subjects first, the busiest on top.
          final byCount = b.n.compareTo(a.n);
          return byCount != 0 ? byCount : a.name.compareTo(b.name);
        });

    return WeekStats._(
      days: [for (var i = 0; i < count; i++) DateTime(monday.year, monday.month, monday.day + i)],
      current: [for (var i = 0; i < count; i++) avg(now[i])],
      previous: [for (var i = 0; i < count; i++) avg(before[i])],
      avgNow: avg(now.expand((d) => d)),
      avgBefore: avg(before.take(cutoff + 1).expand((d) => d)),
      lessonsNow: now.fold(0, (a, d) => a + d.length),
      attendNow: pct(attend[0]),
      attendBefore: pct(attend[1]),
      subjects: [for (final s in list) (id: s.id, name: s.name, now: s.now, before: s.before)],
    );
  }
}

/// The landing card: this week's average, the change, and the two weeks
/// drawn day by day.
class WeekHero extends StatelessWidget {
  const WeekHero({super.key, required this.stats, required this.loading, required this.onTap});
  final WeekStats? stats;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final f = Fmt(context.lang);
    final todayIndex = DateTime.now().weekday - 1;
    return HeroChartCard(
      title: context.t('dash.weekAvg'),
      value: s?.avgNow,
      before: s?.avgBefore,
      loading: loading,
      unit: '/ 100',
      badge: s != null && s.lessonsNow > 0 ? context.t('dash.lessons', {'n': s.lessonsNow}) : null,
      note: s != null && s.avgNow == null && !loading ? context.t('dash.noGradesYet') : null,
      current: s?.current,
      previous: s?.previous,
      labels: [for (final d in s?.days ?? const <DateTime>[]) f.weekday(d)],
      todayIndex: s != null && todayIndex < s.days.length ? todayIndex : null,
      currentLabel: context.t('grades.period.thisWeek'),
      previousLabel: context.t('grades.period.lastWeek'),
      changeLabel: context.t('dash.vsLast'),
      onTap: onTap,
    );
  }
}

/// Subjects compared week on week, as paired bars.
class SubjectsPanel extends StatelessWidget {
  const SubjectsPanel({super.key, required this.stats, required this.onOpen});
  final WeekStats stats;
  final void Function(int? subjectId, String name) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = stats.subjects.take(6).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('dash.subjects'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              _Key(color: c.accent, label: context.t('grades.period.thisWeek')),
              const SizedBox(width: 10),
              _Key(color: c.line, label: context.t('grades.period.lastWeek')),
            ],
          ),
          const SizedBox(height: 8),
          SubjectCompareBars(
            rows: [for (final r in rows) (name: r.name, now: r.now, before: r.before)],
            onTap: (i) => onOpen(rows[i].id, rows[i].name),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: context.c.muted)),
    ],
  );
}
