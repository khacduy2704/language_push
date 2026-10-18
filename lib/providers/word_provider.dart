import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';

class WordProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  List<Word> words = <Word>[];
  String _searchQuery = '';
  bool isLoading = true;
  String? loadError;
  int _fetchToken = 0;

  WordProvider() {
    _fetch();
  }

  void setSearch(String query) {
    _searchQuery = query;
    _fetch();
  }

  void retryFetch() {
    _fetch();
  }

  Future<void> _fetch() async {
    final int token = ++_fetchToken;
    isLoading = true;
    loadError = null;
    notifyListeners();

    final Timer watchdog = Timer(const Duration(seconds: 10), () {
      if (token != _fetchToken || !isLoading) {
        return;
      }
      words = <Word>[];
      loadError = 'Loading words is stuck. Please retry.';
      isLoading = false;
      notifyListeners();
      debugPrint('WordProvider: watchdog released stuck loading state.');
    });

    Future<List<Word>> loadWords() =>
        _db.getWords(query: _searchQuery).timeout(const Duration(seconds: 8));

    bool recovered = false;
    while (true) {
      try {
        words = await loadWords();
        loadError = null;
        break;
      } on TimeoutException {
        debugPrint('WordProvider: getWords timed out.');
        if (recovered) {
          words = <Word>[];
          loadError = 'Loading words took too long. Please try again.';
          break;
        }
        recovered = true;
        debugPrint('WordProvider: resetting database after timeout...');
        await _db.resetDatabase();
      } catch (error, stackTrace) {
        debugPrint('WordProvider: getWords failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (recovered) {
          words = <Word>[];
          loadError = 'Could not load words. Please try again.';
          break;
        }
        recovered = true;
        debugPrint('WordProvider: resetting database after failure...');
        await _db.resetDatabase();
      }
    }

    if (token != _fetchToken) {
      watchdog.cancel();
      return;
    }

    watchdog.cancel();
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

  Future<void> clearAllWords() async {
    await _db.deleteAllWords();
    await _fetch();
  }
}
