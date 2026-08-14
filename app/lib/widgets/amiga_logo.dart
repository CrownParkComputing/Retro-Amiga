import 'package:flutter/material.dart';

/// The Amiga tick, drawn rather than shipped as a bitmap so it stays crisp at
/// any size and density.
///
/// The colours are the AmigaOS boot tick's, sampled from the artwork the
/// launcher used: red at the top of the long arm running down through orange
/// and yellow into green at the elbow. Not the red-and-white Commodore
/// wordmark tick - this is the one people picture when they think of an Amiga
/// booting.
class AmigaLogo extends StatelessWidget {
  const AmigaLogo({super.key, this.height = 44});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * _AmigaTickPainter.aspect,
      child: const CustomPaint(painter: _AmigaTickPainter()),
    );
  }
}

class _AmigaTickPainter extends CustomPainter {
  const _AmigaTickPainter();

  /// Width relative to height: the tick leans right, so it needs the room.
  static const double aspect = 1.1;

  /// Sampled from the original artwork, ordered along the tick.
  static const List<Color> _bands = <Color>[
    Color(0xFFFE3814), // red, top of the long arm
    Color(0xFFFE8801), // orange
    Color(0xFFFED802), // yellow
    Color(0xFFEEEF00), // yellow-green
    Color(0xFF5CE468), // green
    Color(0xFF17CE76), // green-cyan, into the elbow
  ];

  static const Color _outline = Color(0xFF182C48);

  Path _tick(Size size) {
    final double w = size.width;
    final double h = size.height;
    // Long arm down from top right, elbow bottom left, short arm back up.
    const List<Offset> points = <Offset>[
      Offset(0.72, 0.04),
      Offset(0.99, 0.16),
      Offset(0.40, 0.96),
      Offset(0.02, 0.56),
      Offset(0.16, 0.40),
      Offset(0.41, 0.66),
    ];
    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      final double x = points[i].dx * w;
      final double y = points[i].dy * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = _tick(size);

    // The bands run down the tick rather than across, which is what makes it
    // read as the Amiga one and not a generic rainbow.
    final Paint fill = Paint()
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: _bands,
      ).createShader(Offset.zero & size);

    canvas.drawPath(path, fill);

    // A dark edge, as the original has: without it the yellow disappears on a
    // light background.
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.045
        ..color = _outline,
    );
  }

  @override
  bool shouldRepaint(_AmigaTickPainter oldDelegate) => false;
}
