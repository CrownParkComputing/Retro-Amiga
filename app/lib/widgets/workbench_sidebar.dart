/// The panels the workbench can show, in rail order.
///
/// This file used to hold the rail widget too. It is gone: the rail is now
/// the shared widgets/sidebar.dart, identical in every Retro-* front end, and
/// what stays here is the one thing that is genuinely this app's -- which
/// panels exist and what order they come in.
///
/// Setups first, and first on opening, because a setup is the thing you can
/// actually play: it names the machine, the memory and the Kickstart as well
/// as the disk. The file list sits lower down and is called Files, because
/// that is what it is - a list of what is on the device, and a place to make a
/// setup from one of them.
/// Declaration order IS rail order, and [group] is the band it sits in,
/// matching Retro-C64 and Retro-Dosbox:
///
///   0  where you go        Games, Resume
///   2  how it is set up    Files, A/V, Input, Settings
///   4  everything else     Music, History, Compliance, About  (pinned)
///
/// The numbers are spaced rather than consecutive so a band can be inserted
/// between two without renumbering the rest. Only the ORDER of the values
/// matters to the rail, and that the pinned band is last.
///
/// Eight flat entries read as a list to be searched; three bands read as a
/// place to look. The bottom band is pinned so About stays where About always
/// is rather than drifting with the length of the band above it.
enum WorkbenchSection {
  // The C64 rail's shape, so the family reads as one: what you play at the
  // top, how the machine is set up in the middle, the extras at the bottom.
  setups('Games', '🎮', 0),
  resume('Resume', '🚀', 0),
  // Everything ready to run, in one place: AGS, AmigaVision, PiMiga, a
  // WHDLoad pack, a folder someone copied off a real Amiga. One entry rather
  // than one per system -- a rail that grows a row every time a card is
  // plugged in stops being a rail.
  collections('Collections', '🗂️', 2),
  files('Files', '📂', 2),
  // Picture and sound together. They were two entries, each holding one
  // control and each ending with the same "set it per config" card; the rail
  // is shorter for merging them and neither page lost anything.
  av('A/V', '📺', 2),
  input('Input', '🕹️', 2),
  settings('Settings', '⚙️', 2),
  music('Music', '🎵', 4),
  history('History', '📜', 4),
  // Its own destination, and named so a store reviewer recognises it on
  // sight rather than having to be told where to look.
  compliance('Compliance', '✅', 4),
  about('About', 'ℹ️', 4);

  const WorkbenchSection(this.title, this.icon, this.group);

  final String title;
  final String icon;
  final int group;
}
