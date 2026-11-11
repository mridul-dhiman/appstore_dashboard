import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A QR code for [data], black on white with a quiet border, so a phone camera reads it in light and dark mode alike.
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 148});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR code for $data',
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x22000000)),
        ),
        child: CustomPaint(
          painter: QrPainter(QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M))),
        ),
      ),
    );
  }
}

class QrPainter extends CustomPainter {
  QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        // A hair of overlap so neighbouring squares leave no seams at fractional sizes.
        if (image.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.4, cell + 0.4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter old) => old.image != image;
}

/// Only Apple's own join links get a QR code.
bool isTestFlightLink(String? link) => link != null && link.startsWith('https://testflight.apple.com/');
