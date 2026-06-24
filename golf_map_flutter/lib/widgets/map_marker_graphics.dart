import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Classic golf flag pin — bottom of pole drawn at bottom of widget bounds.
/// Pair with flutter_map Marker(alignment: Alignment.topCenter).
class GreenFlagPin extends StatelessWidget {
  const GreenFlagPin({super.key, this.large = true});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final scale = large ? 1.0 : 0.72;
    return SizedBox(
      width: 28 * scale,
      height: 46 * scale,
      child: CustomPaint(
        painter: _FlagPinPainter(scale: scale),
      ),
    );
  }
}

class _FlagPinPainter extends CustomPainter {
  _FlagPinPainter({required this.scale});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final groundY = size.height - 2 * scale;

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, groundY + 1 * scale),
        width: 12 * scale,
        height: 4 * scale,
      ),
      Paint()..color = const Color(0x66000000),
    );

    // Pin hole
    canvas.drawCircle(
      Offset(cx, groundY),
      2.5 * scale,
      Paint()..color = const Color(0xFF1A1A1A),
    );

    final poleTop = groundY - 34 * scale;
    final polePaint = Paint()
      ..color = const Color(0xFFE8E8E8)
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(cx, groundY - 2 * scale), Offset(cx, poleTop), polePaint);

    // Pole highlight
    canvas.drawLine(
      Offset(cx - 0.5 * scale, groundY - 2 * scale),
      Offset(cx - 0.5 * scale, poleTop),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.8 * scale,
    );

    // Flag — red with white stripe
    final flagPath = Path()
      ..moveTo(cx, poleTop + 2 * scale)
      ..lineTo(cx + 14 * scale, poleTop + 8 * scale)
      ..lineTo(cx, poleTop + 14 * scale)
      ..close();

    canvas.drawPath(
      flagPath,
      Paint()
        ..color = const Color(0xFFE53935)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      flagPath,
      Paint()
        ..color = const Color(0xFFB71C1C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6 * scale,
    );

    // White chevron on flag
    final stripe = Path()
      ..moveTo(cx + 2 * scale, poleTop + 5 * scale)
      ..lineTo(cx + 10 * scale, poleTop + 8 * scale)
      ..lineTo(cx + 2 * scale, poleTop + 11 * scale);
    canvas.drawPath(
      stripe,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * scale
        ..strokeCap = StrokeCap.round,
    );

    // Pin head (ball on top of pole)
    canvas.drawCircle(
      Offset(cx, poleTop - 2 * scale),
      2.2 * scale,
      Paint()..color = const Color(0xFFFFD54F),
    );
    canvas.drawCircle(
      Offset(cx, poleTop - 2 * scale),
      2.2 * scale,
      Paint()
        ..color = const Color(0xFFF9A825)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6 * scale,
    );
  }

  @override
  bool shouldRepaint(covariant _FlagPinPainter oldDelegate) =>
      oldDelegate.scale != scale;
}

/// Golf ball with dimple texture.
class GolfBallMarker extends StatelessWidget {
  const GolfBallMarker({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 6,
      height: size + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentGreen.withValues(alpha: 0.45),
            blurRadius: 8,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size, size),
          painter: _GolfBallPainter(),
        ),
      ),
    );
  }
}

class _GolfBallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFF5F5F0),
            Color(0xFFD8D8D0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x44000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    final dimplePaint = Paint()..color = const Color(0x33000000);
    const dimpleR = 1.1;
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final dist = radius * 0.45;
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * dist,
          center.dy + math.sin(angle) * dist,
        ),
        dimpleR,
        dimplePaint,
      );
    }
    canvas.drawCircle(
      Offset(center.dx, center.dy + radius * 0.2),
      dimpleR,
      dimplePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
