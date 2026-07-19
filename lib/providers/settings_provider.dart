import 'package:flutter/foundation.dart';

class SettingsProvider extends ChangeNotifier {
  static const List<String> languageOptions = <String>['Tiếng Việt', 'English'];
  static const List<String> timeToPushOptions = <String>[
    '1 min',
    '5 min',
    '10 min',
    '20 min',
    '30 min',
    '60 min',
    '120 min',
  ];

  String language = 'English';
  String timeToPush = '10 min';

  int get intervalMinutes => int.parse(timeToPush.split(' ').first);

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }

  void setTimeToPush(String value) {
    timeToPush = value;
    notifyListeners();
  }
}
