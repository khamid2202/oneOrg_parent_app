import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/children.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/query.dart';
import '../widgets/theme.dart';
import 'lesson_row.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _date = DateTime.now();

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final child = context.watch<Children>().child!;
    final api = context.read<ParentApi>();
    final f = Fmt(context.lang);
    final now = DateTime.now();
    final day = iso(_date);
    final monday = mondayOf(_date);
    final c = context.c;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text(f.month(_date), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            if (!_same(_date, now))
              Pill(label: context.t('common.today'), selected: false, onTap: () => setState(() => _date = now)),
            IconButton(
              tooltip: context.t('common.previous'),
              onPressed: () => setState(() => _date = _date.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: context.t('common.next'),
              onPressed: () => setState(() => _date = _date.add(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Builder(builder: (context) {
                  final d = monday.add(Duration(days: i));
                  final selected = _same(d, _date);
                  final isToday = _same(d, now);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: selected ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _date = d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(f.weekday(d),
                                  style: TextStyle(fontSize: 12, color: selected ? c.page : c.muted)),
                              const SizedBox(height: 2),
                              Text('${d.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? c.page : (isToday ? c.accent : c.ink),
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SectionTitle(f.dayLong(_date)),
        QueryView<Map<String, dynamic>>(
          cacheKey: 'schedule:${child.id}:$day',
          load: () => api.schedule(child.id, day),
          isEmpty: (d) => _lessons(d).isEmpty,
          emptyText: context.t('schedule.empty'),
          builder: (context, data, _) =>
              PanelList(children: [for (final l in _lessons(data)) LessonRow(lesson: l)]),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _lessons(Map<String, dynamic> data) =>
      ((data['result'] as Map?)?['lessons'] as List? ?? const []).cast<Map<String, dynamic>>();
}
