import 'package:flutter/material.dart';

/// The palette, in one place.
///
/// Two families sit side by side deliberately. The chrome is modern dark -
/// near-black root, floating panels - because that is what reads well on a
/// handheld in a dark room. The accents are the Amiga's own: Workbench 1.3
/// blue and its orange, and the boot tick's greens and reds. Using period
/// colours for the whole surface would look like a museum piece rather than
/// something you want to browse.
class AmigaColors {
  const AmigaColors._();

  /// Behind everything, including the backdrop demo.
  static const Color root = Color(0xFF050607);

  /// The floating panels. Translucent so the backdrop shows through.
  static const Color panel = Color(0xCC0B0D10);
  static const Color panelBorder = Color(0x1AFFFFFF);

  /// Cards inside a panel.
  static const Color card = Color(0xFF14171C);
  static const Color cardHover = Color(0xFF1D222A);

  /// Workbench 1.3's blue and orange, straight off the boot screen.
  static const Color workbenchBlue = Color(0xFF0055AA);
  static const Color workbenchOrange = Color(0xFFFF8800);

  /// The tick's colours, shared with AmigaLogo.
  static const Color tickRed = Color(0xFFFE3814);
  static const Color tickGreen = Color(0xFF17CE76);

  /// Selection and focus.
  static const Color accent = workbenchOrange;

  static const Color text = Color(0xFFF2F4F7);
  static const Color textDim = Color(0xFF9AA3AF);
}

/// Sizes shared between the shell and the panels, so a card in the library and
/// a card on the shelf are the same card.
class AmigaMetrics {
  const AmigaMetrics._();

  static const double gutter = 12;

  /// The nav rail. Measured from the widest label at build time and clamped
  /// into this range, so a long language does not eat the content panel.
  static const double sidebarMin = 118;
  static const double sidebarMax = 190;

  /// Media cards: 3:4-ish, which suits box art and disk labels alike.
  static const double cardWidth = 120;
  static const double cardHeight = 178;

  /// Grid cell including its gap; the column count divides by this.
  static const double cardCell = 126;

  static const double panelRadius = 12;
}
