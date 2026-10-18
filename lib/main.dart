import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/notification_service.dart';
import 'providers/push_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/word_provider.dart';

Future<bool> _initializeApp() async {
  try {
    await AppDatabase.instance.database.timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('AppDatabase bootstrap failed: $error');
  }

  try {
    await NotificationService.instance.initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  } catch (error) {
    debugPrint('NotificationService initialize failed: $error');
  }

  bool firebaseReady = true;
  try {
    await _initializeFirebase();
  } catch (error) {
    debugPrint('Firebase initialize failed: $error');
    firebaseReady = false;
  }

  if (!kIsWeb && Platform.isIOS) {
    HomeWidget.setAppGroupId('group.com.example.push_language');
  }

  return firebaseReady;
}

Future<void> _initializeFirebase() async {
  const Duration _timeout = Duration(seconds: 10);
  try {
    await Firebase.initializeApp().timeout(_timeout);
    return;
  } on FirebaseException {
    if (!kIsWeb && Platform.isIOS) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyAuAtQnj5g1M3gCqfavD55KUkUZOcVc-3w',
          appId: '1:798855418030:ios:17de6aa92b78ff411f5d3f',
          messagingSenderId: '798855418030',
          projectId: 'push-language',
          storageBucket: 'push-language.firebasestorage.app',
          iosBundleId: 'com.example.pushLanguage27',
        ),
      ).timeout(_timeout);
      return;
    }
    rethrow;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WordProvider>(create: (_) => WordProvider()),
        ChangeNotifierProvider<PushProvider>(create: (_) => PushProvider()),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
      ],
      child: _AppLoader(),
    ),
  );
}

class _AppLoader extends StatefulWidget {
  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  late final Future<bool> _init = _initializeApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _init,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          // Show a themed loading screen instead of a black frame.
          return MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            ),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return App(firebaseReady: snapshot.data ?? false);
      },
    );
  }
}
