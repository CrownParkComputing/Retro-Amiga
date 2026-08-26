import 'package:flutter/material.dart';

/// One key: a raw Amiga key code (the AK_ numbering uae4arm_host_send_key
/// takes), or an action (CLOSE).
class _KeySpec {
  const _KeySpec(this.label, this.code, {this.weight = 1.0, this.action});

  final String label;
  final int? code;
  final double weight;
  final VoidCallback? action;
}

/// The Amiga keyboard, the C64 overlay's way: a full set of rows along the
/// bottom of the pane, each key driving the core directly while it is held.
///
/// Shift/Ctrl/Alt/Amiga LATCH rather than needing a held finger: tap arms
/// the modifier for one keypress, tap again locks it, again releases -- the
/// model the family's DOSBox and ST keyboards use. Shift-letter and
/// Ctrl-Amiga-Amiga stop being two- and three-finger jobs.
class AmigaKeyboardOverlay extends StatefulWidget {
  const AmigaKeyboardOverlay({
    super.key,
    required this.onKey,
    required this.onClose,
  });

  /// (raw Amiga key code, pressed).
  final void Function(int code, bool pressed) onKey;
  final VoidCallback onClose;

  @override
  State<AmigaKeyboardOverlay> createState() => _AmigaKeyboardOverlayState();
}

class _AmigaKeyboardOverlayState extends State<AmigaKeyboardOverlay> {
  /// Left/right Shift, Ctrl, left/right Alt, left/right Amiga.
  static const Set<int> _modifierCodes = <int>{
    0x60, 0x61, 0x63, 0x64, 0x65, 0x66, 0x67,
  };

  final Set<int> _armed = <int>{};
  final Set<int> _locked = <int>{};

  void _tapModifier(int code) {
    setState(() {
      if (_locked.contains(code)) {
        _locked.remove(code);
        widget.onKey(code, false);
      } else if (_armed.contains(code)) {
        _armed.remove(code);
        _locked.add(code);
        // Already down from arming; stays down.
      } else {
        _armed.add(code);
        widget.onKey(code, true);
      }
    });
  }

  /// A one-shot modifier covers exactly one ordinary keypress.
  void _releaseArmed() {
    if (_armed.isEmpty) return;
    for (final int code in _armed) {
      widget.onKey(code, false);
    }
    setState(_armed.clear);
  }

  @override
  void dispose() {
    // A modifier latched down when the keyboard closes must not stay held
    // in the machine forever.
    for (final int code in {..._armed, ..._locked}) {
      widget.onKey(code, false);
    }
    super.dispose();
  }

  void Function(int code, bool pressed) get onKey => widget.onKey;
  VoidCallback get onClose => widget.onClose;

  List<List<_KeySpec>> get _rows => <List<_KeySpec>>[
        <_KeySpec>[
          const _KeySpec('ESC', 0x45),
          const _KeySpec('F1', 0x50), const _KeySpec('F2', 0x51),
          const _KeySpec('F3', 0x52), const _KeySpec('F4', 0x53),
          const _KeySpec('F5', 0x54), const _KeySpec('F6', 0x55),
          const _KeySpec('F7', 0x56), const _KeySpec('F8', 0x57),
          const _KeySpec('F9', 0x58), const _KeySpec('F10', 0x59),
          const _KeySpec('HELP', 0x5F, weight: 1.3),
          const _KeySpec('DEL', 0x46, weight: 1.3),
          _KeySpec('CLOSE', null, weight: 1.6, action: onClose),
        ],
        const <_KeySpec>[
          _KeySpec('`', 0x00), _KeySpec('1', 0x01), _KeySpec('2', 0x02),
          _KeySpec('3', 0x03), _KeySpec('4', 0x04), _KeySpec('5', 0x05),
          _KeySpec('6', 0x06), _KeySpec('7', 0x07), _KeySpec('8', 0x08),
          _KeySpec('9', 0x09), _KeySpec('0', 0x0A), _KeySpec('-', 0x0B),
          _KeySpec('=', 0x0C), _KeySpec('\\', 0x0D),
          _KeySpec('BS', 0x41, weight: 1.5),
        ],
        const <_KeySpec>[
          _KeySpec('TAB', 0x42, weight: 1.5), _KeySpec('Q', 0x10),
          _KeySpec('W', 0x11), _KeySpec('E', 0x12), _KeySpec('R', 0x13),
          _KeySpec('T', 0x14), _KeySpec('Y', 0x15), _KeySpec('U', 0x16),
          _KeySpec('I', 0x17), _KeySpec('O', 0x18), _KeySpec('P', 0x19),
          _KeySpec('[', 0x1A), _KeySpec(']', 0x1B),
          _KeySpec('RETURN', 0x44, weight: 1.9),
        ],
        const <_KeySpec>[
          _KeySpec('CTRL', 0x63, weight: 1.3), _KeySpec('CAPS', 0x62, weight: 1.2),
          _KeySpec('A', 0x20), _KeySpec('S', 0x21), _KeySpec('D', 0x22),
          _KeySpec('F', 0x23), _KeySpec('G', 0x24), _KeySpec('H', 0x25),
          _KeySpec('J', 0x26), _KeySpec('K', 0x27), _KeySpec('L', 0x28),
          _KeySpec(';', 0x29), _KeySpec('\'', 0x2A),
          _KeySpec('UP', 0x4C, weight: 1.4),
        ],
        const <_KeySpec>[
          _KeySpec('SHIFT', 0x60, weight: 1.8), _KeySpec('Z', 0x31),
          _KeySpec('X', 0x32), _KeySpec('C', 0x33), _KeySpec('V', 0x34),
          _KeySpec('B', 0x35), _KeySpec('N', 0x36), _KeySpec('M', 0x37),
          _KeySpec(',', 0x38), _KeySpec('.', 0x39), _KeySpec('/', 0x3A),
          _KeySpec('SHIFT', 0x61, weight: 1.4),
          _KeySpec('LEFT', 0x4F), _KeySpec('DOWN', 0x4D), _KeySpec('RIGHT', 0x4E),
        ],
        const <_KeySpec>[
          _KeySpec('ALT', 0x64, weight: 1.3), _KeySpec('A', 0x66, weight: 1.3),
          _KeySpec('SPACE', 0x40, weight: 7),
          _KeySpec('A', 0x67, weight: 1.3), _KeySpec('ALT', 0x65, weight: 1.3),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xEE0B0D10),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final List<_KeySpec> row in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: <Widget>[
                  for (final _KeySpec spec in row)
                    Expanded(
                      flex: (spec.weight * 20).round(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: spec.code != null &&
                                _modifierCodes.contains(spec.code)
                            ? _ModKey(
                                spec: spec,
                                armed: _armed.contains(spec.code),
                                locked: _locked.contains(spec.code),
                                onTap: () => _tapModifier(spec.code!),
                              )
                            : _Key(
                                spec: spec,
                                onKey: onKey,
                                onKeyUp: _releaseArmed,
                              ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.spec, required this.onKey, this.onKeyUp});

  final _KeySpec spec;
  final void Function(int code, bool pressed) onKey;

  /// Fired after an ordinary key releases, so armed one-shot modifiers can
  /// let go with it.
  final VoidCallback? onKeyUp;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    final int? code = widget.spec.code;
    if (code != null) {
      widget.onKey(code, pressed);
      if (!pressed) widget.onKeyUp?.call();
    }
  }

  @override
  void dispose() {
    if (_pressed && widget.spec.code != null) widget.onKey(widget.spec.code!, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _KeySpec spec = widget.spec;
    final Widget key = Container(
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pressed ? const Color(0xFFFF8A00) : const Color(0xFF22272E),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF3D4652)),
      ),
      child: Text(
        spec.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: spec.label.length > 4 ? 9 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (spec.action != null) {
      return GestureDetector(onTap: spec.action, child: key);
    }
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: key,
    );
  }
}

/// A latching modifier key: idle, armed (accent border, one keypress) or
/// locked (accent fill, stays until tapped off).
class _ModKey extends StatelessWidget {
  const _ModKey({
    required this.spec,
    required this.armed,
    required this.locked,
    required this.onTap,
  });

  final _KeySpec spec;
  final bool armed;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: locked ? const Color(0xFFFF8A00) : const Color(0xFF22272E),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: armed ? const Color(0xFFFF8A00) : const Color(0xFF3D4652),
            width: armed ? 2 : 1,
          ),
        ),
        child: Text(
          spec.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: locked ? Colors.black : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
