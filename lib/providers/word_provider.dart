import 'package:flutter/foundation.dart';

import '../data/app_database.dart';

class WordProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  List<Word> words = <Word>[];
  String _searchQuery = '';
  bool isLoading = true;

  WordProvider() {
    _fetch();
  }

  void setSearch(String query) {
    _searchQuery = query;
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      words = await _db.getWords(query: _searchQuery);
    } catch (_) {
      words = <Word>[];
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> addWord(String word, String partOfSpeech, String meaning) async {
    await _db.addWord(word, partOfSpeech, meaning);
    await _fetch();
  }

  Future<void> updateWord(
    int id,
    String word,
    String partOfSpeech,
    String meaning,
  ) async {
    await _db.updateWord(id, word, partOfSpeech, meaning);
    await _fetch();
  }

  Future<void> deleteWord(int id) async {
    await _db.deleteWord(id);
    await _fetch();
  }
}
