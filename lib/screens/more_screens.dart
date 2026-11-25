import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/auth.dart';
import '../state/children.dart';
import '../state/passkeys.dart';
import '../state/push.dart';
import '../state/query_cache.dart';
import '../state/settings.dart';
import '../util/dates.dart';
import '../util/notices.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/states.dart';
import '../widgets/theme.dart';
import 'shell.dart';

typedef Json = Map<String, dynamic>;

/// Shown in Settings; keep in step with `version:` in pubspec.yaml.
const kAppVersion = '1.1.0';

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
    final lists = await Future.wait(
      children.map((c) async {
        try {
          final r = await api.notifications(c.id);
          return [
            for (final n in _list(r['items']))
              // Staffing changes are not for parents; older servers still sent them.
              if (n['type'] != 'substitution') {...n, _childKey: c.id},
          ];
        } catch (e) {
          // One child's inbox failing should not hide the others.
          firstError ??= e;
          failed++;
          return <Json>[];
        }
      }),
    );
    if (failed > 0 && failed == children.length) throw firstError!;
    final items = lists.expand((l) => l).toList()..sort((a, b) => _time(b).compareTo(_time(a)));
    return {'items': items};
  }

  static DateTime _time(Json n) =>
      DateTime.tryParse('${n['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);

  static int _childOf(Json n) => (n[_childKey] as num).toInt();

  static bool _same(Json a, Json b) => a['id'] == b['id'] && a[_childKey] == b[_childKey];

  /// Changes the cached list at once, then tells the server.
  Future<void> _change(bool Function(Json n) which, Future<void> Function() send, VoidCallback reload) async {
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

  /// Filter chosen at the top; null shows everything.
  NoticeKind? _filter;

  /// Marks [n] read (if it isn't) and opens the page it is about.
  void _open(Json n, Notice notice, ParentApi api, VoidCallback reload) {
    if (n['is_read'] != true) {
      _change((x) => _same(x, n), () => api.markRead(_childOf(n), (n['id'] as num).toInt()), reload);
    }
    final children = context.read<Children>();
    void forChild() {
      if (children.list.any((ch) => ch.id == _childOf(n))) children.select(_childOf(n));
    }

    switch (notice.kind) {
      case NoticeKind.point:
        forChild();
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PointsScreen()));
      case NoticeKind.exam:
        forChild();
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExamsScreen()));
      case NoticeKind.grade:
        forChild();
        Shell.tabRequest.value = 2;
      case NoticeKind.attendance:
        forChild();
        Shell.tabRequest.value = 3;
      case NoticeKind.behavior:
      case NoticeKind.other:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = context.watch<Children>().list;
    final byId = {for (final ch in children) ch.id: ch};
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);

    return Query<Json>(
      cacheKey: NotificationsScreen.cacheKey,
      load: () => _loadAll(api, children),
      builder: (context, q) {
        final items = _list(q.data?['items']);
        final hasUnread = items.any((n) => n['is_read'] != true);
        final notices = {for (final n in items) n: Notice.parse(n)};
        final kinds = [
          for (final k in NoticeKind.values)
            if (notices.values.any((x) => x.kind == k)) k,
        ];
        final filter = kinds.contains(_filter) ? _filter : null;
        final shown = [
          for (final n in items)
            if (filter == null || notices[n]!.kind == filter) n,
        ];

        final list = <Widget>[];
        if (q.loading) {
          list.add(const LoadingState());
        } else if (q.data == null) {
          list.add(ErrorState(error: q.error, onRetry: q.reload));
        } else if (items.isEmpty) {
          list.add(EmptyState(text: context.t('notifications.empty'), icon: Icons.notifications_off_outlined));
        } else {
          String? day;
          var i = 0;
          for (final n in shown) {
            final when = _time(n).toLocal();
            final key = iso(when);
            if (key != day) {
              day = key;
              list.add(_DayHeader(label: _dayLabel(context, f, when)));
            }
            final child = byId[_childOf(n)];
            list.add(_Appear(
              index: i++,
              child: _NoticeCard(
                key: ValueKey('${n[_childKey]}:${n['id']}'),
                notice: notices[n]!,
                unread: n['is_read'] != true,
                time: when,
                child: children.length > 1 ? child : null,
                onTap: () => _open(n, notices[n]!, api, q.reload),
                onRead: () => _change(
                  (x) => _same(x, n),
                  () => api.markRead(_childOf(n), (n['id'] as num).toInt()),
                  q.reload,
                ),
              ),
            ));
          }
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
                  _change((_) => true, () => Future.wait(ids.map(api.markAllRead)), q.reload);
                },
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(context.t('notifications.readAll')),
              ),
            const SizedBox(width: 8),
          ],
          child: RefreshIndicator(
            onRefresh: q.reload,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (kinds.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: PillRow(children: [
                      Pill(
                        label: '${context.t('notifications.all')} · ${items.length}',
                        selected: filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final k in kinds)
                        Pill(
                          leading: Icon(_kindLook(context, k, null).icon, size: 16, color: _kindLook(context, k, null).color),
                          label: '${context.t('notifications.kind.${k.name}')} · ${notices.values.where((x) => x.kind == k).length}',
                          selected: filter == k,
                          onTap: () => setState(() => _filter = filter == k ? null : k),
                        ),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: list),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _dayLabel(BuildContext context, Fmt f, DateTime d) {
    final today = DateTime.now();
    final key = iso(d);
    if (key == iso(today)) return context.t('common.today');
    if (key == iso(today.subtract(const Duration(days: 1)))) return context.t('common.yesterday');
    return f.dayLong(d);
  }
}

/// Icon and colour for a kind of notice; [notice] refines it (a behaviour
/// note is red, an absence takes its attendance colour).
({IconData icon, Color color}) _kindLook(BuildContext context, NoticeKind kind, Notice? notice) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  Color tone(int light, int darkTone) => Color(dark ? darkTone : light);
  return switch (kind) {
    NoticeKind.grade => (icon: Icons.school_rounded, color: tone(0xFF7C3AED, 0xFFA78BFA)),
    NoticeKind.exam => (icon: Icons.assignment_turned_in_rounded, color: tone(0xFF2563EB, 0xFF60A5FA)),
    NoticeKind.attendance => (
        icon: switch (notice?.status) {
          'present' => Icons.how_to_reg_rounded,
          'late' => Icons.schedule_rounded,
          'absent' => Icons.person_off_rounded,
          'excused' => Icons.medical_information_rounded,
          _ => Icons.event_available_rounded,
        },
        color: notice?.status == null ? tone(0xFF0D9488, 0xFF2DD4BF) : attendanceColors(context, notice!.status!).solid,
      ),
    NoticeKind.behavior => switch (notice?.positive) {
        false => (icon: Icons.flag_rounded, color: tone(0xFFE11D48, 0xFFFB7185)),
        true => (icon: Icons.emoji_events_rounded, color: tone(0xFF059669, 0xFF34D399)),
        null => (icon: Icons.psychology_rounded, color: tone(0xFFD97706, 0xFFFBBF24)),
      },
    NoticeKind.point => (
        icon: (notice?.points ?? 1) < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
        color: (notice?.points ?? 1) < 0 ? tone(0xFFE11D48, 0xFFFB7185) : tone(0xFFD97706, 0xFFFBBF24),
      ),
    NoticeKind.other => (icon: Icons.campaign_rounded, color: context.c.accent),
  };
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.c.muted, letterSpacing: 0.2),
        ),
      );
}

/// Fades and lifts a card in, a beat after the one above it.
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final ms = 220 + 45 * (index < 10 ? index : 10);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    super.key,
    required this.notice,
    required this.unread,
    required this.time,
    required this.child,
    required this.onTap,
    required this.onRead,
  });

  final Notice notice;
  final bool unread;
  final DateTime time;

  /// The child it is about, shown only when there is more than one.
  final Child? child;
  final VoidCallback onTap, onRead;

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static final _date = RegExp(r'^\d{1,2}[./]\d{1,2}[./]\d{2,4}$');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final look = _kindLook(context, notice.kind, notice);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = look.color.withValues(alpha: dark ? 0.22 : 0.12);
    final main = switch (notice.kind) {
      NoticeKind.grade || NoticeKind.exam || NoticeKind.point => notice.subject ?? notice.headline,
      NoticeKind.attendance => notice.status != null
          ? context.t('attendance.status.${notice.status}')
          : notice.headline,
      _ => _capital(notice.headline),
    };
    final sub = switch (notice.kind) {
      // The day heading above already says the date.
      NoticeKind.grade || NoticeKind.exam => notice.details.where((d) => !_date.hasMatch(d)).join(' · '),
      NoticeKind.point => notice.details.join(' · '),
      _ => notice.details.join(' · '),
    };

    final card = Material(
      color: unread ? Color.alphaBlend(look.color.withValues(alpha: dark ? 0.08 : 0.04), c.surface) : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: unread ? look.color.withValues(alpha: 0.35) : c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              // Kind icon, with the child's photo tucked in its corner.
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
                      child: Icon(look.icon, color: look.color, size: 24),
                    ),
                    if (child != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                          child: Avatar(name: child!.fullName, url: child!.picture, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            [
                              context.t('notifications.kind.${notice.kind.name}'),
                              if (child != null) child!.fullName.split(' ').skip(1).firstOrNull ?? child!.fullName,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: look.color),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(DateFormat('HH:mm').format(time), style: TextStyle(fontSize: 12, color: c.muted)),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: look.color, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      main,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (_trailing(context) case final trailing?) ...[const SizedBox(width: 10), trailing],
            ],
          ),
        ),
      ),
    );

    if (!unread) return Padding(padding: const EdgeInsets.only(bottom: 10), child: card);
    // Swipe left to mark read without opening it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('read:${key.hashCode}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onRead();
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.t('notifications.markRead'),
                  style: TextStyle(color: c.accentInk, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 6),
              Icon(Icons.done_rounded, color: c.accentInk, size: 20),
            ],
          ),
        ),
        child: card,
      ),
    );
  }

  Widget? _trailing(BuildContext context) {
    switch (notice.kind) {
      case NoticeKind.grade:
      case NoticeKind.exam:
        final score = notice.score;
        if (score == null) return null;
        return _ScoreRing(score: score, max: notice.maxScore, percent: notice.percent);
      case NoticeKind.point:
        final p = notice.points;
        if (p == null) return null;
        final look = _kindLook(context, notice.kind, notice);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: look.color.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            p > 0 ? '+$p' : '$p',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: look.color),
          ),
        );
      case NoticeKind.attendance:
      case NoticeKind.behavior:
      case NoticeKind.other:
        return null;
    }
  }
}

/// A score in a ring that fills to its share of the maximum, coloured like
/// scores elsewhere in the app.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.max, required this.percent});
  final num score;
  final num? max, percent;

  static String _n(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(context, percent ?? (max == null ? null : score));
    return SizedBox(
      width: 52,
      height: 52,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ((percent ?? 0) / 100).clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: percent == null ? 0 : t,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_n(score), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color, height: 1.1)),
                if (max != null)
                  Text('/${_n(max!)}', style: TextStyle(fontSize: 10, color: context.c.muted, height: 1.1)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Settings

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.inTab = false});

  /// Shown as a bottom-bar tab: no app bar of its own, a heading instead.
  final bool inTab;
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

    final list = ListView(
      padding: EdgeInsets.fromLTRB(16, widget.inTab ? 8 : 16, 16, 32),
      children: [
        if (widget.inTab)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(context.t('nav.settings'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
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
        const SizedBox(height: 20),
        const _NotificationChoices(),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _push(context, const PasskeysScreen()),
          icon: const Icon(Icons.key_outlined, size: 18),
          label: Text(context.t('passkey.title')),
        ),
        const SizedBox(height: 8),
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
    );
    if (widget.inTab) return list;
    return _Page(title: context.t('nav.settings'), child: list);
  }
}

/// One switch per kind of push. The bell inside the app keeps everything;
/// these only decide what reaches the phone.
class _NotificationChoices extends StatelessWidget {
  const _NotificationChoices();

  static const _icons = {
    'attendance': Icons.event_busy_outlined,
    'attendance_present': Icons.event_available_outlined,
    'behavior': Icons.sentiment_satisfied_alt_outlined,
    'point': Icons.emoji_events_outlined,
    'grade': Icons.star_outline,
    'exam': Icons.school_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final push = context.watch<Push>();
    final c = context.c;
    // A build without Firebase has no push to choose about.
    if (!push.available) return const SizedBox.shrink();
    final notes = [
      if (!push.granted) context.t('settings.notifyOff'),
      if (push.serverSupportsMuting == false) context.t('settings.notifyServerOld'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.t('settings.notifications')),
        PanelList(
          children: [
            for (final kind in Push.kinds)
              SwitchListTile.adaptive(
                value: push.isOn(kind),
                onChanged: (on) => push.setOn(kind, on),
                secondary: Icon(_icons[kind], size: 20, color: c.muted),
                title: Text(context.t('notify.$kind'), style: const TextStyle(fontSize: 15)),
                dense: true,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            [context.t('settings.notifyHint'), ...notes].join('\n'),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
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

// ---------------------------------------------------------------- Passkeys

/// The account's passkeys: add one on this phone, or delete old ones.
class PasskeysScreen extends StatefulWidget {
  const PasskeysScreen({super.key});
  @override
  State<PasskeysScreen> createState() => _PasskeysScreenState();
}

class _PasskeysScreenState extends State<PasskeysScreen> {
  static const _key = 'passkeys';
  bool _busy = false;
  String? _messageKey;
  bool _messageIsError = false;

  void _say(String key, {bool error = false}) => setState(() {
    _messageKey = key;
    _messageIsError = error;
  });

  Future<void> _add(Future<void> Function() reload) async {
    final auth = context.read<Auth>();
    setState(() {
      _busy = true;
      _messageKey = null;
    });
    try {
      await auth.passkeys.add();
      // Added here, so there's nothing left to offer after the next SMS login.
      await auth.closePasskeyOffer();
      await reload();
      if (mounted) _say('passkey.added');
    } on PasskeyCancelled {
      // Closed the system sheet: nothing to say.
    } catch (e) {
      if (mounted) _say(passkeyErrorKey(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(Json key, Future<void> Function() reload) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(d.t('passkey.deleteConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(d.t('passkey.delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _messageKey = null);
    try {
      await context.read<ParentApi>().deletePasskey((key['id'] as num).toInt());
    } catch (e) {
      if (mounted) _say(errorKey(e), error: true);
    }
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Query<Json>(
      cacheKey: _key,
      load: api.passkeys,
      builder: (context, q) {
        final keys = _list(q.data?['result']);
        final serverOff = q.data == null && passkeysOffOnServer(q.error);
        Widget list;
        if (q.loading) {
          list = const LoadingState();
        } else if (q.data == null && serverOff) {
          list = EmptyState(text: context.t('passkey.serverOff'), icon: Icons.key_off_outlined);
        } else if (q.data == null) {
          list = ErrorState(error: q.error, onRetry: q.reload);
        } else if (keys.isEmpty) {
          list = EmptyState(text: context.t('passkey.empty'), icon: Icons.key_off_outlined);
        } else {
          list = PanelList(
            children: [
              for (final k in keys)
                ListTile(
                  leading: Icon(k['synced'] == true ? Icons.cloud_done_outlined : Icons.key_outlined, color: c.accent),
                  title: Text('${k['name'] ?? ''}'),
                  subtitle: Text(
                    k['last_used_at'] == null
                        ? context.t('passkey.neverUsed')
                        : context.t('passkey.lastUsed', {'when': f.moment(k['last_used_at'] as Object)}),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  trailing: IconButton(
                    tooltip: context.t('passkey.delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(k, q.reload),
                  ),
                ),
            ],
          );
        }
        return _Page(
          title: context.t('passkey.title'),
          child: RefreshIndicator(
            onRefresh: q.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(context.t('passkey.offerBody'), style: TextStyle(color: c.muted)),
                const SizedBox(height: 16),
                list,
                const SizedBox(height: 16),
                if (!serverOff)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _add(q.reload),
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
                    label: Text(context.t('passkey.add')),
                  ),
                if (_messageKey != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      context.t(_messageKey!),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _messageIsError
                            ? (dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48))
                            : (dark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
