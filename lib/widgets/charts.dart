import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Two weeks of daily averages on one 0–100 scale: this week as a solid line
/// with a soft fill, last week dashed behind it. Drawn for a coloured
/// background ([ink] is the line colour). Touch or drag to read a day.
class WeekLineChart extends StatefulWidget {
  const WeekLineChart({
    super.key,
    required this.current,
    required this.previous,
    required this.labels,
    required this.ink,
    this.todayIndex,
    this.height = 150,
    this.labelEvery = 1,
  });

  /// One value per day; null where there is no grade (or the day is ahead).
  final List<double?> current, previous;
  final List<String> labels;
  final Color ink;
  final int? todayIndex;
  final double height;

  /// With many days, label only every n-th (today and the last always).
  final int labelEvery;

  @override
  State<WeekLineChart> createState() => _WeekLineChartState();
}

class _WeekLineChartState extends State<WeekLineChart> {
  int? _selected;

  void _pick(Offset local, double width) {
    final n = widget.labels.length;
    if (n < 2) return;
    final i = ((local.dx - _LinePainter.left) / (width - _LinePainter.left - _LinePainter.right) * (n - 1))
        .round()
        .clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragStart: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragEnd: (_) => setState(() => _selected = null),
        onTapUp: (_) => Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _selected = null);
        }),
        child: TweenAnimationBuilder<double>(
          // Draws itself in from the left whenever it is first shown.
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            size: Size(box.maxWidth, widget.height),
            painter: _LinePainter(
              current: widget.current,
              previous: widget.previous,
              labels: widget.labels,
              ink: widget.ink,
              todayIndex: widget.todayIndex,
              labelEvery: widget.labelEvery,
              selected: _selected,
              progress: t,
              tooltipInk: context.c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.current,
    required this.previous,
    required this.labels,
    required this.ink,
    required this.todayIndex,
    required this.labelEvery,
    required this.selected,
    required this.progress,
    required this.tooltipInk,
  });

  static const left = 26.0, right = 8.0, top = 10.0, bottom = 22.0;

  final List<double?> current, previous;
  final List<String> labels;
  final Color ink, tooltipInk;
  final int? todayIndex, selected;
  final int labelEvery;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final values = [...current, ...previous].whereType<double>();
    // Scores sit high; start the scale near the lowest one so changes show.
    // Never above 50, so a run of 100s still sits on a readable scale.
    final lo = values.isEmpty
        ? 0.0
        : math.min(50.0, math.max(0.0, ((values.reduce(math.min) - 5) / 10).floor() * 10.0));
    const hi = 100.0;
    double x(int i) => left + (n == 1 ? w / 2 : w * i / (n - 1));
    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));

    // Recessive grid: three hairlines with their values.
    final grid = Paint()
      ..color = ink.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (final v in [lo, (lo + hi) / 2, hi]) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - right, y(v)), grid);
      _text(
        canvas,
        v.round().toString(),
        Offset(0, y(v) - 6),
        10,
        ink.withValues(alpha: 0.6),
        width: left - 6,
        align: TextAlign.right,
      );
    }
    for (var i = 0; i < n; i++) {
      final today = i == todayIndex;
      if (i % labelEvery != 0 && !today && i != n - 1) continue;
      _text(
        canvas,
        labels[i],
        Offset(x(i) - 16, size.height - 15),
        11,
        ink.withValues(alpha: today ? 1 : 0.65),
        width: 32,
        align: TextAlign.center,
        bold: today,
      );
    }

    // Reveal left to right.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, left + w * progress + 6, size.height));

    // Last week: dashed, quieter.
    final prev = Paint()
      ..color = ink.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final seg in _segments(previous, x, y)) {
      _dashed(canvas, seg, prev);
    }

    // This week: area, then the line, then the points.
    for (final seg in _segments(current, x, y)) {
      if (seg.length > 1) {
        final area = Path()..moveTo(seg.first.dx, top + h);
        for (final p in seg) {
          area.lineTo(p.dx, p.dy);
        }
        area.lineTo(seg.last.dx, top + h);
        canvas.drawPath(
          area,
          Paint()
            ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + h), [
              ink.withValues(alpha: 0.32),
              ink.withValues(alpha: 0),
            ]),
        );
      }
      canvas.drawPath(
        _smooth(seg),
        Paint()
          ..color = ink
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (var i = 0; i < n; i++) {
      final v = current[i];
      if (v == null) continue;
      final big = i == selected || (selected == null && i == _lastIndex(current));
      canvas.drawCircle(Offset(x(i), y(v)), big ? 6 : (n > 10 ? 2.5 : 4), Paint()..color = ink);
      canvas.drawCircle(Offset(x(i), y(v)), big ? 3 : (n > 10 ? 1.2 : 2), Paint()..color = const Color(0xFF6D28D9));
    }
    canvas.restore();

    // Touch: a guide and the two values.
    final s = selected;
    if (s != null && progress == 1) {
      canvas.drawLine(Offset(x(s), top), Offset(x(s), top + h), Paint()..color = ink.withValues(alpha: 0.35));
      final now = current[s], before = previous[s];
      final lines = [labels[s], if (now != null) '● ${now.round()}', if (before != null) '┄ ${before.round()}'];
      if (lines.length > 1) {
        final tp = TextPainter(
          text: TextSpan(
            style: TextStyle(fontSize: 12, color: tooltipInk, height: 1.35),
            children: [
              TextSpan(
                text: lines.first,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final l in lines.skip(1)) TextSpan(text: '\n$l'),
            ],
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final bw = tp.width + 16, bh = tp.height + 10;
        var bx = x(s) + 8;
        if (bx + bw > size.width) bx = x(s) - 8 - bw;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(bx, top, bw, bh), const Radius.circular(8));
        canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.12));
        canvas.drawRRect(r, Paint()..color = Colors.white);
        tp.paint(canvas, Offset(bx + 8, top + 5));
      }
    }
  }

  static int? _lastIndex(List<double?> list) {
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i] != null) return i;
    }
    return null;
  }

  /// Runs of consecutive days that have a value; a gap breaks the line.
  static List<List<Offset>> _segments(List<double?> v, double Function(int) x, double Function(double) y) {
    final out = <List<Offset>>[];
    var run = <Offset>[];
    for (var i = 0; i < v.length; i++) {
      final value = v[i];
      if (value == null) {
        if (run.isNotEmpty) out.add(run);
        run = [];
      } else {
        run.add(Offset(x(i), y(value)));
      }
    }
    if (run.isNotEmpty) out.add(run);
    return out;
  }

  /// A gentle curve through the points (monotone enough for five days).
  static Path _smooth(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 1; i < p.length; i++) {
      final a = p[i - 1], b = p[i];
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    return path;
  }

  static void _dashed(Canvas canvas, List<Offset> seg, Paint paint) {
    if (seg.length == 1) {
      canvas.drawCircle(seg.first, 2.5, Paint()..color = paint.color);
      return;
    }
    for (final metric in _smooth(seg).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  static void _text(
    Canvas canvas,
    String s,
    Offset at,
    double size,
    Color color, {
    double width = 40,
    TextAlign align = TextAlign.left,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.current != current ||
      old.previous != previous ||
      old.ink != ink;
}

/// The same two periods as [WeekLineChart], as paired columns: the period
/// before pale on the left, this one solid on the right, on a 0–100 scale.
/// Tap a day to read both values.
class WeekBarChart extends StatefulWidget {
  const WeekBarChart({
    super.key,
    required this.current,
    required this.previous,
    required this.labels,
    required this.ink,
    this.todayIndex,
    this.height = 150,
    this.labelEvery = 1,
    this.unit = '',
  });

  final List<double?> current, previous;
  final List<String> labels;
  final Color ink;
  final int? todayIndex;
  final double height;
  final int labelEvery;
  final String unit;

  @override
  State<WeekBarChart> createState() => _WeekBarChartState();
}

class _WeekBarChartState extends State<WeekBarChart> {
  int? _selected;

  void _pick(Offset local, double width) {
    final n = widget.labels.length;
    if (n == 0) return;
    final slot = (width - _BarPainter.left - _BarPainter.right) / n;
    final i = ((local.dx - _BarPainter.left) / slot).floor().clamp(0, n - 1);
    setState(() => _selected = _selected == i ? null : i);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(d.localPosition, box.maxWidth),
        child: TweenAnimationBuilder<double>(
          // Columns grow from the baseline when first shown.
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            size: Size(box.maxWidth, widget.height),
            painter: _BarPainter(
              current: widget.current,
              previous: widget.previous,
              labels: widget.labels,
              ink: widget.ink,
              todayIndex: widget.todayIndex,
              labelEvery: widget.labelEvery,
              selected: _selected,
              progress: t,
              tooltipInk: context.c.ink,
              unit: widget.unit,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.current,
    required this.previous,
    required this.labels,
    required this.ink,
    required this.todayIndex,
    required this.labelEvery,
    required this.selected,
    required this.progress,
    required this.tooltipInk,
    required this.unit,
  });

  static const left = 26.0, right = 4.0, top = 10.0, bottom = 22.0;

  final List<double?> current, previous;
  final List<String> labels;
  final Color ink, tooltipInk;
  final int? todayIndex, selected;
  final int labelEvery;
  final double progress;
  final String unit;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final slot = w / n;
    double y(double v) => top + h * (1 - v.clamp(0, 100) / 100);

    // Recessive grid; bars always start at zero.
    final grid = Paint()
      ..color = ink.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (final v in [0.0, 50.0, 100.0]) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - right, y(v)), grid);
      _LinePainter._text(
        canvas,
        v.round().toString(),
        Offset(0, y(v) - 6),
        10,
        ink.withValues(alpha: 0.6),
        width: left - 6,
        align: TextAlign.right,
      );
    }

    // A pair per day: 2px apart, the pair narrower than its slot.
    final dense = n > 10;
    final gap = dense ? 1.0 : 2.0;
    final pair = math.min(slot * (dense ? 0.8 : 0.62), 40.0);
    final bw = (pair - gap) / 2;
    final sel = selected;

    void bar(double x, double? v, Color color, {double? width}) {
      if (v == null) return;
      // A zero still shows as a stub on the baseline.
      final y0 = math.min(y(v * progress), top + h - 2);
      final r = Radius.circular(math.min(4, (width ?? bw) / 2));
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(x, y0, x + (width ?? bw), top + h), topLeft: r, topRight: r),
        Paint()..color = color,
      );
    }

    for (var i = 0; i < n; i++) {
      final cx = left + slot * (i + 0.5);
      final dim = sel != null && sel != i ? 0.4 : 1.0;
      final p = previous[i], c = current[i];
      if (dense && (p == null || c == null)) {
        // Over 30 days a day rarely has both: give the one bar the whole pair.
        bar(cx - pair / 2, p, ink.withValues(alpha: 0.38 * dim), width: pair);
        bar(cx - pair / 2, c, ink.withValues(alpha: dim), width: pair);
      } else {
        bar(cx - pair / 2, p, ink.withValues(alpha: 0.38 * dim));
        bar(cx - pair / 2 + bw + gap, c, ink.withValues(alpha: dim));
      }

      final today = i == todayIndex;
      if (i % labelEvery != 0 && !today && i != n - 1) continue;
      _LinePainter._text(
        canvas,
        labels[i],
        Offset(cx - 16, size.height - 15),
        11,
        ink.withValues(alpha: today || i == sel ? 1 : 0.65),
        width: 32,
        align: TextAlign.center,
        bold: today || i == sel,
      );
    }

    // Tapped day: both values.
    if (sel != null && progress == 1) {
      final now = current[sel], before = previous[sel];
      final lines = [
        labels[sel],
        if (now != null) '■ ${now.round()}$unit',
        if (before != null) '□ ${before.round()}$unit',
      ];
      if (lines.length > 1) {
        final tp = TextPainter(
          text: TextSpan(
            style: TextStyle(fontSize: 12, color: tooltipInk, height: 1.35),
            children: [
              TextSpan(
                text: lines.first,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final l in lines.skip(1)) TextSpan(text: '\n$l'),
            ],
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final cx = left + slot * (sel + 0.5);
        final boxW = tp.width + 16, boxH = tp.height + 10;
        var bx = cx + pair / 2 + 6;
        if (bx + boxW > size.width) bx = cx - pair / 2 - 6 - boxW;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(bx, top, boxW, boxH), const Radius.circular(8));
        canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.12));
        canvas.drawRRect(r, Paint()..color = Colors.white);
        tp.paint(canvas, Offset(bx + 8, top + 5));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.current != current ||
      old.previous != previous ||
      old.ink != ink;
}

/// One row per subject: this week's average as a solid bar over last week's
/// as a pale one, with the change at the end.
class SubjectCompareBars extends StatelessWidget {
  const SubjectCompareBars({super.key, required this.rows, this.onTap});

  final List<({String name, double? now, double? before})> rows;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        for (final (i, r) in rows.indexed)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bar(value: r.now, color: c.accent, delay: i * 70),
                        const SizedBox(height: 3),
                        _Bar(value: r.before, color: c.line, delay: i * 70, thin: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 30,
                    child: Text(
                      // No grade yet this week: last week's score, greyed.
                      r.now != null ? '${r.now!.round()}' : (r.before != null ? '${r.before!.round()}' : '—'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: r.now == null ? c.muted.withValues(alpha: 0.7) : c.ink,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: DeltaText(now: r.now, before: r.before, align: TextAlign.right),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.delay, this.thin = false});
  final double? value;
  final Color color;
  final int delay;
  final bool thin;

  @override
  Widget build(BuildContext context) {
    final target = ((value ?? 0) / 100).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: Duration(milliseconds: 700 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => FractionallySizedBox(
        widthFactor: math.max(t, value == null ? 0 : 0.02),
        child: Container(
          height: thin ? 6 : 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

/// "▲ 6" in green, "▼ 3" in red, "=" when level; nothing without both weeks.
class DeltaText extends StatelessWidget {
  const DeltaText({super.key, required this.now, required this.before, this.align = TextAlign.left, this.suffix = ''});
  final double? now, before;
  final TextAlign align;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    if (now == null || before == null) return const SizedBox.shrink();
    final d = (now! - before!).round();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final up = dark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final down = dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
    final text = d == 0 ? '=' : '${d > 0 ? '▲' : '▼'} ${d.abs()}$suffix';
    return Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: d == 0 ? context.c.muted : (d > 0 ? up : down),
      ),
    );
  }
}

/// A gradient headline card: a big number, its change against the period
/// before, and a [WeekLineChart] of both periods underneath.
class HeroChartCard extends StatelessWidget {
  const HeroChartCard({
    super.key,
    required this.title,
    required this.value,
    required this.loading,
    required this.unit,
    required this.current,
    required this.previous,
    required this.labels,
    required this.currentLabel,
    required this.previousLabel,
    required this.changeLabel,
    this.before,
    this.badge,
    this.note,
    this.todayIndex,
    this.labelEvery = 1,
    this.changeSuffix = '',
    this.bars = false,
    this.onTap,
  });

  /// Paired columns instead of lines.
  final bool bars;
  final String title, unit, currentLabel, previousLabel, changeLabel, changeSuffix;
  final double? value, before;
  final bool loading;
  final String? badge, note;
  final List<double?>? current, previous;
  final List<String> labels;
  final int? todayIndex;
  final int labelEvery;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cur = current, prev = previous;
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF5B21B6), Color(0xFF3730A3)]
                : const [Color(0xFF8B5CF6), Color(0xFF6D28D9), Color(0xFF4F46E5)],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: value ?? 0),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(
                        value == null ? (loading ? '…' : '—') : '${v.round()}',
                        style: const TextStyle(
                          fontSize: 48,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          color: white,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        unit,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (value != null && before != null)
                      Flexible(
                        flex: 3,
                        child: _ChangePill(now: value!, before: before!, label: changeLabel, suffix: changeSuffix),
                      ),
                  ],
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note!, style: TextStyle(fontSize: 12, color: white.withValues(alpha: 0.8))),
                  ),
                const SizedBox(height: 10),
                if (cur != null && prev != null && bars)
                  WeekBarChart(
                    current: cur,
                    previous: prev,
                    labels: labels,
                    todayIndex: todayIndex,
                    labelEvery: labelEvery,
                    ink: white,
                    unit: unit == '%' ? '%' : '',
                  )
                else if (cur != null && prev != null)
                  WeekLineChart(
                    current: cur,
                    previous: prev,
                    labels: labels,
                    todayIndex: todayIndex,
                    labelEvery: labelEvery,
                    ink: white,
                  )
                else
                  const SizedBox(height: 150),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _Legend(dashed: false, label: currentLabel, square: bars),
                    _Legend(dashed: true, label: previousLabel, square: bars),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.now, required this.before, required this.label, required this.suffix});
  final double now, before;
  final String label, suffix;
  @override
  Widget build(BuildContext context) {
    final d = (now - before).round();
    final icon = d > 0 ? Icons.trending_up : (d < 0 ? Icons.trending_down : Icons.trending_flat);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: d >= 0 ? const Color(0xFF059669) : const Color(0xFFE11D48)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${d > 0 ? '+' : ''}$d$suffix $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E1B2E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.dashed, required this.label, this.square = false});
  final bool dashed, square;
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: dashed ? 0.6 : 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (square)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: dashed ? 0.38 : 1),
              borderRadius: BorderRadius.circular(3),
            ),
          )
        else if (dashed)
          for (var i = 0; i < 3; i++) ...[
            Container(width: 4, height: 2, color: color),
            if (i < 2) const SizedBox(width: 2),
          ]
        else
          Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
  }
}

/// One column per day, split by attendance status (bottom to top in
/// [order]), as tall as that day's lessons. Tap a column to read it.
class DailyStackedBars extends StatefulWidget {
  const DailyStackedBars({
    super.key,
    required this.days,
    required this.order,
    required this.colorOf,
    required this.describe,
    this.labelEvery = 1,
    this.height = 140,
  });

  final List<({String label, String title, Map<String, int> counts})> days;
  final List<String> order;
  final Color Function(String status) colorOf;

  /// The line shown for a tapped day, e.g. "Se, 18 noy · 5 keldi, 1 kechikdi".
  final String Function(int index) describe;
  final int labelEvery;
  final double height;

  @override
  State<DailyStackedBars> createState() => _DailyStackedBarsState();
}

class _DailyStackedBarsState extends State<DailyStackedBars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final days = widget.days;
    final most = days.fold<int>(1, (m, d) => math.max(m, d.counts.values.fold(0, (a, b) => a + b)));
    final n = days.length;
    final gap = n > 10 ? 3.0 : 8.0;
    final sel = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: Text(
            sel == null ? '' : widget.describe(sel),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.ink),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, d) in days.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = _selected == i ? null : i),
                    child: _Column(
                      counts: d.counts,
                      order: widget.order,
                      colorOf: widget.colorOf,
                      share: d.counts.values.fold(0, (a, b) => a + b) / most,
                      dimmed: sel != null && sel != i,
                      delay: i * (n > 10 ? 15 : 60),
                      empty: c.line,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, d) in days.indexed) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: Text(
                  i % widget.labelEvery == 0 || i == n - 1 ? d.label : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    color: i == sel ? c.ink : c.muted,
                    fontWeight: i == sel ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.counts,
    required this.order,
    required this.colorOf,
    required this.share,
    required this.dimmed,
    required this.delay,
    required this.empty,
  });
  final Map<String, int> counts;
  final List<String> order;
  final Color Function(String) colorOf;
  final double share;
  final bool dimmed;
  final int delay;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final s in order)
        if ((counts[s] ?? 0) > 0) s,
    ];
    return LayoutBuilder(
      builder: (context, box) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: share),
        duration: Duration(milliseconds: 700 + delay),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: dimmed ? 0.35 : 1,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: parts.isEmpty
                // A school day with nothing marked: a stub on the baseline.
                ? Container(
                    height: 3,
                    decoration: BoxDecoration(color: empty, borderRadius: BorderRadius.circular(2)),
                  )
                : SizedBox(
                    height: math.max(4, box.maxHeight * t),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      child: Column(
                        verticalDirection: VerticalDirection.up,
                        children: [
                          for (final (i, s) in parts.indexed) ...[
                            // A 2px gap between segments keeps them apart.
                            if (i > 0) const SizedBox(height: 2),
                            Expanded(
                              flex: counts[s]!,
                              child: Container(color: colorOf(s)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
