/// A key on the Amiga keyboard, as the hardware numbers it.
///
/// The code is a raw Amiga key code - the value the keyboard itself puts on
/// the wire - not an SDL scancode and not a Flutter LogicalKeyboardKey. That
/// is what `uae4arm_host_send_key` takes, and it is the only numbering that
/// means the same thing on every host we run on. The values are the AK_
/// constants from src/include/keyboard.h.
class AmigaKey {
  const AmigaKey(this.label, this.code);

  final String label;
  final int code;

  String get id => 'ak:$code';
}

/// The keys worth putting on a button, grouped the way you would look for one.
///
/// Not the whole matrix: this list exists to be browsed with a thumb while a
/// game is running. What games actually ask for is a fire-adjacent key -
/// SPACE to start, RETURN to select, ESC to quit, F1 to pick a level - so
/// those come first, and the letters and digits follow for the games that
/// want a specific one.
class AmigaKeys {
  const AmigaKeys._();

  static const AmigaKey space = AmigaKey('SPACE', 0x40);
  static const AmigaKey enter = AmigaKey('RETURN', 0x44);
  static const AmigaKey escape = AmigaKey('ESC', 0x45);

  static const Map<String, List<AmigaKey>> groups = <String, List<AmigaKey>>{
    'Common': <AmigaKey>[
      space,
      enter,
      escape,
      AmigaKey('CTRL', 0x63),
      AmigaKey('L-SHIFT', 0x60),
      AmigaKey('L-ALT', 0x64),
      AmigaKey('HELP', 0x5F),
      AmigaKey('DEL', 0x46),
      AmigaKey('TAB', 0x42),
    ],
    'Function': <AmigaKey>[
      AmigaKey('F1', 0x50),
      AmigaKey('F2', 0x51),
      AmigaKey('F3', 0x52),
      AmigaKey('F4', 0x53),
      AmigaKey('F5', 0x54),
      AmigaKey('F6', 0x55),
      AmigaKey('F7', 0x56),
      AmigaKey('F8', 0x57),
      AmigaKey('F9', 0x58),
      AmigaKey('F10', 0x59),
    ],
    'Cursor': <AmigaKey>[
      AmigaKey('UP', 0x4C),
      AmigaKey('DOWN', 0x4D),
      AmigaKey('LEFT', 0x4F),
      AmigaKey('RIGHT', 0x4E),
    ],
    'Numbers': <AmigaKey>[
      AmigaKey('1', 0x01),
      AmigaKey('2', 0x02),
      AmigaKey('3', 0x03),
      AmigaKey('4', 0x04),
      AmigaKey('5', 0x05),
      AmigaKey('6', 0x06),
      AmigaKey('7', 0x07),
      AmigaKey('8', 0x08),
      AmigaKey('9', 0x09),
      AmigaKey('0', 0x0A),
    ],
    'Letters': <AmigaKey>[
      AmigaKey('A', 0x20),
      AmigaKey('B', 0x35),
      AmigaKey('C', 0x33),
      AmigaKey('D', 0x22),
      AmigaKey('E', 0x12),
      AmigaKey('F', 0x23),
      AmigaKey('G', 0x24),
      AmigaKey('H', 0x25),
      AmigaKey('I', 0x17),
      AmigaKey('J', 0x26),
      AmigaKey('K', 0x27),
      AmigaKey('L', 0x28),
      AmigaKey('M', 0x37),
      AmigaKey('N', 0x36),
      AmigaKey('O', 0x18),
      AmigaKey('P', 0x19),
      AmigaKey('Q', 0x10),
      AmigaKey('R', 0x13),
      AmigaKey('S', 0x21),
      AmigaKey('T', 0x14),
      AmigaKey('U', 0x16),
      AmigaKey('V', 0x34),
      AmigaKey('W', 0x11),
      AmigaKey('X', 0x32),
      AmigaKey('Y', 0x15),
      AmigaKey('Z', 0x31),
    ],
  };

  /// The key with [code], or null. Used when reading back a saved button: a
  /// code we no longer offer is better dropped than drawn with no label.
  static AmigaKey? byCode(int code) {
    for (final List<AmigaKey> group in groups.values) {
      for (final AmigaKey key in group) {
        if (key.code == code) return key;
      }
    }
    return null;
  }
}
