import 'package:flutter/material.dart';

import 'emulator.dart';

void main() {
  runApp(const Uae4ArmApp());
}

class Uae4ArmApp extends StatelessWidget {
  const Uae4ArmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAE4ARM 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE84B3C),
          brightness: Brightness.dark,
        ),
      ),
      home: const QuickStartScreen(),
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
      appBar: AppBar(
        title: const Text('UAE4ARM 2026'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'host: $_platform',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pick a machine to boot. You supply your own Kickstart ROM.',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: AmigaModel.all.length,
              itemBuilder: (BuildContext context, int index) {
                final AmigaModel model = AmigaModel.all[index];
                return ListTile(
                  leading: const Icon(Icons.memory),
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
    );
  }
}
