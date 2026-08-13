
import 'package:flutter/material.dart';

import '../data/ags_setup.dart';
import '../data/file_category.dart';
import '../data/amiga_model.dart';
import '../data/media_library.dart';
import '../data/media_root.dart';
import '../emulator.dart';
import '../theme/amiga_theme.dart';
import 'pad_designer_screen.dart';

/// Where things live and how they get there, after setup has run.
///
/// The same three actions setup offers - choose the media folder, file
/// everything into it, install WHDLoad - because none of them is a one-off:
/// media arrives on a device long after the first run.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  String _root = '';
  MediaIndex _index = const MediaIndex.empty();
  bool _busy = false;
  String? _notice;

  List<AgsInstall> _ags = <AgsInstall>[];

  /// Builds a config for an AGS set, with a Kickstart chosen the same way the
  /// wizard chooses one.
  Future<String> _setUpAgs(AgsInstall install) async {
    final List<MediaFile> roms = _index.of(FileCategory.roms);
    final MediaFile? rom = RomPicker.kickstartFor(AmigaModel.a1200, roms);
    if (rom == null) {
      return 'No Kickstart to boot it with. Add a 3.1 ROM and scan again.';
    }
    await AgsSetup.createConfig(install, rom.path);
    return '${install.name}: ${install.driveCount} drives'
        '${install.sharedFolder.isEmpty ? '' : ' and a shared folder'} '
        'set up. It is on the Configs shelf.';
  }

  Future<void> _findAgs() async {
    final List<AgsInstall> found = await AgsSetup.find(_index);
    if (!mounted) return;
    setState(() {
      _ags = found;
      _notice = found.isEmpty
          ? 'No AGS set found. It is a folder of four or more HDF files - '
              'use Browse if it is somewhere unusual.'
          : null;
    });
  }

  Future<void> _browseForAgs() async {
    final TextEditingController controller = TextEditingController(
      text: _root.isEmpty ? '/storage' : _root,
    );
    final String? folder = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('AGS folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'The folder holding Workbench.hdf, Games.hdf and the rest.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '/storage/XXXX-XXXX/AGS_UAE',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use this'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (folder == null || folder.trim().isEmpty) return;

    final AgsInstall? install = AgsSetup.inspect(folder.trim());
    if (!mounted) return;
    if (install == null) {
      setState(() => _notice =
          'No hard drives in ${folder.trim()} - an AGS set is four or more.');
      return;
    }
    setState(() => _ags = <AgsInstall>[install]);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String root = await MediaRoot.path();
    final MediaIndex index = await MediaLibrary.cached();
    if (!mounted) return;
    setState(() {
      _root = root;
      _index = index;
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final String message = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = message;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const _Header('Media'),
        Card(
          color: AmigaColors.card,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(_root.isEmpty ? '...' : _root),
                subtitle: const Text('Media folder'),
                trailing: MediaRoot.canChoose
                    ? TextButton(
                        onPressed: _busy ? null : _chooseRoot,
                        child: const Text('Change'),
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Scan for media'),
                subtitle: Text('${_index.files.length} files indexed'),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final MediaIndex index = await MediaLibrary.scan();
                            return '${index.files.length} files found.';
                          }),
                  child: const Text('Scan'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('File everything into the media folder'),
                subtitle: const Text(
                  'Moves what is elsewhere into Floppies, HardDrives, CDROMs, '
                  'LHA and Kickstarts, and unpacks disk images out of zips.',
                ),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final ImportResult result =
                                await MediaImporter.import(_index);
                            await MediaLibrary.scan();
                            return '${result.moved} moved, '
                                '${result.alreadyInPlace} already in place'
                                '${result.extracted > 0 ? ', ${result.extracted} unzipped' : ''}'
                                '${result.failed > 0 ? ', ${result.failed} failed' : ''}.';
                          }),
                  child: const Text('Import'),
                ),
              ),
            ],
          ),
        ),

        const _Header('Controls'),
        Card(
          color: AmigaColors.card,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.gamepad_outlined),
                title: const Text('On-screen pad'),
                subtitle: const Text(
                  'Where the stick and buttons sit, joystick or CD32 pad, and '
                  'any extra keys you want under a thumb.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const PadDesignerScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.videogame_asset_outlined),
                title: const Text('Controller buttons'),
                subtitle: const Text(
                  'Which button on a real controller is red, blue, green and '
                  'yellow. A CD32 config uses all four; anything else uses the '
                  'first two as fire.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: Emulator.openControllerMapping,
              ),
            ],
          ),
        ),

        const _Header('AGS'),
        Card(
          color: AmigaColors.card,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: const Text('Amiga Game Selector'),
                subtitle: const Text(
                  'A folder of HDFs and a shared folder, mounted as one '
                  'machine. Setting it up by hand means ten drives in the '
                  'right order.',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextButton(
                      onPressed: _busy ? null : _browseForAgs,
                      child: const Text('Browse'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _findAgs,
                      child: const Text('Find'),
                    ),
                  ],
                ),
              ),
              for (final AgsInstall install in _ags)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.storage, size: 18),
                  title: Text(install.name),
                  subtitle: Text(
                    '${install.driveCount} drives'
                    '${install.sharedFolder.isEmpty ? '' : ' + shared folder'}'
                    '  ·  boots ${install.bootDrive.split('/').last}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: TextButton(
                    onPressed:
                        _busy ? null : () => _run(() => _setUpAgs(install)),
                    child: const Text('Set up'),
                  ),
                ),
            ],
          ),
        ),

        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _notice!,
              style: const TextStyle(color: AmigaColors.tickGreen),
            ),
          ),
      ],
    );
  }

  Future<void> _chooseRoot() async {
    final TextEditingController controller =
        TextEditingController(text: _root);
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Media folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/sdcard/Amiga',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use this'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (chosen == null || chosen.trim().isEmpty) return;
    await MediaRoot.setPath(chosen.trim());
    await _load();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AmigaColors.accent,
        ),
      ),
    );
  }
}
