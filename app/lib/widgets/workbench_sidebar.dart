import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/amiga_theme.dart';

/// The panels the workbench can show, in rail order.
///
/// Setups first, and first on opening, because a setup is the thing you can
/// actually play: it names the machine, the memory and the Kickstart as well
/// as the disk. The file list sits lower down and is called Files, because
/// that is what it is - a list of what is on the device, and a place to make a
/// setup from one of them.
enum WorkbenchSection {
  setups('Setups', Icons.tune),
  resume('Resume', Icons.play_circle_outline),
  music('Music', Icons.music_note_outlined),
  history('History', Icons.history_edu_outlined),
  files('Files', Icons.folder_open_outlined),
  settings('Settings', Icons.settings_outlined),
  logs('Logs', Icons.article_outlined),
  about('About', Icons.info_outline);

  const WorkbenchSection(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// The nav rail down the left of the workbench.
///
/// Its width is measured from the widest label rather than fixed, so a longer
/// word cannot clip, then clamped: unclamped it would eat the content panel on
/// a phone.
class WorkbenchSidebar extends StatelessWidget {
  const WorkbenchSidebar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.available,
  });

  final WorkbenchSection selected;
  final ValueChanged<WorkbenchSection> onSelected;

  /// Width the rail is allowed to take, before clamping.
  final double available;

  /// Widest label plus the fixed icon column, clamped so the rail can never
  /// take more than a quarter of a narrow screen.
  ///
  /// [scaler] must be the one the labels will actually be painted with. It is
  /// not decoration: measuring at 1.0 and rendering at the iPad's larger
  /// default is exactly what turned "Settings" into "Settin..." here.
  static double widthFor(double available, TextScaler scaler) {
    double widest = 0;
    for (final WorkbenchSection section in WorkbenchSection.values) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: section.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, painter.width);
    }
    // icon column + gap + label + padding, and a couple of points of slack so
    // a font that rounds up a hair does not clip the last letter.
    final double natural = 22 + 10 + widest + 28 + 4;
    final double ceiling = math.max(
      AmigaMetrics.sidebarMin,
      math.min(AmigaMetrics.sidebarMax, available * 0.25),
    );
    return natural.clamp(AmigaMetrics.sidebarMin, ceiling);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widthFor(available, MediaQuery.textScalerOf(context)),
      decoration: BoxDecoration(
        color: AmigaColors.panel,
        borderRadius: BorderRadius.circular(AmigaMetrics.panelRadius),
        border: Border.all(color: AmigaColors.panelBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final WorkbenchSection section in WorkbenchSection.values)
            _RailButton(
              section: section,
              selected: section == selected,
              onTap: () => onSelected(section),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final WorkbenchSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AmigaColors.workbenchBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: <Widget>[
                // Fixed icon column so every label starts at the same x.
                SizedBox(
                  width: 22,
                  child: Icon(
                    section.icon,
                    size: 18,
                    color: selected ? Colors.white : AmigaColors.textDim,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AmigaColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
