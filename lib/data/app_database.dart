import 'dart:io' show Platform;

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

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'push_language.db';
  static const String _contactsTable = 'contacts';
  static const int _dbVersion = 3;

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

          await _seedWords(db);
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

  Future<List<Word>> getWords({String query = ''}) async {
    final sqflite.Database db = await database;

    final String normalizedQuery = query.trim();
    final List<Map<String, Object?>> rows = await db.query(
      _contactsTable,
      where: normalizedQuery.isEmpty ? null : 'word LIKE ?',
      whereArgs: normalizedQuery.isEmpty ? null : <String>['%$normalizedQuery%'],
      orderBy: 'word COLLATE NOCASE ASC',
    );

    return rows.map((Map<String, Object?> row) => Word.fromMap(row)).toList();
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
}
