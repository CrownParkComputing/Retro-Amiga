/// The kinds of file the library scanner recognises.
///
/// Extension sets are carried over from the launcher this replaces, because
/// the core's config validation keys off exactly these.
///
/// Two properties are deliberately NOT true of this table, and the original's
/// tests fail on both:
///
///  * The sets overlap. `zip` is both a ROM archive and a floppy archive, so
///    no single extension maps to one category.
///  * [fromExtension] therefore resolves by declaration order, first match
///    wins. `bin` lands on roms, never cdImages.
///
/// Both are behaviour the shipping app depends on, so they are preserved
/// rather than tidied.
enum FileCategory {
  roms('roms', 'Kickstarts / ROMs', <String>{'rom', 'bin', 'kick', 'zip'}),
  floppies('floppies', 'Floppy Images',
      <String>{'adf', 'adz', 'dms', 'ipf', 'zip', 'gz'}),
  hardDrives('harddrives', 'Hard Drives', <String>{'hdf', 'hdi', 'vhd'}),
  cdImages('cd-images', 'CD / ISO Images', <String>{'iso', 'chd'}),
  whdloadGames('lha', 'WHDLoad Games', <String>{'lha', 'lzx', 'lzh'});

  const FileCategory(this.folder, this.displayName, this.extensions);

  final String folder;
  final String displayName;
  final Set<String> extensions;

  /// First category whose extension set contains [extension]. Order matters:
  /// see the note on this enum.
  static FileCategory? fromExtension(String extension) {
    final String lower = extension.toLowerCase();
    for (final FileCategory category in FileCategory.values) {
      if (category.extensions.contains(lower)) return category;
    }
    return null;
  }

  static FileCategory? fromPath(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    return fromExtension(path.substring(dot + 1));
  }
}
