import 'dart:io';

import 'amiga_model.dart';
import 'config_generator.dart';
import 'host_paths.dart';
import 'emulator_settings.dart';

/// A saved setup on the shelf.
class SavedConfig {
  const SavedConfig({
    required this.name,
    required this.path,
    required this.model,
    required this.summary,
  });

  final String name;
  final String path;

  /// Best guess at the machine, read back from the config. Null when the file
  /// predates us or names a machine we do not know.
  final AmigaModel? model;

  /// One line describing what is in the drives, for the shelf card.
  final String summary;
}

/// Where saved setups live, and how they get there.
///
/// Files are plain .uae text in a conf/ directory beside the app's other
/// data, which is also where the core looks when handed --config.
class ConfigStore {
  const ConfigStore._();

  static const String currentSettingsFile = '.current_settings.uae';

  static Future<Directory> configDirectory() async {
    final Directory dir = Directory('${await HostPaths.appSupport()}/conf');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static String _sanitise(String name) {
    final String trimmed = name.trim();
    final String cleaned = trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_')
        .trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  /// Writes [settings] as `<name>.uae` and returns the file.
  static Future<File> save(EmulatorSettings settings, String name) async {
    final Directory dir = await configDirectory();
    final File file = File('${dir.path}/${_sanitise(name)}.uae');
    file.writeAsStringSync(ConfigGenerator.generate(settings));
    return file;
  }

  /// Writes the scratch config used for a one-off launch that is not being
  /// added to the shelf. Leading dot keeps it out of the listing.
  static Future<File> saveCurrent(EmulatorSettings settings) async {
    final Directory dir = await configDirectory();
    final File file = File('${dir.path}/$currentSettingsFile');
    file.writeAsStringSync(ConfigGenerator.generate(settings));
    return file;
  }

  static Future<List<SavedConfig>> list() async {
    final Directory dir = await configDirectory();
    final List<SavedConfig> configs = <SavedConfig>[];

    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! File) continue;
      final String name = entity.uri.pathSegments.last;
      if (!name.endsWith('.uae')) continue;
      if (name.startsWith('.')) continue; // scratch configs

      String text;
      try {
        text = entity.readAsStringSync();
      } on Exception {
        continue;
      }
      configs.add(
        SavedConfig(
          name: name.substring(0, name.length - 4),
          path: entity.path,
          model: _modelFrom(text),
          summary: _summaryFrom(text),
        ),
      );
    }

    configs.sort(
      (SavedConfig a, SavedConfig b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return configs;
  }

  static Future<void> delete(String path) async {
    final File file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  static String? _value(String text, String key) {
    for (final String line in text.split('\n')) {
      final int eq = line.indexOf('=');
      if (eq <= 0) continue;
      if (line.substring(0, eq).trim() == key) {
        return line.substring(eq + 1).trim();
      }
    }
    return null;
  }

  /// Infers the machine from what the config asks for. The core has no single
  /// "model" key: a setup is described by its chipset, CPU and CD hardware, so
  /// this reads those back the same way the launcher's parser did.
  static AmigaModel? _modelFrom(String text) {
    if (_value(text, 'cd32cd') == 'true') return AmigaModel.cd32;
    if (_value(text, 'cdtv') == 'true') return AmigaModel.cdtv;

    final String chipset = _value(text, 'chipset') ?? '';
    final int cpu = int.tryParse(_value(text, 'cpu_model') ?? '') ?? 68000;

    if (chipset == 'aga') {
      if (cpu >= 68040) return AmigaModel.a4000;
      return AmigaModel.a1200;
    }
    if (cpu >= 68030) return AmigaModel.a3000;
    if (chipset.startsWith('ecs')) return AmigaModel.a600;
    return AmigaModel.a500;
  }

  static String _summaryFrom(String text) {
    final List<String> parts = <String>[];

    final String? whd = _value(text, 'whdload_filename');
    if (whd != null && whd.isNotEmpty) {
      parts.add('WHDLoad: ${_baseName(whd)}');
    }
    final String? cd = _value(text, 'cdimage0');
    if (cd != null && cd.isNotEmpty) {
      parts.add('CD: ${_baseName(cd.replaceAll(RegExp(r',image$'), ''))}');
    }
    final String? df0 = _value(text, 'floppy0');
    if (df0 != null && df0.isNotEmpty) {
      parts.add('DF0: ${_baseName(df0)}');
    }
    for (final String line in text.split('\n')) {
      if (line.startsWith('hardfile2=') || line.startsWith('filesystem2=')) {
        parts.add('Hard drive');
        break;
      }
    }
    return parts.isEmpty ? 'No media' : parts.join(' · ');
  }

  static String _baseName(String path) {
    final String cleaned = path.replaceAll('"', '');
    final int slash = cleaned.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? cleaned : cleaned.substring(slash + 1);
  }
}
