import 'package:flutter/material.dart';

/// The Amiga check mark, drawn rather than shipped as a bitmap so it stays
/// crisp at any size and on any screen density.
///
/// Two overlapping ticks, the front one white and the one behind it red,
/// offset up and to the right — the mark Commodore put on the machines.
class AmigaLogo extends StatelessWidget {
  const AmigaLogo({super.key, this.height = 44, this.frontColour});

  final double height;

  /// The front tick. Defaults to white, which reads on a dark background;
  /// pass something darker when the backdrop is light.
  final Color? frontColour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * _AmigaCheckPainter.aspect,
      child: CustomPaint(
        painter: _AmigaCheckPainter(
          front: frontColour ?? Colors.white,
        ),
      ),
    );
  }
}

class _AmigaCheckPainter extends CustomPainter {
  const _AmigaCheckPainter({required this.front});

  final Color front;

  /// Width relative to height, chosen so the two ticks and the offset fit
  /// without clipping.
  static const double aspect = 1.35;

  static const Color _behind = Color(0xFFE1122F);

  /// The tick as a closed path in a unit square, so it scales by multiply.
  Path _tick(Size size, double dx, double dy) {
    final double w = size.width;
    final double h = size.height;
    // Points run: outer top of the long arm, down to the elbow, out to the
    // short arm's tip, and back up the inside edge.
    final List<Offset> points = <Offset>[
      Offset(0.62, 0.02),
      Offset(0.99, 0.02),
      Offset(0.34, 0.98),
      Offset(0.01, 0.55),
      Offset(0.19, 0.36),
      Offset(0.36, 0.60),
    ];
    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      final double x = (points[i].dx + dx) * w;
      final double y = (points[i].dy + dy) * h;
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
    // The unit paths are drawn into a square region; the extra width in the
    // box is what the rear tick's offset uses.
    final Size square = Size(size.height, size.height);
    final Paint paint = Paint()..isAntiAlias = true;

    canvas.drawPath(_tick(square, 0.26, -0.02), paint..color = _behind);
    canvas.drawPath(_tick(square, 0.0, 0.02), paint..color = front);
  }

  @override
  bool shouldRepaint(_AmigaCheckPainter oldDelegate) =>
      oldDelegate.front != front;
}
