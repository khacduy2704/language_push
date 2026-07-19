import 'dart:io' show Platform;
import 'dart:async' show Future;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Word {
  final int? id;
  final String word;
  final String partOfSpeech;
  final String meaning;
  final bool isPushed;

  const Word({
    this.id,
    required this.word,
    required this.partOfSpeech,
    required this.meaning,
    this.isPushed = false,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'word': word,
    'partOfSpeech': partOfSpeech,
    'meaning': meaning,
    'isPushed': isPushed ? 1 : 0,
  };

  factory Word.fromMap(Map<String, Object?> map) => Word(
    id: map['id'] as int?,
    word: map['word']! as String,
    partOfSpeech: map['partOfSpeech']! as String,
    meaning: map['meaning']! as String,
    isPushed: (map['isPushed'] as int? ?? 0) == 1,
  );

  @override
  String toString() => 'Word($id, $word, $partOfSpeech, $meaning, isPushed: $isPushed)';
}

class DictionaryEntry {
  final int? id;
  final String word;
  final String ipa;
  final String partOfSpeech;
  final String meaning;

  const DictionaryEntry({
    this.id,
    required this.word,
    required this.ipa,
    required this.partOfSpeech,
    required this.meaning,
  });

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'word': word,
    'ipa': ipa,
    'partOfSpeech': partOfSpeech,
    'meaning': meaning,
  };

  factory DictionaryEntry.fromMap(Map<String, Object?> map) => DictionaryEntry(
    id: map['id'] as int?,
    word: map['word']! as String,
    ipa: map['ipa']! as String,
    partOfSpeech: map['partOfSpeech']! as String,
    meaning: map['meaning']! as String,
  );

  @override
  String toString() =>
      'DictionaryEntry($id, $word, $ipa, $partOfSpeech, $meaning)';
}

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'push_language.db';
  static const String _contactsTable = 'contacts';
  static const String _dictionaryTable = 'dictionary';
  static const String _cachedAudioTable = 'cached_audio';
  static const int _dbVersion = 5;

  sqflite.Database? _database;

  bool get _isMobile {
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  sqflite.DatabaseFactory get _databaseFactory {
    if (_isMobile) {
      return sqflite.databaseFactory;
    }

    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  Future<sqflite.Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final String dbPath = await _resolveDbPath();
    _database = await _databaseFactory.openDatabase(
      dbPath,
      options: sqflite.OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (sqflite.Database db, int version) async {
          await db.execute('''
            CREATE TABLE $_contactsTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              word TEXT NOT NULL,
              partOfSpeech TEXT NOT NULL DEFAULT 'None',
              meaning TEXT NOT NULL DEFAULT '',
              isPushed INTEGER NOT NULL DEFAULT 0
            )
          ''');

          await db.execute('''
            CREATE TABLE $_dictionaryTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              word TEXT NOT NULL UNIQUE,
              ipa TEXT NOT NULL DEFAULT '',
              partOfSpeech TEXT NOT NULL DEFAULT '',
              meaning TEXT NOT NULL DEFAULT ''
            )
          ''');

          await _seedWords(db);

          await db.execute('''
            CREATE TABLE $_cachedAudioTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              word TEXT NOT NULL UNIQUE,
              filePath TEXT NOT NULL,
              downloadedAt TEXT NOT NULL
            )
          ''');
        },
        onUpgrade: (sqflite.Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await _migrateFromLegacySchema(db);
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE $_contactsTable ADD COLUMN isPushed INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 4) {
            await db.execute('''
              CREATE TABLE $_dictionaryTable (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL UNIQUE,
                ipa TEXT NOT NULL DEFAULT '',
                partOfSpeech TEXT NOT NULL DEFAULT '',
                meaning TEXT NOT NULL DEFAULT ''
              )
            ''');
          }
          if (oldVersion < 5) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $_cachedAudioTable (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL UNIQUE,
                filePath TEXT NOT NULL,
                downloadedAt TEXT NOT NULL
              )
            ''');
          }
        },
      ),
    );

    return _database!;
  }

  Future<String> _resolveDbPath() async {
    final String databasesPath = _isMobile
        ? await sqflite.getDatabasesPath()
        : await databaseFactoryFfi.getDatabasesPath();

    return join(databasesPath, _dbName);
  }

  Future<String> getDatabasePath() async {
    return await _resolveDbPath();
  }

  Future<void> _seedWords(sqflite.Database db) async {
    const List<Word> initialWords = <Word>[
      Word(word: 'Hello', partOfSpeech: 'n', meaning: 'A greeting'),
      Word(word: 'Run', partOfSpeech: 'v', meaning: 'To move quickly'),
      Word(word: 'Beautiful', partOfSpeech: 'adj', meaning: 'Pleasing to the eye'),
      Word(word: 'Quickly', partOfSpeech: 'adv', meaning: 'In a fast manner'),
      Word(word: 'Example', partOfSpeech: 'n', meaning: 'A thing characteristic of its kind'),
      Word(word: 'Speak', partOfSpeech: 'v', meaning: 'To say something'),
      Word(word: 'Happy', partOfSpeech: 'adj', meaning: 'Feeling pleasure'),
      Word(word: 'Slowly', partOfSpeech: 'adv', meaning: 'In a slow manner'),
      Word(word: 'Friend', partOfSpeech: 'n', meaning: 'A person with whom one has a bond'),
    ];

    final sqflite.Batch batch = db.batch();
    for (final Word word in initialWords) {
      batch.insert(_contactsTable, word.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> _migrateFromLegacySchema(sqflite.Database db) async {
    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info($_contactsTable)',
    );

    final Set<String> columnNames = columns
        .map((Map<String, Object?> row) => row['name']! as String)
        .toSet();

    final bool alreadyNewSchema =
        columnNames.contains('word') &&
        columnNames.contains('partOfSpeech') &&
        columnNames.contains('meaning');

    if (alreadyNewSchema) {
      return;
    }

    await db.execute('''
      CREATE TABLE ${_contactsTable}_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        partOfSpeech TEXT NOT NULL DEFAULT 'None',
        meaning TEXT NOT NULL DEFAULT ''
      )
    ''');

    final bool hasLegacyName = columnNames.contains('name');
    if (hasLegacyName) {
      await db.execute('''
        INSERT INTO ${_contactsTable}_new (word, partOfSpeech, meaning)
        SELECT name, 'None', '' FROM $_contactsTable
      ''');
    }

    await db.execute('DROP TABLE $_contactsTable');
    await db.execute('ALTER TABLE ${_contactsTable}_new RENAME TO $_contactsTable');
  }

  Future<List<Word>> getWords({String query = '', bool includePushed = true}) async {
    final sqflite.Database db = await database;

    final String normalizedQuery = query.trim();
    final List<Map<String, Object?>> rows = normalizedQuery.isEmpty
        ? await db.query(
            _contactsTable,
            where: includePushed ? null : 'isPushed = 0',
            orderBy: 'word COLLATE NOCASE ASC',
          )
        : await db.rawQuery(
            '''
            SELECT * FROM $_contactsTable
            WHERE word LIKE ?
              AND (? = 1 OR isPushed = 0)
            ORDER BY
              CASE
                WHEN lower(word) = lower(?) THEN 0
                WHEN lower(word) LIKE lower(?) THEN 1
                ELSE 2
              END,
              word COLLATE NOCASE ASC
            ''',
            <Object?>[
              '%$normalizedQuery%',
              includePushed ? 1 : 0,
              normalizedQuery,
              '$normalizedQuery%',
            ],
          );

    return rows.map((Map<String, Object?> row) => Word.fromMap(row)).toList();
  }

  Future<Word?> findWord({
    required String word,
    required String meaning,
  }) async {
    final sqflite.Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      _contactsTable,
      where: 'lower(word) = lower(?) AND meaning = ?',
      whereArgs: <Object?>[word.trim(), meaning.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Word.fromMap(rows.first);
  }

  Future<void> addWord(String word, String partOfSpeech, String meaning) async {
    final String wordTrimmed = word.trim();
    final String meaningTrimmed = meaning.trim();
    
    if (wordTrimmed.isEmpty) {
      return;
    }

    final sqflite.Database db = await database;
    await db.insert(_contactsTable, Word(
      word: wordTrimmed,
      partOfSpeech: partOfSpeech.isEmpty ? 'None' : partOfSpeech,
      meaning: meaningTrimmed,
    ).toMap());
  }

  Future<void> updateWord(int id, String word, String partOfSpeech, String meaning) async {
    final String wordTrimmed = word.trim();
    final String meaningTrimmed = meaning.trim();

    if (wordTrimmed.isEmpty) {
      return;
    }

    final sqflite.Database db = await database;
    await db.update(
      _contactsTable,
      Word(
        id: id,
        word: wordTrimmed,
        partOfSpeech: partOfSpeech.isEmpty ? 'None' : partOfSpeech,
        meaning: meaningTrimmed,
      ).toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteWord(int id) async {
    final sqflite.Database db = await database;
    await db.delete(
      _contactsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteAllWords() async {
    final sqflite.Database db = await database;
    await db.delete(_contactsTable);
  }

  Future<List<Word>> getPushedWords() async {
    final sqflite.Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      _contactsTable,
      where: 'isPushed = 1',
      orderBy: 'word COLLATE NOCASE ASC',
    );
    return rows.map((Map<String, Object?> row) => Word.fromMap(row)).toList();
  }

  Future<void> setWordPushed(int id, {required bool pushed}) async {
    final sqflite.Database db = await database;
    await db.update(
      _contactsTable,
      <String, Object?>{'isPushed': pushed ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<DictionaryEntry>> searchDictionary({String query = ''}) async {
    final sqflite.Database db = await database;
    final String normalizedQuery = query.trim();
    final List<Map<String, Object?>> rows = normalizedQuery.isEmpty
        ? <Map<String, Object?>>[]
        : await db.rawQuery(
            '''
            SELECT * FROM $_dictionaryTable
            WHERE word LIKE ?
            ORDER BY
              CASE
                WHEN lower(word) = lower(?) THEN 0
                WHEN lower(word) LIKE lower(?) THEN 1
                ELSE 2
              END,
              word COLLATE NOCASE ASC
            ''',
            <Object?>[
              '%$normalizedQuery%',
              normalizedQuery,
              '$normalizedQuery%',
            ],
          );

    return rows
        .map((Map<String, Object?> row) => DictionaryEntry.fromMap(row))
        .toList();
  }

  Future<int> insertDictionaryEntry(DictionaryEntry entry) async {
    final sqflite.Database db = await database;
    try {
      return await db.insert(_dictionaryTable, entry.toMap(),
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
    } catch (_) {
      return -1;
    }
  }

  Future<void> insertDictionaryBatch(
      List<DictionaryEntry> entries) async {
    final sqflite.Database db = await database;
    final sqflite.Batch batch = db.batch();
    for (final DictionaryEntry entry in entries) {
      batch.insert(_dictionaryTable, entry.toMap(),
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<int> getDictionaryCount() async {
    final sqflite.Database db = await database;
    final List<Map<String, Object?>> result =
        await db.rawQuery('SELECT COUNT(*) as count FROM $_dictionaryTable');
    return result.isNotEmpty ? (result[0]['count'] as int?) ?? 0 : 0;
  }

  Future<void> clearDictionary() async {
    final sqflite.Database db = await database;
    await db.delete(_dictionaryTable);
  }

  // ── Cached audio ──────────────────────────────────────────────────────────

  /// Incremented every time an audio file is successfully cached.
  /// Listeners (e.g. word list items) can watch this to refresh their state.
  final ValueNotifier<int> audioCacheVersion = ValueNotifier<int>(0);

  Future<void> _ensureCachedAudioTable(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_cachedAudioTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL UNIQUE,
        filePath TEXT NOT NULL,
        downloadedAt TEXT NOT NULL
      )
    ''');

    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info($_cachedAudioTable)',
    );
    final Set<String> names = columns
        .map((Map<String, Object?> row) => row['name'] as String)
        .toSet();

    if (!names.contains('filePath')) {
      await db.execute(
        'ALTER TABLE $_cachedAudioTable ADD COLUMN filePath TEXT NOT NULL DEFAULT ""',
      );
    }
    if (!names.contains('downloadedAt')) {
      await db.execute(
        'ALTER TABLE $_cachedAudioTable ADD COLUMN downloadedAt TEXT NOT NULL DEFAULT ""',
      );
    }
  }

  Future<bool> hasCachedAudio(String word) async {
    final sqflite.Database db = await database;
    await _ensureCachedAudioTable(db);
    final List<Map<String, Object?>> rows = await db.query(
      _cachedAudioTable,
      columns: <String>['filePath'],
      where: 'word = ?',
      whereArgs: <Object?>[word.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> upsertCachedAudio(String word, String filePath) async {
    final sqflite.Database db = await database;
    await _ensureCachedAudioTable(db);
    await db.insert(
      _cachedAudioTable,
      <String, Object?>{
        'word': word.trim().toLowerCase(),
        'filePath': filePath,
        'downloadedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    audioCacheVersion.value++;
  }

  Future<void> deleteCachedAudio(String word) async {
    final sqflite.Database db = await database;
    await _ensureCachedAudioTable(db);
    await db.delete(
      _cachedAudioTable,
      where: 'word = ?',
      whereArgs: <Object?>[word.trim().toLowerCase()],
    );
  }

  Future<List<CachedAudio>> getCachedAudioList() async {
    final sqflite.Database db = await database;
    await _ensureCachedAudioTable(db);
    final List<Map<String, Object?>> rows = await db.query(
      _cachedAudioTable,
      orderBy: 'downloadedAt DESC',
    );
    return rows.map(CachedAudio.fromMap).toList();
  }

  Future<void> clearCachedAudioTable() async {
    final sqflite.Database db = await database;
    await _ensureCachedAudioTable(db);
    await db.delete(_cachedAudioTable);
  }
}

class CachedAudio {
  final int? id;
  final String word;
  final String filePath;
  final DateTime downloadedAt;

  const CachedAudio({
    this.id,
    required this.word,
    required this.filePath,
    required this.downloadedAt,
  });

  factory CachedAudio.fromMap(Map<String, Object?> map) => CachedAudio(
        id: map['id'] as int?,
        word: map['word']! as String,
        filePath: map['filePath']! as String,
        downloadedAt: DateTime.parse(map['downloadedAt']! as String),
      );
}
