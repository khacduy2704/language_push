import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../data/notification_service.dart';

class PushProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  List<Word> pushedWords = <Word>[];

  PushProvider() {
    _loadPushedWords();
  }

  Future<void> _loadPushedWords() async {
    try {
      pushedWords = await _db.getPushedWords();
      notifyListeners();
    } catch (_) {}
  }

  bool isWordPushed(int? id) =>
      id != null && pushedWords.any((Word w) => w.id == id);

  Future<void> addWord(Word word, int intervalMinutes) async {
    if (isWordPushed(word.id)) {
      return;
    }
    if (word.id != null) {
      await _db.setWordPushed(word.id!, pushed: true);
    }
    pushedWords = <Word>[...pushedWords, word];
    notifyListeners();
    _reschedule(intervalMinutes);
  }

  Future<void> removeWord(Word word, int intervalMinutes) async {
    if (word.id != null) {
      await _db.setWordPushed(word.id!, pushed: false);
    }
    pushedWords = pushedWords.where((Word w) => w.id != word.id).toList();
    notifyListeners();
    _reschedule(intervalMinutes);
  }

  void replaceWord(Word updated, int intervalMinutes) {
    final int index = pushedWords.indexWhere((Word w) => w.id == updated.id);
    if (index < 0) {
      return;
    }
    final List<Word> next = List<Word>.from(pushedWords);
    next[index] = updated;
    pushedWords = next;
    notifyListeners();
    _reschedule(intervalMinutes);
  }

  void reschedule(int intervalMinutes) {
    _reschedule(intervalMinutes);
  }

  void _reschedule(int intervalMinutes) {
    NotificationService.instance.schedule(
      words: pushedWords,
      intervalMinutes: intervalMinutes,
    );
  }
}
