import 'dart:convert';

import 'amiga_keys.dart';

/// A joystick direction a button can be bound to.
///
/// Its own enum rather than the pad API's bit numbers: this gets written to
/// disk, so it needs a name that stays put even if the native constants move.
enum PadDirection {
  up('UP'),
  down('DOWN'),
  left('LEFT'),
  right('RIGHT');

  const PadDirection(this.label);

  final String label;

  static PadDirection? byName(String name) {
    for (final PadDirection d in PadDirection.values) {
      if (d.name == name) return d;
    }
    return null;
  }
}

/// An extra on-screen button the player added, bound to an Amiga key or to a
/// joystick direction.
///
/// Both kinds, because games ask for both. A key covers SPACE to start and
/// ESC to quit; a direction covers the games where up is jump, and reaching
/// back to the stick mid-run is worse than a button under your thumb.
///
/// The stick stays the stick and fire stays fire - these are always extra,
/// never a remap, so nothing a player adds can take away a control they had.
class PadButton {
  const PadButton.key(AmigaKey this.key) : direction = null;
  const PadButton.direction(PadDirection this.direction) : key = null;

  final AmigaKey? key;
  final PadDirection? direction;

  bool get isDirection => direction != null;

  String get label => key?.label ?? direction!.label;

  String get id => key != null ? key!.id : 'dir:${direction!.name}';

  Map<String, Object?> toJson() => key != null
      ? <String, Object?>{'key': key!.code, 'label': key!.label}
      : <String, Object?>{'direction': direction!.name};

  static PadButton? fromJson(Map<String, Object?> json) {
    final Object? direction = json['direction'];
    if (direction is String) {
      final PadDirection? parsed = PadDirection.byName(direction);
      return parsed == null ? null : PadButton.direction(parsed);
    }
    final Object? code = json['key'];
    if (code is! int) return null;
    // The saved label wins over the catalogue's, so a button keeps the name
    // it was added with even if we rename a key later.
    final AmigaKey? known = AmigaKeys.byCode(code);
    final String label = json['label'] as String? ?? known?.label ?? '?';
    return PadButton.key(AmigaKey(label, code));
  }
}

/// Which controller is drawn.
///
/// The CD32 pad is a different device to the core, not a skin: it registers as
/// a seven-button pad and port 1 has to be told it is one, which is why this
/// is part of the layout rather than a colour scheme.
enum PadStyle {
  /// Stick and two fire buttons - the Amiga's own joystick.
  joystick,

  /// The CD32 joypad: red, blue, green, yellow, and the three transport keys.
  cd32;

  static PadStyle byName(String? name) {
    for (final PadStyle style in PadStyle.values) {
      if (style.name == name) return style;
    }
    return PadStyle.joystick;
  }
}

/// Where the on-screen controls sit and what extra buttons there are.
///
/// Positions are fractions of the play area, not pixels: the controls have to
/// land in the same place on a phone held one way, the same phone held the
/// other way, and a tablet. A pixel offset saved on one of those is wrong on
/// the other two.
class PadLayout {
  const PadLayout({
    this.stick = const Offset2(0.13, 0.74),
    this.buttons = const Offset2(0.89, 0.72),
    this.transport = const Offset2(0.78, 0.12),
    this.customButtons = const <PadButton>[],
    this.style = PadStyle.joystick,
  });

  /// Defaults chosen to match where the controls have always been drawn -
  /// stick bottom left, fire bottom right - so nobody who never opens the
  /// editor sees anything change.
  static const PadLayout defaults = PadLayout();

  final Offset2 stick;
  final Offset2 buttons;

  /// The CD32 transport keys - play, rewind, forward. Placed on their own,
  /// away from the four coloured buttons, because they are not part of
  /// playing: hitting one by accident mid-game is a skipped track, so they
  /// want to be somewhere your thumb is not.
  final Offset2 transport;
  final List<PadButton> customButtons;
  final PadStyle style;

  PadLayout copyWith({
    Offset2? stick,
    Offset2? buttons,
    Offset2? transport,
    List<PadButton>? customButtons,
    PadStyle? style,
  }) => PadLayout(
    stick: stick ?? this.stick,
    buttons: buttons ?? this.buttons,
    transport: transport ?? this.transport,
    customButtons: customButtons ?? this.customButtons,
    style: style ?? this.style,
  );

  String encode() => jsonEncode(<String, Object?>{
    'stick': stick.toJson(),
    'buttons': buttons.toJson(),
    'transport': transport.toJson(),
    'custom': customButtons.map((PadButton b) => b.toJson()).toList(),
    'style': style.name,
  });

  /// Anything unreadable falls back to the defaults rather than throwing: a
  /// corrupt layout file must not be the reason a game has no controls.
  static PadLayout decode(
    String? text, {
    PadStyle fallbackStyle = PadStyle.joystick,
  }) {
    // No layout yet means a machine we have not been asked about, so the
    // caller's guess stands: a CD32 game gets the CD32 pad without anyone
    // having to go and choose it.
    if (text == null || text.isEmpty) {
      return defaults.copyWith(style: fallbackStyle);
    }
    try {
      final Object? raw = jsonDecode(text);
      if (raw is! Map<String, Object?>) {
        return defaults.copyWith(style: fallbackStyle);
      }

      final List<PadButton> custom = <PadButton>[];
      final Object? entries = raw['custom'];
      if (entries is List<Object?>) {
        for (final Object? entry in entries) {
          if (entry is! Map<String, Object?>) continue;
          final PadButton? button = PadButton.fromJson(entry);
          if (button != null) custom.add(button);
        }
      }

      return PadLayout(
        stick: Offset2.fromJson(raw['stick']) ?? defaults.stick,
        buttons: Offset2.fromJson(raw['buttons']) ?? defaults.buttons,
        transport: Offset2.fromJson(raw['transport']) ?? defaults.transport,
        customButtons: custom,
        style: raw['style'] == null
            ? fallbackStyle
            : PadStyle.byName(raw['style'] as String?),
      );
    } on FormatException {
      return defaults.copyWith(style: fallbackStyle);
    }
  }
}

/// A pair of fractions. Not dart:ui's Offset, so this file - and the tests
/// over it - stay free of Flutter.
class Offset2 {
  const Offset2(this.dx, this.dy);

  final double dx;
  final double dy;

  /// Keeps a control from being dragged so far that its centre leaves the
  /// screen and it can never be grabbed again.
  static const double minimum = 0.06;
  static const double maximum = 0.94;

  Offset2 clamped() => Offset2(
    dx.clamp(minimum, maximum).toDouble(),
    dy.clamp(minimum, maximum).toDouble(),
  );

  Offset2 shifted(double x, double y) => Offset2(dx + x, dy + y).clamped();

  List<double> toJson() => <double>[dx, dy];

  static Offset2? fromJson(Object? raw) {
    if (raw is! List<Object?> || raw.length < 2) return null;
    final Object? x = raw[0];
    final Object? y = raw[1];
    if (x is! num || y is! num) return null;
    return Offset2(x.toDouble(), y.toDouble()).clamped();
  }
}
