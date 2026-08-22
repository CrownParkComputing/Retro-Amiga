// The App Store / Play Store compliance page.
//
// One place that answers, on the device and with no network connection,
// every question a store review team asks about an emulator: what does it
// ship, what does it not ship, under what licences, what can it do with
// nothing supplied by the user, and where are the files that prove it.
//
// The sibling of Retro-C64's compliance screen, deliberately: the two apps
// are reviewed by the same people against the same rules, and an answer that
// is phrased differently in each is an answer that has to be checked twice.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_prefs.dart';
import '../data/aros_rom.dart';
import '../data/compliance_demo.dart';
import '../data/file_category.dart';
import '../data/media_library.dart';
import '../theme/amiga_theme.dart';

class CompliancePanel extends StatefulWidget {
  const CompliancePanel({super.key, this.onRerunSetup});

  /// Reopens the walkthrough. Compliance mode is a narrow place to be, and
  /// without this there would be no way out of it but the switch below.
  final VoidCallback? onRerunSetup;

  @override
  State<CompliancePanel> createState() => _CompliancePanelState();
}

class _CompliancePanelState extends State<CompliancePanel> {
  bool _mode = false;
  bool _busy = false;
  String _path = '';
  List<String> _files = const <String>[];
  bool _userKickstart = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Every lookup here is reporting, so one that fails costs a line of the
    // report rather than the page. This is the screen a reviewer is sent to;
    // it has to render whatever else is wrong.
    final bool mode = await AppPrefs.complianceMode();
    String path = '';
    List<String> files = const <String>[];
    bool userKick = false;
    try {
      path = (await ComplianceDemo.folder()).path;
      files = await ComplianceDemo.files();
    } catch (_) {
      // Leaves the path blank, which the wording below covers.
    }
    try {
      final MediaIndex index = await MediaLibrary.scan();
      userKick = index
          .of(FileCategory.roms)
          .any((MediaFile f) => !ArosRom.fileNames.contains(f.name.toLowerCase()));
    } catch (_) {
      // Report what is known rather than nothing.
    }
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _path = path;
      _files = files;
      _userKickstart = userKick;
    });
  }

  Future<void> _toggle() async {
    final bool next = !_mode;
    setState(() => _busy = true);
    try {
      // Writing the files out is part of turning it on, not a separate
      // button to remember: a mode you have to prepare by hand is one that
      // can be left half on.
      if (next) await ComplianceDemo.prepare();
      await AppPrefs.setComplianceMode(value: next);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(next ? 'Compliance mode is on' : 'Compliance mode is off'),
        content: Text(
          next
              ? 'The demo disk and the AROS ROM have been written out. Start a '
                  'machine and it will boot the AROS ROM, with no Kickstart of '
                  'yours involved. Open the demo from Games to see it run.'
              : 'Back to your own Kickstart and your own files. Nothing of '
                  'yours was changed while compliance mode was on.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: <Widget>[
        const Text('App Store / Play Store compliance',
            style: TextStyle(
                color: AmigaColors.text,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Everything a store review needs, on the device. No network '
          'connection is required to check any of it.',
          style: TextStyle(color: AmigaColors.textDim, fontSize: 12),
        ),

        const _Head('1. See it working with nothing supplied'),
        _Body(
          'The app ships AROS -- an independent, open reimplementation of the '
          'Amiga ROM -- and a demo disk of our own. Together they boot a real '
          'emulated Amiga and run it, with no files, no account and no '
          'network.\\n\\n'
          'Compliance mode is a SEPARATE MACHINE, not a swap. In it the '
          'emulator boots the AROS ROM and the demo folder below; your own '
          'Kickstart and your own disks are not read, written or touched. '
          'Turning it on or off applies to the next machine you start, '
          'because the ROM is chosen as the machine is built.\\n\\n'
          'Right now: ${_mode ? "COMPLIANCE MODE IS ON." : _userKickstart ? "running on your own Kickstart." : "no Kickstart of your own has been imported."}',
        ),
        Card(
          color: AmigaColors.panel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AmigaColors.panelBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: <Widget>[
              SwitchListTile(
                value: _mode,
                onChanged: _busy ? null : (_) => _toggle(),
                title: const Text('Compliance mode',
                    style: TextStyle(color: AmigaColors.text)),
                subtitle: Text(
                  _mode
                      ? 'On. Booting the bundled AROS ROM.'
                      : 'Off. Using your own Kickstart.',
                  style: const TextStyle(
                      color: AmigaColors.textDim, fontSize: 12),
                ),
                activeThumbColor: AmigaColors.accent,
              ),
              if (_mode)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'To run the demo:\n'
                      '  1.  Open Games in the sidebar.\n'
                      '  2.  Start "${ComplianceDemo.diskName}".\n\n'
                      'It is inserted and booted the same way any other disk '
                      'is -- nothing is typed in or started for you, so what '
                      'you see the demo do is what the emulator does with any '
                      'disk you give it.',
                      style: TextStyle(
                          color: AmigaColors.textDim,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const _Head('2. The demo files, and where they are'),
        _Body(_files.isEmpty
            ? 'Not written out yet. Turn compliance mode on and every file '
                'the demo uses appears here, in a folder you can open, read '
                'and copy from.'
            : 'These are the actual files the demo runs on, in a folder you '
                'can open rather than buried inside the app:'),
        _Mono(_path.isEmpty ? '...' : _path),
        if (_files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String f in _files)
                  Text('  •  $f',
                      style: const TextStyle(
                          color: AmigaColors.textDim,
                          fontSize: 12,
                          fontFamily: 'monospace')),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _path.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _path));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Path copied.')),
                    );
                  },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy the path'),
          ),
        ),

        const _Head('3. What the bundled ROM is'),
        const _Body(
          'AROS: an independent, open reimplementation of AmigaOS, written '
          'from scratch. It is NOT Commodore\'s or Amiga\'s code and contains '
          'none of it.\n\n'
          'Licence: the AROS Public License, which permits redistribution. '
          'Source: aros.sourceforge.io\n\n'
          'It is a reimplementation, not a clone. It boots and it runs the '
          'demo, but many WHDLoad titles and some disks need a real '
          'Kickstart -- which is why the app still offers to import one, and '
          'why the two are kept apart.',
        ),

        const _Head('4. Kickstart ROMs are never shipped'),
        const _Body(
          'The Amiga Kickstart ROMs are still under copyright. The app '
          'contains none of them and never distributes them. Most commercial '
          'Amiga software was written against them, so to run your old games '
          'you supply one yourself.\n\n'
          'Legitimate ways to obtain one:\n'
          '  •  Dump it from an Amiga you own.\n'
          '  •  Buy a licensed set -- Amiga Forever (Cloanto) includes them.\n\n'
          'Import it with Files, or drop it in the app\'s folder. Nothing '
          'above changes that: AROS is a reimplementation, not Amiga code.',
        ),

        const _Head('5. Games are never shipped'),
        const _Body(
          'The app contains no games. Everything playable comes from the '
          'user. It is a hardware emulator for a home computer of the 1980s, '
          'permitted under App Review Guideline 4.7. The demo disk above is '
          'our own work, written for this purpose.',
        ),

        const _Head('6. Free software, and where its source is'),
        const _Body(
          'The emulation core is Amiberry, under the GNU General Public '
          'License. WHDLoad, JST and AmiQuit are Bert Jahn\'s. The licences '
          'require the app to say so and to point at the source:\n\n'
          '  github.com/CrownParkComputing/Retro-Amiga\n'
          '  github.com/BlitterStudio/amiberry\n'
          '  aros.sourceforge.io',
        ),

        const _Head('7. Privacy'),
        const _Body(
          'No accounts, no sign-in, no analytics, no tracking, no data '
          'collected and none transmitted.',
        ),

        if (widget.onRerunSetup != null) ...<Widget>[
          const _Head('Start over'),
          const _Body(
            'Reopens the walkthrough, where the same choice is offered again.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : widget.onRerunSetup,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Back to the setup screen'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AmigaColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: AmigaColors.textDim, fontSize: 13, height: 1.4)),
      );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(color: AmigaColors.panelBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(text,
            style: const TextStyle(
                color: AmigaColors.text, fontSize: 12, fontFamily: 'monospace')),
      );
}
