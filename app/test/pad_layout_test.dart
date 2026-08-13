import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_keys.dart';
import 'package:uae4arm2026/data/pad_layout.dart';

void main() {
  group('PadLayout', () {
    test('survives a round trip through JSON', () {
      const PadLayout layout = PadLayout(
        stick: Offset2(0.2, 0.8),
        buttons: Offset2(0.7, 0.3),
        customButtons: <PadButton>[
          PadButton.key(AmigaKeys.space),
          PadButton.direction(PadDirection.up),
        ],
      );

      final PadLayout back = PadLayout.decode(layout.encode());

      expect(back.stick.dx, closeTo(0.2, 1e-9));
      expect(back.stick.dy, closeTo(0.8, 1e-9));
      expect(back.buttons.dx, closeTo(0.7, 1e-9));
      expect(back.customButtons.length, 2);
      // The key must come back as the same raw Amiga code, not as a label
      // that happens to read the same: the code is what the core is sent.
      expect(back.customButtons[0].key?.code, 0x40);
      expect(back.customButtons[1].direction, PadDirection.up);
    });

    test('falls back to the defaults rather than throwing on rubbish', () {
      expect(PadLayout.decode('not json').stick.dx, PadLayout.defaults.stick.dx);
      expect(PadLayout.decode('').customButtons, isEmpty);
      expect(PadLayout.decode(null).buttons.dy, PadLayout.defaults.buttons.dy);
      // A layout whose entries are the wrong shape keeps whatever it can.
      final PadLayout partial =
          PadLayout.decode('{"stick":[0.4,0.4],"custom":[{"key":"nope"}]}');
      expect(partial.stick.dx, closeTo(0.4, 1e-9));
      expect(partial.customButtons, isEmpty);
    });

    test('a control cannot be dragged off the screen', () {
      // Dragging hard to the corner has to leave the control grabbable, or
      // the only way back is reinstalling.
      final Offset2 far = const Offset2(0.5, 0.5).shifted(-5, 5);
      expect(far.dx, Offset2.minimum);
      expect(far.dy, Offset2.maximum);
      expect(Offset2.fromJson(<double>[-3, 9])!.dx, Offset2.minimum);
    });
  });

  group('AmigaKeys', () {
    test('codes are the raw Amiga ones from keyboard.h', () {
      expect(AmigaKeys.space.code, 0x40);
      expect(AmigaKeys.enter.code, 0x44);
      expect(AmigaKeys.escape.code, 0x45);
      expect(AmigaKeys.byCode(0x50)?.label, 'F1');
      expect(AmigaKeys.byCode(0x20)?.label, 'A');
      expect(AmigaKeys.byCode(0x99), isNull);
    });
  });
}
