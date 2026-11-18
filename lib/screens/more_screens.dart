import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/auth.dart';
import '../state/children.dart';
import '../state/query_cache.dart';
import '../state/settings.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/states.dart';
import '../widgets/theme.dart';
import 'shell.dart';

typedef Json = Map<String, dynamic>;

/// Shown in Settings; keep in step with `version:` in pubspec.yaml.
const kAppVersion = '1.0.0';

List<Json> _list(Object? v) => (v as List? ?? const []).cast<Json>();

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

/// A pushed page with a back button and the child's name under the title.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: context.c.line),
      ),
    ),
    body: child,
  );
}

// ---------------------------------------------------------------- More

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.emoji_events_outlined, 'points', () => const PointsScreen()),
      (Icons.school_outlined, 'exams', () => const ExamsScreen()),
      (Icons.date_range_outlined, 'calendar', () => const CalendarScreen()),
      (Icons.notifications_none, 'notifications', () => const NotificationsScreen()),
      (Icons.settings_outlined, 'settings', () => const SettingsScreen()),
    ];
    final c = context.c;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(context.t('nav.more'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        PanelList(
          children: [
            for (final (icon, key, build) in items)
              ListTile(
                onTap: () => _push(context, build()),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 20, color: c.accentInk),
                ),
                title: Text(context.t('nav.$key'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                trailing: Icon(Icons.chevron_right, color: c.muted),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Points

class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});
  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  String _tab = 'history';

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final api = context.read<ParentApi>();
    final c = context.c;
    return _Page(
      title: context.t('nav.points'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Panel(
            padding: const EdgeInsets.all(16),
            child: Query<Json>(
              cacheKey: 'points-progress:${child.id}',
              load: () => api.pointsProgress(child.id),
              builder: (context, q) {
                if (q.loading) return const LoadingState(padding: 24);
                final meta = q.data?['meta'] as Map?;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('points.total'), style: TextStyle(fontSize: 12, color: c.muted)),
                    Text(
                      fmtNum(meta?['total_points'] ?? 0),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ProgressChart(progress: _list(q.data?['progress'])),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final key in ['history', 'ranking']) ...[
                Pill(
                  label: context.t('points.tab.$key'),
                  selected: _tab == key,
                  onTap: () => setState(() => _tab = key),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_tab == 'history') _History(childId: child.id) else _Ranking(childId: child.id),
        ],
      ),
    );
  }
}

/// Running total of points over time, as a simple area chart.
class ProgressChart extends StatelessWidget {
  const ProgressChart({super.key, required this.progress});
  final List<Json> progress;
  @override
  Widget build(BuildContext context) {
    if (progress.length < 2) return const SizedBox.shrink();
    var running = 0.0;
    final points = [
      for (final p in progress) (date: dayOf(p['date']), value: running += (asNum(p['total_points']) ?? 0).toDouble()),
    ];
    final f = Fmt(context.lang);
    final c = context.c;
    return Column(
      children: [
        SizedBox(
          height: 96,
          width: double.infinity,
          child: CustomPaint(painter: _AreaPainter([for (final p in points) p.value], c.accent)),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(f.day(points.first.date), style: TextStyle(fontSize: 11, color: c.muted)),
            Text(f.day(points.last.date), style: TextStyle(fontSize: 11, color: c.muted)),
          ],
        ),
      ],
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.fold<double>(0, (a, b) => a < b ? a : b);
    var hi = values.fold<double>(lo + 1, (a, b) => a > b ? a : b);
    if (hi <= lo) hi = lo + 1;
    double x(int i) => i / (values.length - 1) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * (size.height - 8) - 4;
    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_AreaPainter old) => old.values != values || old.color != color;
}

class _History extends StatefulWidget {
  const _History({required this.childId});
  final int childId;
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  int _limit = 30;
  @override
  Widget build(BuildContext context) {
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return QueryView<Json>(
      cacheKey: 'points:${widget.childId}:$_limit',
      load: () => api.points(widget.childId, {'limit': _limit}),
      isEmpty: (d) => _list(d['points']).isEmpty,
      emptyText: context.t('points.empty'),
      builder: (context, data, snap) {
        final rows = _list(data['points']);
        final total = asNum((data['meta'] as Map?)?['total']) ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelList(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['reason'] ?? r['subject_name'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                [
                                  if (r['date'] != null) f.day(r['date'] as Object),
                                  if (r['reason'] != null && r['subject_name'] != null) '${r['subject_name']}',
                                  if (r['teacher_name'] != null) '${r['teacher_name']}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final p = asNum(r['points']) ?? 0;
                            final color = p < 0
                                ? (dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48))
                                : (dark ? const Color(0xFF34D399) : const Color(0xFF059669));
                            return Text(
                              p > 0 ? '+${fmtNum(p)}' : fmtNum(p),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (rows.length < total)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  onPressed: snap.refreshing ? null : () => setState(() => _limit += 30),
                  child: Text(context.t('common.showMore')),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Ranking extends StatelessWidget {
  const _Ranking({required this.childId});
  final int childId;
  @override
  Widget build(BuildContext context) {
    final api = context.read<ParentApi>();
    final day = today();
    final now = DateTime.now();
    final c = context.c;
    return QueryView<Json>(
      cacheKey: 'ranking:$childId:${day.substring(0, 7)}',
      load: () => api.ranking(childId, iso(DateTime(now.year, now.month)), day),
      // Everyone on 0 is a tie for 1st, not a ranking.
      isEmpty: (d) => !_list(d['ranking']).any((r) => (asNum(r['total_points']) ?? 0) > 0),
      emptyText: context.t('points.noRanking'),
      builder: (context, data, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.t('points.rankingHint'), style: TextStyle(fontSize: 12, color: c.muted)),
          ),
          PanelList(
            children: [
              for (final r in _list(data['ranking']))
                _RankRow(
                  rank: r['rank'],
                  name: '${r['full_name'] ?? ''}',
                  picture: r['picture'] as String?,
                  value: fmtNum(r['total_points']),
                  me: r['is_current_student'] == true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.value,
    required this.me,
    this.picture,
    this.avatar = true,
  });
  final Object? rank;
  final String name, value;
  final String? picture;
  final bool me, avatar;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: me ? c.accentSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${rank ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, color: c.muted),
            ),
          ),
          const SizedBox(width: 10),
          if (avatar) ...[Avatar(name: name, url: picture, size: 32), const SizedBox(width: 10)],
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: me ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Exams

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);
    final c = context.c;

    // The list is flat; group it by exam period, newest period first.
    List<({Object? id, String name, String date, List<Json> exams})> group(Json data) {
      final map = <Object?, ({Object? id, String name, String date, List<Json> exams})>{};
      for (final e in _list(data['result'])) {
        map
            .putIfAbsent(
              e['exam_period_id'],
              () => (
                id: e['exam_period_id'],
                name: '${e['exam_period_name'] ?? ''}',
                date: dayOf(e['exam_period_date']),
                exams: <Json>[],
              ),
            )
            .exams
            .add(e);
      }
      return map.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    }

    return _Page(
      title: context.t('nav.exams'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          QueryView<Json>(
            cacheKey: 'exams:${child.id}',
            load: () => api.exams(child.id),
            isEmpty: (d) => _list(d['result']).isEmpty,
            emptyText: context.t('exams.empty'),
            builder: (context, data, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final period in group(data)) ...[
                  SectionTitle(
                    period.name,
                    trailing: period.date.isEmpty
                        ? null
                        : Text(f.dayYear(period.date), style: TextStyle(fontSize: 12, color: c.muted)),
                  ),
                  PanelList(
                    children: [for (final exam in period.exams) _ExamRow(exam: exam, childId: child.id)],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({required this.exam, required this.childId});
  final Json exam;
  final int childId;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = exam['current_score'] != null;
    return InkWell(
      onTap: done ? () => _showRanking(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${exam['subject_name'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (done) ...[
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: fmtNum(exam['current_score']),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scoreColor(context, asNum(exam['current_percentage'])),
                      ),
                    ),
                    TextSpan(
                      text: ' / ${fmtNum(exam['max_score'])}',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: c.muted),
            ] else
              Text(context.t('exams.noResult'), style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
      ),
    );
  }

  void _showRanking(BuildContext context) {
    final api = context.read<ParentApi>();
    final examId = (exam['id'] as num).toInt();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                '${exam['subject_name']} · ${exam['exam_period_name']}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            QueryView<Json>(
              cacheKey: 'exam-ranking:$childId:$examId',
              load: () => api.examRanking(childId, examId),
              isEmpty: (d) => _list(d['ranking']).isEmpty,
              emptyText: context.t('exams.noRanking'),
              builder: (context, data, _) {
                final meta = data['meta'] as Map?;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (meta?['current_student_rank'] != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                        child: Text(
                          context.t('exams.place', {
                            'rank': meta!['current_student_rank'],
                            'total': meta['total_students'],
                          }),
                        ),
                      ),
                    for (final r in _list(data['ranking']))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _RankRow(
                          rank: r['rank'],
                          name: '${r['full_name'] ?? ''}',
                          value: fmtNum(r['score']),
                          me: r['is_current_student'] == true,
                          avatar: false,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Calendar

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// Day picked in the grid; null shows the whole month's events.
  DateTime? _selected;

  static const _sourceColors = {
    'holiday': Color(0xFF10B981),
    'term_start': Color(0xFF0EA5E9),
    'term_end': Color(0xFF0EA5E9),
    'exam_period': Color(0xFFF59E0B),
  };

  Color _colorOf(Json item) => _sourceColors['${item['source'] ?? ''}'] ?? context.c.accent;

  static DateTime _date(Object? v) => DateTime.parse(dayOf(v));

  /// Whether [item] runs over [day] (events can span several days).
  static bool _covers(Json item, DateTime day) {
    final start = _date(item['start_date']);
    final end = _date(item['end_date'] ?? item['start_date']);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final api = context.read<ParentApi>();
    final from = iso(_month);
    final to = iso(DateTime(_month.year, _month.month + 1, 0));

    return _Page(
      title: context.t('nav.calendar'),
      child: Query<Json>(
        cacheKey: 'calendar:${child.id}:$from',
        load: () => api.calendar(child.id, from, to),
        builder: (context, snap) {
          final events = _list(snap.data?['result']);
          final selected = _selected;
          final shown = selected == null ? events : events.where((e) => _covers(e, selected)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              MonthNav(
                month: _month,
                onChange: (m) => setState(() {
                  _month = m;
                  _selected = null;
                }),
              ),
              const SizedBox(height: 8),
              _grid(events),
              const SizedBox(height: 16),
              if (snap.loading)
                const LoadingState(padding: 24)
              else if (snap.data == null)
                ErrorState(error: snap.error, onRetry: snap.reload)
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    context.t(selected == null ? 'calendar.empty' : 'calendar.emptyDay'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.c.muted, fontSize: 14),
                  ),
                )
              else
                PanelList(children: [for (final item in shown) _eventRow(item)]),
            ],
          );
        },
      ),
    );
  }

  /// Month grid, Monday first, with a dot per kind of event on each day.
  Widget _grid(List<Json> events) {
    final c = context.c;
    final f = Fmt(context.lang);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = DateTime(_month.year, _month.month, 1).weekday - 1;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    Widget cell(DateTime? day) {
      if (day == null) return const SizedBox.shrink();
      final isToday = day == today;
      final isSelected = day == _selected;
      final colors = <Color>{
        for (final e in events)
          if (_covers(e, day)) _colorOf(e),
      }.take(3);
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selected = isSelected ? null : day),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? c.accent : (isToday ? c.accentSoft : null),
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : isToday
                      ? c.accentInk
                      : day.weekday == DateTime.sunday
                      ? c.muted
                      : c.ink,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in colors)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Panel(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    f.weekday(DateTime(2024, 1, 1 + i)), // 1 Jan 2024 was a Monday
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < cells.length; r += 7)
            Row(
              children: [for (var i = r; i < r + 7; i++) Expanded(child: SizedBox(height: 48, child: cell(cells[i])))],
            ),
        ],
      ),
    );
  }

  Widget _eventRow(Json item) => Builder(
    builder: (context) {
      final f = Fmt(context.lang);
      final c = context.c;
      final start = dayOf(item['start_date']);
      final end = dayOf(item['end_date'] ?? item['start_date']);
      final cancelled = item['status'] == 'cancelled';
      final source = '${item['source'] ?? ''}';
      final sourceLabel = context.t('calendar.source.$source');
      final startDate = DateTime.parse(start);
      final place = item['location'] ?? item['room'];
      final details = [
        if (sourceLabel != 'calendar.source.$source') sourceLabel,
        if (end != start) context.t('calendar.until', {'date': f.day(end)}),
        if (item['all_day'] != true && item['start_time'] != null)
          '${hm(item['start_time'])}${item['end_time'] != null ? '–${hm(item['end_time'])}' : ''}',
        if (place != null && '$place'.isNotEmpty) '$place',
        if (cancelled) context.t('calendar.cancelled'),
      ];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text('${startDate.day}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(f.weekday(startDate), style: TextStyle(fontSize: 11, color: c.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['title'] ?? ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cancelled ? c.muted : c.ink,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 4, right: 6),
                        decoration: BoxDecoration(color: _colorOf(item), shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(details.join(' · '), style: TextStyle(fontSize: 12, color: c.muted)),
                      ),
                    ],
                  ),
                  if (item['description'] != null && '${item['description']}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${item['description']}', style: TextStyle(fontSize: 12, color: c.muted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------- Notifications

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  /// The merged inbox of every child; drop it to make the screen reload.
  static const cacheKey = 'notifications:all';
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Every child's inbox in one list, newest first. Each item carries the
  /// child it is about in [_childKey], so a parent sees all of them whichever
  /// child is open at the top.
  static const _childKey = '_child_id';

  static Future<Json> _loadAll(ParentApi api, List<Child> children) async {
    Object? firstError;
    var failed = 0;
    final lists = await Future.wait(children.map((c) async {
      try {
        final r = await api.notifications(c.id);
        return [for (final n in _list(r['items'])) {...n, _childKey: c.id}];
      } catch (e) {
        // One child's inbox failing should not hide the others.
        firstError ??= e;
        failed++;
        return <Json>[];
      }
    }));
    if (failed > 0 && failed == children.length) throw firstError!;
    final items = lists.expand((l) => l).toList()
      ..sort((a, b) => _time(b).compareTo(_time(a)));
    return {'items': items};
  }

  static DateTime _time(Json n) =>
      DateTime.tryParse('${n['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);

  static int _childOf(Json n) => (n[_childKey] as num).toInt();

  static bool _same(Json a, Json b) => a['id'] == b['id'] && a[_childKey] == b[_childKey];

  /// Changes the cached list at once, then tells the server.
  Future<void> _change(
    bool Function(Json n) which,
    Future<void> Function() send,
    VoidCallback reload,
  ) async {
    final cache = context.read<QueryCache>();
    final data = cache.peek<Json>(NotificationsScreen.cacheKey);
    if (data == null) return;
    setState(() {
      cache.put(NotificationsScreen.cacheKey, {
        ...data,
        'items': [
          for (final n in _list(data['items'])) which(n) ? {...n, 'is_read': true} : n,
        ],
      });
    });
    try {
      await send();
      if (mounted) {
        final children = context.read<Children>().list;
        context.read<Unread>().refresh(children);
      }
    } catch (_) {
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = context.watch<Children>().list;
    final byId = {for (final ch in children) ch.id: ch};
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);
    final c = context.c;

    return Query<Json>(
      cacheKey: NotificationsScreen.cacheKey,
      load: () => _loadAll(api, children),
      builder: (context, q) {
        final items = _list(q.data?['items']);
        final hasUnread = items.any((n) => n['is_read'] != true);
        Widget body;
        if (q.loading) {
          body = const LoadingState();
        } else if (q.data == null) {
          body = ErrorState(error: q.error, onRetry: q.reload);
        } else if (items.isEmpty) {
          body = EmptyState(text: context.t('notifications.empty'), icon: Icons.notifications_off_outlined);
        } else {
          body = PanelList(
            children: [
              for (final n in items)
                InkWell(
                  onTap: n['is_read'] == true
                      ? null
                      : () => _change(
                          (x) => _same(x, n),
                          () => api.markRead(_childOf(n), (n['id'] as num).toInt()),
                          q.reload,
                        ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6, right: 12),
                          decoration: BoxDecoration(
                            color: n['is_read'] == true ? Colors.transparent : c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Which child it is about, once there is more than one.
                              if (children.length > 1 && byId[_childOf(n)] != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Avatar(
                                        name: byId[_childOf(n)]!.fullName,
                                        url: byId[_childOf(n)]!.picture,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          byId[_childOf(n)]!.fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: c.accent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                '${n['title'] ?? ''}',
                                style: TextStyle(fontWeight: n['is_read'] == true ? FontWeight.w400 : FontWeight.w600),
                              ),
                              if (n['body'] != null && '${n['body']}'.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('${n['body']}', style: TextStyle(fontSize: 14, color: c.muted)),
                                ),
                              if (n['created_at'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    f.moment(n['created_at'] as Object),
                                    style: TextStyle(fontSize: 12, color: c.muted),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }
        return _Page(
          title: context.t('nav.notifications'),
          actions: [
            if (hasUnread)
              TextButton.icon(
                onPressed: () {
                  final ids = {
                    for (final n in items)
                      if (n['is_read'] != true) _childOf(n),
                  };
                  _change(
                    (_) => true,
                    () => Future.wait(ids.map(api.markAllRead)),
                    q.reload,
                  );
                },
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(context.t('notifications.readAll')),
              ),
            const SizedBox(width: 8),
          ],
          child: RefreshIndicator(
            onRefresh: q.reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [body]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Settings

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(d.t('settings.logoutConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(d.t('auth.logOut'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await context.read<Auth>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final children = context.watch<Children>().list;
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return _Page(
      title: context.t('nav.settings'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SectionTitle(context.t('settings.children')),
          PanelList(
            children: [
              for (final ch in children)
                ListTile(
                  leading: Avatar(name: ch.fullName, url: ch.picture, size: 36),
                  title: Text(
                    ch.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    [ch.code, ch.className].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            child: Text(context.t('settings.childrenHint'), style: TextStyle(fontSize: 12, color: c.muted)),
          ),
          SectionTitle(context.t('settings.language')),
          _Choice<String>(
            value: settings.language,
            onChange: settings.setLanguage,
            options: [for (final l in kLanguages) (l.code, l.label)],
          ),
          const SizedBox(height: 20),
          SectionTitle(context.t('settings.theme')),
          _Choice<ThemeMode>(
            value: settings.themeMode,
            onChange: settings.setThemeMode,
            options: [
              (ThemeMode.system, context.t('settings.themes.system')),
              (ThemeMode.light, context.t('settings.themes.light')),
              (ThemeMode.dark, context.t('settings.themes.dark')),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48)),
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: Text(context.t('auth.logOut')),
          ),
          const SizedBox(height: 24),
          Text(
            context.t('settings.version', {'version': kAppVersion}),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.value, required this.onChange, required this.options});
  final T value;
  final ValueChanged<T> onChange;
  final List<(T, String)> options;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (final (key, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  decoration: BoxDecoration(
                    color: key == value ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: key == value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: key == value ? c.ink : c.muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
