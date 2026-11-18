import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../util/dates.dart';
import 'theme.dart';

/// A rounded bordered box, the app's card.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.c.line),
        ),
        child: child,
      );
}

/// Rows inside a [Panel], with dividers between them.
class PanelList extends StatelessWidget {
  const PanelList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Panel(
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: context.c.line),
              children[i],
            ],
          ],
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.c.muted)),
            ),
            ?trailing,
          ],
        ),
      );
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 40});
  final String name;
  final String? url;
  final double size;

  String get _initials => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.c.accentSoft, shape: BoxShape.circle),
      child: Text(_initials,
          style: TextStyle(color: context.c.accentInk, fontWeight: FontWeight.w600, fontSize: size * 0.32)),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url!, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback),
    );
  }
}

/// A rounded toggle chip, used for filters and the child switcher.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.leading});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: selected ? c.accentSoft : c.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? c.accent : c.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leading == null ? 12 : 4, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? c.accentInk : c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of [Pill]s.
class PillRow extends StatelessWidget {
  const PillRow({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 6), children[i]],
          ],
        ),
      );
}

class Badge2 extends StatelessWidget {
  const Badge2({super.key, required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
      );
}

/// Colours per attendance status.
({Color solid, Color bg, Color fg}) attendanceColors(BuildContext context, String status) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  Color soft(Color c) => dark ? c.withValues(alpha: 0.2) : c.withValues(alpha: 0.12);
  final solid = switch (status) {
    'present' => const Color(0xFF10B981),
    'late' => const Color(0xFFF59E0B),
    'absent' => const Color(0xFFF43F5E),
    'excused' => const Color(0xFF0EA5E9),
    _ => const Color(0xFF94A3B8),
  };
  return (solid: solid, bg: soft(solid), fg: dark ? Color.lerp(solid, Colors.white, 0.35)! : Color.lerp(solid, Colors.black, 0.25)!);
}

class AttendanceBadge extends StatelessWidget {
  const AttendanceBadge({super.key, required this.status, this.minutesLate});
  final String status;
  final Object? minutesLate;
  @override
  Widget build(BuildContext context) {
    final colors = attendanceColors(context, status);
    var text = context.t('attendance.status.$status');
    if (status == 'late' && minutesLate != null) {
      text += ' · ${context.t('attendance.minutes', {'count': minutesLate})}';
    }
    return Badge2(text: text, bg: colors.bg, fg: colors.fg);
  }
}

/// Daily score out of 100 (or a percentage): green from 70, amber from 40.
Color scoreColor(BuildContext context, num? score) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (score == null) return context.c.muted;
  if (score >= 70) return dark ? const Color(0xFF34D399) : const Color(0xFF059669);
  if (score >= 40) return dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  return dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
}

/// "‹ November 2026 ›"
class MonthNav extends StatelessWidget {
  const MonthNav({super.key, required this.month, required this.onChange, this.max});
  final DateTime month;
  final ValueChanged<DateTime> onChange;
  final DateTime? max;
  @override
  Widget build(BuildContext context) {
    final next = DateTime(month.year, month.month + 1);
    final atMax = max != null && next.isAfter(max!);
    return Row(
      children: [
        Expanded(
          child: Text(Fmt(context.lang).month(month),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: context.t('common.previous'),
          onPressed: () => onChange(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: context.t('common.next'),
          onPressed: atMax ? null : () => onChange(next),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Number rows from the API arrive as int, double or string.
num? asNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

String fmtNum(Object? v) {
  final n = asNum(v);
  if (n == null) return '—';
  return n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);
}
