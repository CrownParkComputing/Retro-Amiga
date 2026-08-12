/// The kinds of file the library scanner recognises.
///
/// The core is the authority here, not the launcher this replaces. That
/// launcher accepted a much narrower set - CD images were only iso and chd,
/// so a .cue was silently dropped even though the core has a parser for it -
/// and files it did not recognise simply never appeared in the picker.
///
/// Sources, all in the emulator core:
///   floppies   zfile.cpp diskimages[], plus the raw types disk.cpp accepts
///   cdImages   blkdev_cdimage.cpp parsers, plus its raw fallback which
///              mounts any image whose size divides by 2048 or 2352
///   hardDrives zfile.cpp hdf/hdz/vhd handling
///   archives   zfile.cpp plugins_7z[] and the archive extension list
///
/// Two properties are deliberately NOT true of this table:
///
///  * The sets overlap. Archive extensions in particular are shared: a zip
///    may hold a ROM, a floppy or a hard drive image, and only its contents
///    say which.
///  * [fromExtension] therefore resolves by declaration order, first match
///    wins.
///
/// Both were true of the original too, where they broke two of its tests.
/// Preserved rather than tidied, because the categories are a browsing aid;
/// the core decides what a file really is when it opens it.
enum FileCategory {
  roms('roms', 'Kickstarts / ROMs', <String>{'rom', 'kick', 'key', 'bin'}),

  floppies(
      'floppies',
      'Floppy Images',
      <String>{
        // zfile.cpp diskimages[]
        'adf', 'adz', 'ipf', 'scp', 'fdi', 'dms', 'wrp', 'dsq', 'pkd', 'ima',
        // raw types disk.cpp will take
        'img', 'st', 'dsk',
      }),

  hardDrives('harddrives', 'Hard Drives', <String>{'hdf', 'hdz', 'vhd', 'hdi'}),

  cdImages(
      'cd-images',
      'CD / ISO Images',
      <String>{
        // parsers in blkdev_cdimage.cpp
        'cue', 'ccd', 'mds', 'nrg', 'chd',
        // no parser needed: mounted through the raw-image fallback
        'iso',
      }),

  whdloadGames('lha', 'WHDLoad Games', <String>{'lha', 'lzx', 'lzh'}),

  archives('archives', 'Archives', <String>{'zip', '7z', 'rar', 'tar', 'gz'});

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

  /// Archives can hold any of the above, so a picker for [category] should
  /// offer them too rather than hide a zipped disk image.
  static Set<String> pickerExtensionsFor(FileCategory category) =>
      <String>{...category.extensions, ...archives.extensions};
}
