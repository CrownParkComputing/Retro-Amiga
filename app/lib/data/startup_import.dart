import 'media_library.dart';
import 'media_root.dart';
import 'app_log.dart';

/// Files whatever has appeared since last time, every launch.
///
/// The app ships no Kickstart, no games and no music, so everything the user
/// has arrives from outside: dropped into the app's folder through the Files
/// app, opened in from another app, or restored with the device. Until now the
/// only things that filed it were the onboarding walkthrough and the Scan
/// button in Settings, which means a user who copies floppies in on Tuesday
/// sees an unchanged library until they think to press a button they have no
/// reason to know about.
///
/// So the scan runs on load. It is the same [MediaLibrary.scan] and
/// [MediaImporter.import] pair those two call, with the same rules:
///
///   * zips are opened and their members filed by extension, so a downloaded
///     kickstarts.zip, music.zip, or a pack of .adf lands in the right folder
///     without being unpacked by hand;
///   * files already inside the media root are left alone, so this is cheap on
///     every launch after the first;
///   * a move within a volume is a rename, so a large collection is filed
///     instantly rather than duplicated.
///
/// Deliberately quiet. A launch that finds nothing must look exactly like a
/// launch with no import at all -- this is plumbing, not a feature to announce
/// -- so it reports through [AppLog] and returns a result the caller may
/// ignore.
class StartupImport {
  const StartupImport._();

  /// Scans, imports, and returns what changed. Never throws: a launch must not
  /// be blocked by a bad file or an unreadable directory, and the worst case
  /// is a library that is missing something the user can still fix by hand
  /// with the Scan button.
  static Future<ImportResult?> run() async {
    try {
      final MediaIndex index = await MediaLibrary.scan();
      final ImportResult result = await MediaImporter.import(index);
      if (result.moved > 0) {
        AppLog.info('startup', 'filed ${result.moved} new file(s) on launch');
      }
      return result;
    } on Object catch (error) {
      AppLog.warn('startup', 'import skipped: $error');
      return null;
    }
  }
}
