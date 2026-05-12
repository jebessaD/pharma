import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Matches [formatSaleReceiptText] header; body lines follow these.
List<String> _receiptBodyLines(String full) {
  final lines = full.split('\n');
  if (lines.length >= 2) {
    if (lines[0].trim() == 'Pharma Shelf' &&
        lines[1].trim().toLowerCase() == 'sales receipt') {
      return lines.sublist(2);
    }
    if (lines[0].contains('PHARMACY RECEIPT')) {
      return lines.sublist(1);
    }
  }
  return lines;
}

/// Renders a branded **Pharma Shelf** receipt PNG for share / download.
Future<Uint8List?> buildReceiptPngBytes(
  String plainText, {
  double pixelRatio = 3,
}) async {
  final trimmed = plainText.trim();
  if (trimmed.isEmpty) return null;

  const brand = Color(0xFF2E7D32);
  const brandDark = Color(0xFF1B5E20);
  const pageBg = Color(0xFFECEFF1);
  const cardBg = Color(0xFFFFFFFF);
  const bodyColor = Color(0xFF263238);
  const mutedColor = Color(0xFF78909C);
  const ruleColor = Color(0xFFB0BEC5);

  final pr = pixelRatio;
  final margin = 14.0 * pr;
  final headerH = 78.0 * pr;
  final gap = 10.0 * pr;
  final cardPad = 20.0 * pr;
  final bottomPad = 22.0 * pr;
  final contentW = 360.0 * pr;
  final w = contentW + margin * 2;

  final bodyLines = _receiptBodyLines(trimmed);
  final baseSize = 11.2 * pr;
  final baseStyle = TextStyle(
    color: bodyColor,
    fontSize: baseSize,
    height: 1.48,
    letterSpacing: 0.15,
  );
  final mutedStyle = baseStyle.copyWith(
    color: mutedColor,
    fontSize: 10.2 * pr,
    height: 1.45,
  );
  final boldStyle = baseStyle.copyWith(
    fontWeight: FontWeight.w700,
    fontSize: 12.4 * pr,
    height: 1.35,
    letterSpacing: 0.2,
  );

  final spans = <InlineSpan>[];
  for (final line in bodyLines) {
    final t = line.trimRight();
    if (t.trim() == '---') {
      // ASCII hyphen-minus (U+002D) so rules render on every system/font;
      // Unicode box-drawing (e.g. U+2500) often shows as □/X when missing from a font.
      spans.add(
        TextSpan(
          text: '\n${''.padRight(44, '-')}\n',
          style: baseStyle.copyWith(
            color: ruleColor,
            letterSpacing: 0,
            height: 1.0,
          ),
        ),
      );
      continue;
    }
    if (t.startsWith('TOTAL:')) {
      spans.add(TextSpan(text: '$line\n', style: boldStyle));
      continue;
    }
    if (t.toLowerCase().startsWith('thank you')) {
      spans.add(TextSpan(text: '\n$line\n', style: mutedStyle));
      continue;
    }
    spans.add(TextSpan(text: '$line\n', style: baseStyle));
  }

  if (spans.isEmpty) {
    spans.add(TextSpan(text: ' ', style: baseStyle));
  }

  final bodyPainter = TextPainter(
    text: TextSpan(children: spans),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: contentW - cardPad * 2);

  final cardH = bodyPainter.height + cardPad * 2;
  final totalH = (margin + headerH + gap + cardH + bottomPad).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, totalH.toDouble()),
    Paint()..color = pageBg,
  );

  final headerRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(margin, margin, w - margin * 2, headerH),
    Radius.circular(12 * pr),
  );
  final headerShader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brand, Color.lerp(brand, brandDark, 0.55)!],
  ).createShader(headerRect.outerRect);
  canvas.drawRRect(headerRect, Paint()..shader = headerShader);

  final titleStyle = TextStyle(
    color: const Color(0xFFFFFFFF),
    fontSize: 22 * pr,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.1,
  );
  final subtitleStyle = TextStyle(
    color: const Color(0xFFFFFFFF).withValues(alpha: 0.92),
    fontSize: 12 * pr,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.6,
    height: 1.2,
  );

  final titlePainter = TextPainter(
    text: TextSpan(text: 'Pharma Shelf', style: titleStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  final subPainter = TextPainter(
    text: TextSpan(text: 'SALES RECEIPT', style: subtitleStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  final headerInnerW = w - margin * 2;
  final titleX = margin + (headerInnerW - titlePainter.width) / 2;
  final subX = margin + (headerInnerW - subPainter.width) / 2;
  final blockH = titlePainter.height + 5 * pr + subPainter.height;
  final headerContentTop = margin + headerH / 2 - blockH / 2;
  titlePainter.paint(canvas, Offset(titleX, headerContentTop));
  subPainter.paint(
    canvas,
    Offset(subX, headerContentTop + titlePainter.height + 5 * pr),
  );

  final cardTop = margin + headerH + gap;
  final cardRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(margin, cardTop, w - margin * 2, cardH),
    Radius.circular(14 * pr),
  );
  canvas.drawRRect(cardRect, Paint()..color = cardBg);
  canvas.drawRRect(
    cardRect,
    Paint()
      ..color = const Color(0x14000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );

  bodyPainter.paint(canvas, Offset(margin + cardPad, cardTop + cardPad));

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(w.ceil(), totalH);
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
