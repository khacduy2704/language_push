import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/notification_service.dart';
import 'providers/push_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/word_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WordProvider>(create: (_) => WordProvider()),
        ChangeNotifierProvider<PushProvider>(create: (_) => PushProvider()),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ],
      child: const App(),
    ),
  );
}
