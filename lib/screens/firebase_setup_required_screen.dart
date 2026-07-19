import 'package:flutter/material.dart';

class FirebaseSetupRequiredScreen extends StatelessWidget {
  const FirebaseSetupRequiredScreen({
    required this.fallbackChild,
    super.key,
  });

  final Widget fallbackChild;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase setup needed'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Firebase is not configured yet for this build.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add Firebase config files from Firebase Console, then rebuild the app:\n\n'
              '- Android: android/app/google-services.json\n'
              '- iOS: ios/Runner/GoogleService-Info.plist',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(builder: (_) => fallbackChild),
                );
              },
              child: const Text('Continue without sign-in'),
            ),
          ],
        ),
      ),
    );
  }
}
