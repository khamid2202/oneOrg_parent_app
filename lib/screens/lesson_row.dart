import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../l10n/strings.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/theme.dart';

/// What changed about a lesson: "cancel", "cover", "merge", or null.
String? lessonChange(Map<String, dynamic> lesson) {
  final sub = lesson['substitution'];
  if (sub is Map && sub['type'] != null) return '${sub['type']}';
  return lesson['status'] == 'cancelled' ? 'cancel' : null;
}

class LessonRow extends StatelessWidget {
  const LessonRow({super.key, required this.lesson});
  final Map<String, dynamic> lesson;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final change = lessonChange(lesson);
    final cancelled = change == 'cancel';
    final sub = lesson['substitution'] as Map?;
    final substitute = sub?['substitute_teacher'] as String?;
    final teacher = lesson['teacher'] as String?;
    final room = lesson['room'];
    final title = lesson['subject'] ?? lesson['text'] ?? lesson['time_slot'] ?? context.t('schedule.lesson');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amber = const Color(0xFFF59E0B);
    final rose = const Color(0xFFF43F5E);
    final changeColor = cancelled ? rose : amber;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hm(lesson['start_time']),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                Text(hm(lesson['end_time']), style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$title',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cancelled ? c.muted : c.ink,
                          decoration: cancelled ? TextDecoration.lineThrough : null,
                        )),
                    if (change != null)
                      Badge2(
                        text: context.t(kStrings['en']!.containsKey('schedule.change.$change')
                            ? 'schedule.change.$change'
                            : 'schedule.change.cover'),
                        bg: changeColor.withValues(alpha: dark ? 0.2 : 0.12),
                        fg: dark ? Color.lerp(changeColor, Colors.white, 0.35)! : Color.lerp(changeColor, Colors.black, 0.25)!,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12, color: c.muted),
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
                if (sub?['note'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${sub!['note']}', style: TextStyle(fontSize: 12, color: c.muted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
