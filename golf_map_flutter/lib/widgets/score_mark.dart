import 'package:flutter/material.dart';

class ScoreMark extends StatelessWidget {
  const ScoreMark({
    super.key,
    required this.score,
    required this.par,
    required this.color,
    required this.fontSize,
    this.width = 34,
    this.height = 28,
  });

  final int score;
  final int par;
  final Color color;
  final double fontSize;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (par <= 0 || score <= 0) {
      return Text(
        '$score',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      );
    }

    final relativeToPar = score - par;
    final showShape = relativeToPar != 0;

    if (!showShape) {
      return Text(
        '$score',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: ScoreMarkPainter(
          relativeToPar: relativeToPar,
          color: color,
        ),
        child: Center(
          child: Text(
            '$score',
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class ScoreMarkPainter extends CustomPainter {
  const ScoreMarkPainter({
    required this.relativeToPar,
    required this.color,
  });

  final int relativeToPar;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;

    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.shortestSide / 2 - 1;
    final inner = outer * 0.72;

    if (relativeToPar <= -2) {
      canvas.drawCircle(center, outer, paint);
      canvas.drawCircle(center, inner, paint);
    } else if (relativeToPar == -1) {
      canvas.drawCircle(center, outer * 0.92, paint);
    } else if (relativeToPar == 1) {
      _drawSquare(canvas, center, outer * 0.92, paint);
    } else if (relativeToPar >= 2) {
      _drawSquare(canvas, center, outer, paint);
      _drawSquare(canvas, center, inner, paint);
    }
  }

  void _drawSquare(Canvas canvas, Offset center, double half, Paint paint) {
    canvas.drawRect(
      Rect.fromCenter(center: center, width: half * 2, height: half * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ScoreMarkPainter oldDelegate) =>
      oldDelegate.relativeToPar != relativeToPar ||
      oldDelegate.color != color;
}
