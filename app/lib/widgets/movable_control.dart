import 'package:flutter/material.dart';

import '../data/pad_layout.dart';

/// A control that can be dragged to a new place while the pad is being
/// designed. Shared by the designer in Settings and, historically, the
/// in-game overlay - one implementation, so a control cannot be draggable in
/// one and not the other.
class MovableControl extends StatelessWidget {
  const MovableControl({
    super.key,
    required this.area,
    required this.fraction,
    required this.editing,
    required this.label,
    required this.onMoved,
    required this.onMoveEnd,
    required this.child,
  });

  final Size area;
  final Offset2 fraction;
  final bool editing;
  final String label;
  final ValueChanged<Offset2> onMoved;
  final VoidCallback onMoveEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: fraction.dx * area.width,
      top: fraction.dy * area.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: editing
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails d) {
                  if (area.width == 0 || area.height == 0) return;
                  onMoved(fraction.shifted(
                    d.delta.dx / area.width,
                    d.delta.dy / area.height,
                  ));
                },
                onPanEnd: (_) => onMoveEnd(),
                child: _chrome(child),
              )
            : child,
      ),
    );
  }

  Widget _chrome(Widget inner) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.tealAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.open_with, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Deliberately NOT wrapped in AbsorbPointer. It was, and that is
          // what made the red delete badge on an added button do nothing:
          // absorbing swallows the badge's taps along with everything else.
          // The controls themselves go inert instead, each one knowing it is
          // being arranged, which leaves the badge live. Dragging still works
          // because the pan gesture is on the parent and a child's tap only
          // takes taps.
          inner,
        ],
      ),
    );
  }
}
