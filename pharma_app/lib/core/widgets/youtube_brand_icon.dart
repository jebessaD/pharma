import 'package:flutter/material.dart';

/// YouTube logo drawn in Flutter (no font/asset dependency).
class YoutubeBrandIcon extends StatelessWidget {
  const YoutubeBrandIcon({
    super.key,
    this.size = 22,
    this.color,
  });

  final double size;

  /// Tint for the red rounded rectangle. Play triangle stays white unless
  /// [color] is white (then the whole mark is drawn in that single color).
  final Color? color;

  static const Color brandRed = Color(0xFFFF0000);

  @override
  Widget build(BuildContext context) {
    final brand = color ?? brandRed;
    final play = brand == Colors.white ? brand : Colors.white;

    return SizedBox(
      width: size,
      height: size * 0.72,
      child: CustomPaint(
        painter: _YoutubeLogoPainter(brandColor: brand, playColor: play),
      ),
    );
  }
}

class _YoutubeLogoPainter extends CustomPainter {
  _YoutubeLogoPainter({
    required this.brandColor,
    required this.playColor,
  });

  final Color brandColor;
  final Color playColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height * 0.2),
    );
    canvas.drawRRect(rect, Paint()..color = brandColor);

    final cx = size.width * 0.53;
    final cy = size.height * 0.5;
    final w = size.width * 0.34;
    final h = size.height * 0.42;
    final play = Path()
      ..moveTo(cx - w * 0.38, cy - h * 0.5)
      ..lineTo(cx + w * 0.52, cy)
      ..lineTo(cx - w * 0.38, cy + h * 0.5)
      ..close();
    canvas.drawPath(play, Paint()..color = playColor);
  }

  @override
  bool shouldRepaint(covariant _YoutubeLogoPainter oldDelegate) {
    return oldDelegate.brandColor != brandColor ||
        oldDelegate.playColor != playColor;
  }
}
