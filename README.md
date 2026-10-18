# Push_Language

A new Flutter project.

## Native iOS migration

A separate SwiftUI app is available in [native-ios](./native-ios/README.md).
It targets iOS 15+ and provides navigation, offline dictionary search, and
word details with Apple text-to-speech, and SQLite saved-word management.
The push list, finite local reminders, and typing/flashcard practice are also
implemented. Listening practice, Flutter data import, and pronunciation recording caches
have not been migrated yet.
The native push list has no word-count limit. Each reminder randomly selects
1-5 words according to a shared, persisted setting (default 5); World rows mark
words already in the push list.
World includes To Learn/Mastered tabs and manual mastery/relearning. Practice
persists correct/incorrect counts and a 0-5 score for each saved word; reaching 5
automatically moves it to Mastered and removes it from reminders.
Native reminders also support a persisted daily time window (default 07:00-20:00),
overnight windows, and an all-day option, to avoid unwanted nighttime reminders.
Native Settings also supports persisted English/Vietnamese interface selection,
the shared reminder interval, and database location. Email/password authentication
is wired and uses Firebase configuration matching `com.example.pushLanguage`;
Google and Apple sign-in remain pending.
The Flutter app remains the working implementation during migration.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
