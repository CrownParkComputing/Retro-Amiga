import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'emulator_settings.dart';
import 'media_library.dart';
import 'media_root.dart';
import 'whdload_support.dart';

/// Prepares Zeb's full-disk WHDLoad image without editing it from Android.
///
/// Zeb's README requires the user's ROM images in `Devs:Kickstarts`. The raw
/// `.img` contains an Amiga RDB/FFS filesystem, so Android cannot safely copy
/// a file into it. Instead a tiny directory drive boots first, uses AmigaDOS
/// itself to copy the prepared ROM aliases into `Workbench:Devs/Kickstarts`,
/// then executes Zeb's original startup-sequence. The image is updated by its
/// own filesystem handler, preserving Amiga metadata and avoiding corruption.
class ZebWhdloadSupport {
  const ZebWhdloadSupport._();

  static const String bootstrapFolderName = 'zeb-bootstrap';

  @visibleForTesting
  static bool appliesTo(List<String> hardDrives) {
    final String identity = hardDrives.join('/').toLowerCase();
    return identity.contains('zeb') && identity.contains('whd');
  }

  /// A boot script intentionally limited to the volume names documented by
  /// Zeb: Workbench is DH0's volume, and the support mount is `save-data`.
  @visibleForTesting
  static const String startupSequence = '''FAILAT 999
Workbench:C/Assign SYS: Workbench:
Workbench:C/Assign C: Workbench:C
Workbench:C/Assign DEVS: Workbench:Devs
Workbench:C/Assign L: Workbench:L
Workbench:C/Assign LIBS: Workbench:Libs
Workbench:C/Assign FONTS: Workbench:Fonts
Workbench:C/MakeDir Workbench:Devs/Kickstarts
Workbench:C/Copy save-data:Kickstarts/#? TO Workbench:Devs/Kickstarts ALL QUIET
Workbench:C/Execute Workbench:S/Startup-Sequence
''';

  /// Adds the two support directory mounts before Zeb's disk image.
  ///
  /// Both directories live in the shared `Retro-Applications/Amiga/WHDBoot`
  /// tree. They are not application-private storage and survive uninstall.
  static Future<EmulatorSettings> prepare(
    EmulatorSettings settings,
    MediaIndex index,
  ) async {
    if (!appliesTo(settings.hardDrives)) return settings;

    await WhdloadSupport.installFromBundle();
    await WhdloadSupport.installKickstarts(index);
    final WhdloadStatus status = await WhdloadSupport.status();
    if (status.kickstartCount == 0) {
      AppLog.warn(
        'zeb',
        'Zeb WHDLoad found, but no compatible Kickstarts could be prepared',
      );
      return settings;
    }

    final String root = await MediaRoot.path();
    final Directory support = Directory('$root/WHDBoot');
    final Directory saveData = Directory('${support.path}/save-data');
    final Directory bootstrap = Directory(
      '${support.path}/$bootstrapFolderName',
    );
    final Directory scripts = Directory('${bootstrap.path}/S');
    scripts.createSync(recursive: true);
    saveData.createSync(recursive: true);
    File(
      '${scripts.path}/startup-sequence',
    ).writeAsStringSync(startupSequence, flush: true);

    final List<String> original = settings.hardDrives
        .where(
          (String path) =>
              path.isNotEmpty &&
              !path.endsWith('/$bootstrapFolderName') &&
              !path.endsWith('/WHDBoot/save-data'),
        )
        .toList();
    AppLog.info(
      'zeb',
      '${status.kickstartCount} Kickstart alias(es) will be installed into '
          'Workbench:Devs/Kickstarts before Zeb starts',
    );
    return settings.copyWith(
      hardDrives: <String>[bootstrap.path, saveData.path, ...original],
    );
  }
}
