import 'package:flutter/material.dart';

import '../data/amiga_keys.dart';
import '../data/pad_layout.dart';
import '../data/pad_layout_store.dart';
import '../widgets/cd32_pad.dart';
import '../widgets/movable_control.dart';
import '../widgets/pad_key_button.dart';
import '../widgets/wobble_joystick.dart';

/// Where the on-screen pad is arranged.
///
/// In the launcher rather than over a running game. Arranging controls while
/// a game is playing means the game is playing underneath you - taking your
/// touches, running its clock - and every fiddle costs a life. Here there is
/// nothing to lose, and the layout is ready before the game starts.
class PadDesignerScreen extends StatefulWidget {
  const PadDesignerScreen({super.key});

  @override
  State<PadDesignerScreen> createState() => _PadDesignerScreenState();
}

class _PadDesignerScreenState extends State<PadDesignerScreen> {
  PadLayout _layout = PadLayout.defaults;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final PadLayout layout = await PadLayoutStore.load();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _loaded = true;
    });
  }

  Future<void> _save() => PadLayoutStore.save(_layout);

  void _move(_Control control, Offset2 to) {
    setState(() {
      _layout = switch (control) {
        _Control.stick => _layout.copyWith(stick: to),
        _Control.buttons => _layout.copyWith(buttons: to),
        _Control.transport => _layout.copyWith(transport: to),
      };
    });
  }

  Future<void> _addButton() async {
    final PadButton? button = await showPadButtonPicker(context);
    if (button == null) return;
    // The same key twice would stack two identical buttons on top of each
    // other, which looks like the tap did nothing.
    if (_layout.customButtons.any((PadButton b) => b.id == button.id)) return;
    setState(() {
      _layout = _layout.copyWith(
        customButtons: <PadButton>[..._layout.customButtons, button],
      );
    });
    await _save();
  }

  Future<void> _removeButton(PadButton button) async {
    setState(() {
      _layout = _layout.copyWith(
        customButtons: _layout.customButtons
            .where((PadButton b) => b.id != button.id)
            .toList(),
      );
    });
    await _save();
  }

  Future<void> _reset() async {
    setState(() => _layout = PadLayout.defaults.copyWith(style: _layout.style));
    await _save();
  }

  Future<void> _setStyle(PadStyle style) async {
    if (_layout.style == style) return;
    setState(() => _layout = _layout.copyWith(style: style));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('On-screen pad'),
        actions: <Widget>[
          TextButton(onPressed: _reset, child: const Text('Reset')),
          TextButton(onPressed: _addButton, child: const Text('Add button')),
          TextButton(
            onPressed: () async {
              await _save();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                _StyleRow(style: _layout.style, onChanged: _setStyle),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Drag the controls where you want them. This is the '
                    'screen shape a game gets, so what you see is where they '
                    'will be.',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _Stage(
                      layout: _layout,
                      onMoved: _move,
                      onCommit: _save,
                      onRemove: _removeButton,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The play area, drawn to the shape a game gets so the fractions mean what
/// they will mean in the game. Anything else and a control dragged to the
/// corner here would not be in the corner there.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.layout,
    required this.onMoved,
    required this.onCommit,
    required this.onRemove,
  });

  final PadLayout layout;
  final void Function(_Control, Offset2) onMoved;
  final VoidCallback onCommit;
  final ValueChanged<PadButton> onRemove;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF101014),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size area = constraints.biggest;
            return Stack(
              children: <Widget>[
                const Center(
                  child: Text(
                    'the game goes here',
                    style: TextStyle(color: Colors.white12, fontSize: 20),
                  ),
                ),
                MovableControl(
                  area: area,
                  fraction: layout.stick,
                  editing: true,
                  label: 'Joystick',
                  onMoved: (Offset2 to) => onMoved(_Control.stick, to),
                  onMoveEnd: onCommit,
                  child: const IgnorePointer(
                    child: WobbleJoystick(size: 110, onDirections: _ignore),
                  ),
                ),
                MovableControl(
                  area: area,
                  fraction: layout.buttons,
                  editing: true,
                  label: 'Buttons',
                  onMoved: (Offset2 to) => onMoved(_Control.buttons, to),
                  onMoveEnd: onCommit,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (final PadButton button in layout.customButtons) ...[
                        PadKeyButton(
                          button: button,
                          enabled: false,
                          size: 40,
                          onKey: _ignoreKey,
                          onDirection: _ignoreDirection,
                          onRemove: () => onRemove(button),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (layout.style == PadStyle.cd32)
                        const IgnorePointer(
                          child: Cd32Pad(enabled: false, onButton: _ignoreButton),
                        )
                      else ...<Widget>[
                        const _Fire(label: '2', colour: Color(0xFF3050DC)),
                        const SizedBox(height: 8),
                        const _Fire(label: '1', colour: Color(0xFFDC3232)),
                      ],
                    ],
                  ),
                ),
                if (layout.style == PadStyle.cd32)
                  MovableControl(
                    area: area,
                    fraction: layout.transport,
                    editing: true,
                    label: 'CD keys',
                    onMoved: (Offset2 to) => onMoved(_Control.transport, to),
                    onMoveEnd: onCommit,
                    child: const IgnorePointer(
                      child: Cd32Transport(
                        enabled: false,
                        onButton: _ignoreButton,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

void _ignore(bool up, bool down, bool left, bool right) {}
void _ignoreKey(int code, bool pressed) {}
void _ignoreDirection(PadDirection direction, bool down) {}
void _ignoreButton(int button, bool pressed) {}

enum _Control { stick, buttons, transport }

class _StyleRow extends StatelessWidget {
  const _StyleRow({required this.style, required this.onChanged});

  final PadStyle style;
  final ValueChanged<PadStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: <Widget>[
          const Text('Controller', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('Joystick'),
            selected: style == PadStyle.joystick,
            onSelected: (_) => onChanged(PadStyle.joystick),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('CD32 pad'),
            selected: style == PadStyle.cd32,
            onSelected: (_) => onChanged(PadStyle.cd32),
          ),
        ],
      ),
    );
  }
}

class _Fire extends StatelessWidget {
  const _Fire({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.45),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Asks what a new button should do.
///
/// Directions come first because they are four options against sixty, and
/// because "UP to jump" is the commonest reason to add a button at all.
Future<PadButton?> showPadButtonPicker(BuildContext context) {
  return showDialog<PadButton>(
    context: context,
    builder: (BuildContext context) => Dialog(
      backgroundColor: const Color(0xFF141A1F),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Choose what the new button does',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  const _PickerHeading('JOYSTICK DIRECTION'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final PadDirection direction in PadDirection.values)
                        _PickerChip(
                          label: direction.label,
                          onTap: () => Navigator.of(context)
                              .pop(PadButton.direction(direction)),
                        ),
                    ],
                  ),
                  for (final MapEntry<String, List<AmigaKey>> group
                      in AmigaKeys.groups.entries) ...<Widget>[
                    _PickerHeading(group.key.toUpperCase()),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final AmigaKey key in group.value)
                          _PickerChip(
                            label: key.label,
                            onTap: () =>
                                Navigator.of(context).pop(PadButton.key(key)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 8),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickerHeading extends StatelessWidget {
  const _PickerHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF3D4652)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: Text(label),
    );
  }
}
