import 'package:flutter/material.dart';

/// The Dombit "D" mark on a transparent background.
///
/// Drawn from the path data of SchoolProject/oneorg-frontend/public/images/2.svg
/// (viewBox 261 x 292), so it stays sharp at any size.
class DombitLogo extends StatelessWidget {
  const DombitLogo({super.key, this.height = 120});
  final double height;

  static const _w = 261.0, _h = 292.0;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: height * _w / _h,
        height: height,
        child: const CustomPaint(painter: _DombitLogoPainter()),
      );
}

class _DombitLogoPainter extends CustomPainter {
  const _DombitLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / DombitLogo._w, size.height / DombitLogo._h);

    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(98.2778, 291.532)
      ..cubicTo(67.9636, 291.526, 30.2397, 290.918, 0, 290.918)
      ..lineTo(0, 0)
      ..cubicTo(30.3906, 0, 90.427, 0.0228452, 120.818, 0.0228452)
      ..cubicTo(217.056, 0.0228452, 261, 64.8391, 261, 145.459)
      ..cubicTo(261, 199.11, 231.758, 246.044, 183.83, 271.441)
      ..lineTo(183.83, 100.376)
      ..lineTo(98.2778, 65.9797)
      ..close();

    final shadow = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(98.2778, 65.9795)
      ..lineTo(98.2784, 291.532)
      ..lineTo(0, 290.914)
      ..close();

    canvas.drawPath(body, Paint()..color = const Color(0xFF623697));
    canvas.drawPath(shadow, Paint()..color = const Color(0xFF4F1A84));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
