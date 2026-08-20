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
///   0  where you go        Files, Configs, Resume
///   1  how it is set up    Settings
///   2  everything else     Music, History, Logs, About  (pinned to the bottom)
///
/// Eight flat entries read as a list to be searched; three bands read as a
/// place to look. The bottom band is pinned so About stays where About always
/// is rather than drifting with the length of the band above it.
enum WorkbenchSection {
  // The C64 rail's shape, so the family reads as one: what you play at the
  // top, how the machine is set up in the middle, the extras at the bottom.
  setups('Configs', '🎮', 0),
  resume('Resume', '🚀', 0),
  files('Files', '📂', 1),
  video('Video', '📺', 1),
  input('Input', '🕹️', 1),
  audio('Audio', '🔊', 1),
  settings('Settings', '⚙️', 1),
  music('Music', '🎵', 2),
  history('History', '📜', 2),
  about('About', 'ℹ️', 2);

  const WorkbenchSection(this.title, this.icon, this.group);

  final String title;
  final String icon;
  final int group;
}
