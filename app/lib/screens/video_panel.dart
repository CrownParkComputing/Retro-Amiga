import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
import '../theme/amiga_theme.dart';
import 'settings_panel.dart';

/// The picture, app-wide. The machine's own video (resolution, aspect
/// correction, auto-crop, LEDs) is per config and lives in the editor.
class VideoPanel extends StatelessWidget {
  const VideoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const SettingsHeader('Screen'),
        Card(
          color: AmigaColors.card,
          child: ValueListenableBuilder<bool>(
            valueListenable: AppPrefs.screenFill,
            builder: (BuildContext context, bool fill, _) => SwitchListTile(
              secondary: const Icon(Icons.aspect_ratio),
              title: const Text('Fill the screen (16:9)'),
              subtitle: const Text(
                'Stretch the Amiga picture over the whole panel instead of '
                'keeping its shape with bars either side.'
              ),
              value: fill,
              onChanged: (bool v) => AppPrefs.setScreenFill(value: v),
            ),
          ),
        ),
        const SettingsHeader('Per machine'),
        const Card(
          color: AmigaColors.card,
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Resolution, aspect, crop, LEDs'),
            subtitle: Text(
              'Set per config, in its Picture section: Configs, long-press, '
              'Edit.',
            ),
          ),
        ),
      ],
    );
  }
}
