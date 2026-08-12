import 'package:flutter/material.dart';

import '../emulator.dart';
import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';

/// What this is, and what is running underneath it.
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Row(
          children: <Widget>[
            const AmigaLogo(height: 40),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Amiga-Retro',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AmigaColors.text,
                  ),
                ),
                FutureBuilder<String>(
                  future: Emulator.platformName(),
                  builder: (BuildContext context, AsyncSnapshot<String> snap) {
                    return Text(
                      'running on ${snap.data ?? '...'}',
                      style: const TextStyle(color: AmigaColors.textDim),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _Section(
          title: 'The emulator',
          body: 'Amiberry, which is WinUAE\'s core with a Linux and handheld '
              'front end. It is vendored and built for each platform in turn, '
              'because they do not agree on much: iOS cannot JIT at all, so '
              'that build compiles the JIT out entirely rather than switching '
              'it off at runtime.',
        ),
        _Section(
          title: 'The front end',
          body: 'Flutter, everywhere - Android, iOS, macOS, Linux and Windows '
              'from one codebase. The emulator draws its own screen natively; '
              'nothing is copied through Dart, so the picture costs the same '
              'as it does in Amiberry proper.',
        ),
        _Section(
          title: 'What you need to supply',
          body: 'A Kickstart ROM. They are still under copyright, so none '
              'ships here - Cloanto sell them, and if you have an Amiga you '
              'may already own one. Everything else, the app will find by '
              'scanning.',
        ),
        _Section(
          title: 'Thanks',
          body: 'Amiberry, WinUAE, and the people who wrote the demos that '
              'made anyone want a machine like this in the first place.',
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AmigaColors.accent,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AmigaColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
