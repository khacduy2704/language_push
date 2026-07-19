import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';
import 'screens/firebase_setup_required_screen.dart';
import 'screens/home_shell.dart';

class App extends StatelessWidget {
  const App({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Push_Language',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: firebaseReady
          ? const AuthGate()
          : const FirebaseSetupRequiredScreen(fallbackChild: HomeShell()),
    );
  }
}
