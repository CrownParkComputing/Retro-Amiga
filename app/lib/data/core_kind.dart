/// Which emulator core a saved setup runs on.
///
/// A setup is still a .uae file whichever core runs it: the marker is a
/// comment the cores ignore, so an old file and a new one sit side by side
/// on the shelf and each launches into its own library. Absence means
/// Amiberry -- every config written before cores existed is one of those,
/// and they all keep working untouched.
library;

enum CoreKind {
  /// The vendored Amiberry core (libuae4arm). The default everywhere a
  /// marker is missing or unrecognised.
  amiberry,

  /// The Copperline core (libcopperline_ffi), driven through the same
  /// uae4arm_host_* surface.
  copperline;

  /// The value written after `; retro-amiga: core=`.
  String get marker => name;

  /// The save-state extension this core writes: Amiberry's .uss, or
  /// Copperline's .clstate. The two formats are not interchangeable -- a
  /// state only ever resumes through the core that wrote it.
  String get stateExtension => switch (this) {
    CoreKind.amiberry => '.uss',
    CoreKind.copperline => '.clstate',
  };

  /// Human-facing label for the picker.
  String get label => switch (this) {
    CoreKind.amiberry => 'Amiberry',
    CoreKind.copperline => 'Copperline',
  };

  /// The version of the vendored core, for the About panel. Amiberry's is
  /// the project() version in the root CMakeLists; Copperline's is the
  /// submodule's package version. Neither is queried at runtime -- the
  /// core libraries export no version call -- so keep these in step when
  /// the vendored trees move.
  String get coreVersion => switch (this) {
    CoreKind.amiberry => '4.3.0',
    CoreKind.copperline => '1.0.1',
  };

  /// One paragraph on what the core is and how it differs from the other,
  /// for the About panel.
  String get description => switch (this) {
    CoreKind.amiberry =>
      'The WinUAE-derived core this app has always run, vendored and '
          'stripped for the host API. Cycle-accurate custom chips with a '
          'fast CPU interpreter and, where the platform allows it, a '
          'dynarec JIT. The safe default: broad compatibility, mature '
          'quirks coverage, and the path every pre-Copperline config was '
          'built for.',
    CoreKind.copperline =>
      'Copperline, a deterministic Rust reimplementation behind the same '
          'host API. Its CPU is a precise interpreter - no dynarec - so it '
          'is slower but cycle-faithful, and its WHDLoad booter, save '
          'states (.clstate) and hardware catalogue are its own. Some .uae '
          'settings have no Copperline equivalent and are translated or '
          'dropped at launch.',
  };

  /// The line in a .uae file that names the core, as a comment so every
  /// parser that does not know it skips it. Match is deliberately loose
  /// about spacing, the same way `collectionMarker` lines are read.
  static const String markerPrefix = '; retro-amiga: core=';

  /// The core a .uae names, or Amiberry when it names none -- which is the
  /// answer for every config written before this marker existed.
  static CoreKind fromConfigText(String text) {
    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith(markerPrefix)) continue;
      final String value = trimmed.substring(markerPrefix.length).trim();
      for (final CoreKind kind in CoreKind.values) {
        if (kind.marker == value) return kind;
      }
      // An unknown core name falls back to Amiberry rather than failing:
      // the file is still a .uae, and the conservative core is the one the
      // format was written for.
      return CoreKind.amiberry;
    }
    return CoreKind.amiberry;
  }

  /// The marker line to write, or null for Amiberry -- the default needs
  /// no marker, and not writing one keeps old files byte-for-byte what
  /// they were.
  String? get markerLine =>
      this == CoreKind.amiberry ? null : '$markerPrefix$marker';
}
