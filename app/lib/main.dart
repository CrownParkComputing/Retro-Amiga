import 'package:flutter/material.dart';

import 'data/app_prefs.dart';
import 'screens/configurations_screen.dart';
import 'screens/onboarding_screen.dart';

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
      home: const _Root(),
    );
  }
}

/// Decides whether to run setup or go straight to the shelf.
///
/// Setup is not a welcome screen to skip past: until it has found a Kickstart
/// there is nothing the shelf can usefully offer, so first launch goes there.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _setupComplete;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool complete = false;
    try {
      complete = await AppPrefs.setupComplete();
    } on Object {
      // A missing preference store means first run, not a failure.
    }
    if (mounted) setState(() => _setupComplete = complete);
  }

  @override
  Widget build(BuildContext context) {
    if (_setupComplete == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_setupComplete!) return const ConfigurationsScreen();
    return OnboardingScreen(
      onFinished: () => setState(() => _setupComplete = true),
    );
  }
}
