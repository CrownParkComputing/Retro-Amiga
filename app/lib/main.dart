import 'package:flutter/material.dart';

import 'emulator.dart';
import 'widgets/amiga_logo.dart';

void main() {
  runApp(const AmigaRetroApp());
}

class AmigaRetroApp extends StatelessWidget {
  const AmigaRetroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amiga-Retro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE1122F),
          brightness: Brightness.dark,
        ),
      ),
      home: const QuickStartScreen(),
    );
  }
}

/// The masthead: Retro Recompilation over the Amiga check and the app name.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        children: <Widget>[
          Image.asset(
            'assets/images/retro_recomp_logo.png',
            height: 64,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const AmigaLogo(height: 40),
              const SizedBox(width: 14),
              Text(
                'Amiga-Retro',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QuickStartScreen extends StatefulWidget {
  const QuickStartScreen({super.key});

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  String _platform = '...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlatform();
  }

  Future<void> _loadPlatform() async {
    try {
      final String name = await Emulator.platformName();
      if (mounted) setState(() => _platform = name);
    } on Exception catch (e) {
      if (mounted) setState(() => _platform = 'unavailable ($e)');
    }
  }

  Future<void> _launch(AmigaModel model) async {
    setState(() => _error = null);
    try {
      await Emulator.launchModel(model.id);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const _Masthead(),
            if (_error != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Pick a machine to boot. You supply your own Kickstart ROM.',
                    ),
                  ),
                  Text(
                    _platform,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: AmigaModel.all.length,
                itemBuilder: (BuildContext context, int index) {
                  final AmigaModel model = AmigaModel.all[index];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    leading: SizedBox(
                      width: 96,
                      height: 64,
                      child: Image.asset(
                        model.artworkPath,
                        fit: BoxFit.contain,
                        // A missing photo should cost the picture, not the row.
                        errorBuilder: (BuildContext context, Object error,
                                StackTrace? stack) =>
                            const AmigaLogo(height: 32),
                      ),
                    ),
                    title: Text(model.name),
                    subtitle: Text(model.blurb),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () => _launch(model),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
