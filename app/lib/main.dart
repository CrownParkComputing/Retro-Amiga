import 'package:flutter/material.dart';

import 'screens/configurations_screen.dart';

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
      home: const ConfigurationsScreen(),
    );
  }
}
