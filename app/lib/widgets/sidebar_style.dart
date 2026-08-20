import 'sidebar.dart';
import '../theme/amiga_theme.dart';

/// The Amiga front end's rail palette. This adapter is the only per-app part
/// of the side nav -- widgets/sidebar.dart itself is identical in every
/// Retro-* app, so a fix there lands everywhere instead of once.
///
/// The values are this app's existing chrome, not Dosbox's: the rail reads as
/// part of Retro-Amiga, it is the LAYOUT that is shared.
const SidebarStyle amigaSidebarStyle = SidebarStyle(
  panelFill: AmigaColors.panel,
  panelStroke: AmigaColors.panelBorder,
  selectedFill: AmigaColors.cardHover,
  selectedStroke: AmigaColors.workbenchOrange,
  labelIdle: AmigaColors.textDim,
  labelSelected: AmigaColors.text,
  minWidth: AmigaMetrics.sidebarMin,
  // Tighter than the C64 rail: ten entries have to fit a Retroid's 480dp
  // without the middle group scrolling off under the pinned one.
  buttonHeight: 32,
  buttonTextSize: 13,
  buttonBottomMargin: 2,
  buttonSidePadding: 10,
  buttonVerticalPadding: 6,
  navPadding: 8,
  maxWidth: _maxWidth,
);

/// A quarter of the screen, capped -- the same rule the app's own
/// WorkbenchSidebar used before the shared rail replaced it.
///
/// The cap is 260, not AmigaMetrics.sidebarMax (190). 190 was chosen for a
/// rail whose labels were painted at the platform's default text scale; on the
/// Retroid, which runs at 1.35x, "Settings" needs more than that and the cap
/// was what clipped it to "Settin...". A quarter of the screen is still the
/// real limit on anything narrow.
const double _railCap = 260;

double _maxWidth(double screenWidth) {
  final quarter = screenWidth / 4;
  return quarter < _railCap ? quarter : _railCap;
}
