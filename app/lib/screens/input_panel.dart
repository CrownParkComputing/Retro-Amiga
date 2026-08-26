import 'dart:io';

import 'package:flutter/material.dart';

import '../emulator.dart';
import '../theme/amiga_theme.dart';
import 'pad_designer_screen.dart';
import 'settings_panel.dart';

/// How the machine is driven: the on-screen pad and a real controller's
/// buttons. Per-config choices (which port, joystick or CD32 pad) stay in the
/// config editor, because they are the machine's, not the app's.
class InputPanel extends StatelessWidget {
  const InputPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const SettingsHeader('Controls'),
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
                    builder: (BuildContext context) =>
                        const PadDesignerScreen(),
                  ),
                ),
              ),
              // The mapping screen is the Android Activity's - it has to see
              // raw controller events, which is native work that iOS has no
              // counterpart for yet. A settings row that silently does
              // nothing is worse than no row.
              if (Platform.isAndroid)
                const ListTile(
                  leading: Icon(Icons.videogame_asset_outlined),
                  title: Text('Controller buttons'),
                  subtitle: Text(
                    'Which button on a real controller is red, blue, green and '
                    'yellow. A CD32 config uses all four; anything else uses the '
                    'first two as fire.',
                  ),
                  trailing: Icon(Icons.chevron_right),
                  onTap: Emulator.openControllerMapping,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
