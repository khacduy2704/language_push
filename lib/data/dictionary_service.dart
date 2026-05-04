import '../data/app_database.dart';
import '../data/dictionary_parser.dart';

class DictionaryService {
  static Future<bool>? _loadingFuture;

  static Future<bool> isDictionaryLoaded() async {
    final int count = await AppDatabase.instance.getDictionaryCount();
    return count > 0;
  }

  static Future<bool> loadDictionary() async {
    if (_loadingFuture != null) {
      return _loadingFuture!;
    }

    _loadingFuture = _loadDictionaryInternal();
    final bool result = await _loadingFuture!;
    _loadingFuture = null;
    return result;
  }

  static Future<bool> _loadDictionaryInternal() async {
    try {
      // Load from assets
      final String assetPath = 'assets/data/EV/anhviet109K.dict';

      final AppDatabase db = AppDatabase.instance;
      final int existingCount = await db.getDictionaryCount();
      if (existingCount > 0) {
        return true;
      }

      final int inserted = await DictionaryParser.parseAndInsertInBatches(
        assetPath,
        db,
      );

      if (inserted <= 0) {
        print('No entries parsed/inserted from dictionary');
        return false;
      }

      final int count = await db.getDictionaryCount();
      print('Dictionary inserted successfully. Total count: $count');

      return count > 0;
    } catch (e) {
      print('Error loading dictionary: $e');
      return false;
    }
  }
}
