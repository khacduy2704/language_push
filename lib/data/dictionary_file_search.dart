import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DictionaryFileSearch {
  static final DictionaryFileSearch _instance = DictionaryFileSearch._();

  factory DictionaryFileSearch() {
    return _instance;
  }

  DictionaryFileSearch._();

  static const String _assetDict = 'assets/data/EV/anhviet109K.dict';
  static const String _assetIndex = 'assets/data/EV/anhviet109K.index';
  static const String _assetIni = 'assets/data/EV/anhviet109K.ini';

  late File _localDictFile;
  late File _localNumericIndexFile;

  Future<void>? _initFuture;
  final List<_IndexEntry> _entries = <_IndexEntry>[];
  final List<String> _lowerWords = <String>[];
  final Map<String, List<int>> _wordToIndexes = <String, List<int>>{};

  Future<void> ensureReady() async {
    _initFuture ??= _initialize();
    await _initFuture;
  }

  Future<List<DictWord>> search({required String query, int limit = 50}) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return <DictWord>[];
    }

    await ensureReady();
    if (_entries.isEmpty) {
      return <DictWord>[];
    }

    final List<DictWord> exact = <DictWord>[];
    final List<DictWord> prefix = <DictWord>[];
    final List<DictWord> contains = <DictWord>[];

    final List<int> exactIndexes = _wordToIndexes[q] ?? <int>[];
    for (final int idx in exactIndexes) {
      final _IndexEntry entry = _entries[idx];
      exact.add(_toDictWord(entry, score: 0));
      if (exact.length >= limit) {
        return exact;
      }
    }

    for (int i = 0; i < _entries.length; i++) {
      final String word = _lowerWords[i];
      if (word == q || !word.startsWith(q)) {
        if (i % 12000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        continue;
      }

      prefix.add(_toDictWord(_entries[i], score: 1));
      if (exact.length + prefix.length >= limit) {
        return <DictWord>[...exact, ...prefix].take(limit).toList();
      }

      if (i % 12000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (q.length >= 3) {
      for (int i = 0; i < _entries.length; i++) {
        final String word = _lowerWords[i];
        if (word == q || word.startsWith(q) || !word.contains(q)) {
          if (i % 12000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          continue;
        }

        contains.add(_toDictWord(_entries[i], score: 2));
        if (exact.length + prefix.length + contains.length >= limit) {
          break;
        }

        if (i % 12000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    return <DictWord>[...exact, ...prefix, ...contains].take(limit).toList();
  }

  Future<String> loadMeaning(DictWord word) async {
    await ensureReady();

    final RandomAccessFile raf = await _localDictFile.open(mode: FileMode.read);
    try {
      await raf.setPosition(word.offset);
      final List<int> bytes = await raf.read(word.length);
      final String raw = utf8.decode(bytes, allowMalformed: true);
      final List<String> lines = const LineSplitter().convert(raw);
      if (lines.isEmpty) {
        return '';
      }

      if (lines.first.trimLeft().startsWith('@')) {
        return lines.skip(1).join('\n').trim();
      }
      return raw.trim();
    } finally {
      await raf.close();
    }
  }

  Future<void> _initialize() async {
    final Directory docDir = await getApplicationDocumentsDirectory();
    final Directory evDir = Directory(p.join(docDir.path, 'ev_dict'));
    if (!await evDir.exists()) {
      await evDir.create(recursive: true);
    }

    final File localDict = File(p.join(evDir.path, 'anhviet109K.dict'));
    final File localIndex = File(p.join(evDir.path, 'anhviet109K.index'));
    final File localIni = File(p.join(evDir.path, 'anhviet109K.ini'));
    _localNumericIndexFile =
        File(p.join(evDir.path, 'anhviet109K.local_index.tsv'));

    await _copyAssetIfMissing(_assetDict, localDict);
    await _copyAssetIfMissing(_assetIndex, localIndex);
    await _copyAssetIfMissing(_assetIni, localIni);

    _localDictFile = localDict;

    if (!await _localNumericIndexFile.exists()) {
      await _buildNumericIndex();
    }

    await _loadNumericIndex();

    final bool missingPosForAllEntries =
        _entries.isNotEmpty &&
        _entries.every((entry) => entry.partOfSpeech.isEmpty);
    if (missingPosForAllEntries) {
      await _buildNumericIndex();
      await _loadNumericIndex();
    }
  }

  Future<void> _copyAssetIfMissing(String assetPath, File target) async {
    if (await target.exists()) {
      return;
    }

    final ByteData data = await rootBundle.load(assetPath);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  Future<void> _buildNumericIndex() async {
    final List<int> bytes = await _localDictFile.readAsBytes();
    final StringBuffer buffer = StringBuffer();

    int lineStart = 0;
    int? entryStart;
    String currentWord = '';
    String currentIpa = '';
    String currentPreview = '';
    String currentPos = '';
    int processedLines = 0;

    void flushEntry(int endOffset) {
      final int? start = entryStart;
      if (start == null || currentWord.isEmpty || endOffset <= start) {
        return;
      }

      final int length = endOffset - start;
      buffer
        ..write(currentWord)
        ..write('\t')
        ..write(start)
        ..write('\t')
        ..write(length)
        ..write('\t')
        ..write(_sanitizeField(currentIpa))
        ..write('\t')
        ..write(_sanitizeField(currentPreview))
        ..write('\t')
        ..write(_sanitizeField(currentPos))
        ..write('\n');
    }

    for (int i = 0; i <= bytes.length; i++) {
      final bool atEnd = i == bytes.length;
      final bool atLineEnd = !atEnd && bytes[i] == 10;
      if (!atEnd && !atLineEnd) {
        continue;
      }

      List<int> lineBytes = bytes.sublist(lineStart, i);
      if (lineBytes.isNotEmpty && lineBytes.last == 13) {
        lineBytes = lineBytes.sublist(0, lineBytes.length - 1);
      }

      final String line = utf8.decode(lineBytes, allowMalformed: true);
      final String trimmed = line.trim();

      if (trimmed.startsWith('@')) {
        flushEntry(lineStart);
        entryStart = lineStart;
        currentPreview = '';
        currentPos = '';

        final int slashStart = trimmed.indexOf('/');
        final int slashEnd = trimmed.lastIndexOf('/');
        if (slashStart > 0 && slashEnd > slashStart) {
          currentWord = trimmed.substring(1, slashStart).trim();
          currentIpa = trimmed.substring(slashStart, slashEnd + 1).trim();
        } else {
          currentWord = trimmed.substring(1).trim();
          currentIpa = '';
        }
      } else if (trimmed.startsWith('*')) {
        currentPos = trimmed.substring(1).trim();
      } else if (currentPreview.isEmpty &&
          (trimmed.startsWith('-') || trimmed.startsWith('='))) {
        currentPreview = trimmed.substring(1).trim();
      }

      lineStart = i + 1;
      processedLines += 1;
      if (processedLines % 6000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    flushEntry(bytes.length);
    await _localNumericIndexFile.writeAsString(buffer.toString(), flush: true);
  }

  Future<void> _loadNumericIndex() async {
    _entries.clear();
    _lowerWords.clear();
    _wordToIndexes.clear();

    final Stream<String> stream = _localNumericIndexFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    int lineNo = 0;
    await for (final String line in stream) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final List<String> parts = trimmed.split('\t');
      if (parts.length < 5) {
        continue;
      }

      final int? offset = int.tryParse(parts[1]);
      final int? length = int.tryParse(parts[2]);
      if (offset == null || length == null || length <= 0) {
        continue;
      }

      final _IndexEntry entry = _IndexEntry(
        word: parts[0],
        offset: offset,
        length: length,
        ipa: parts[3],
        preview: parts[4],
        partOfSpeech: parts.length > 5 ? parts[5] : '',
      );
      final int index = _entries.length;
      _entries.add(entry);

      final String lower = entry.word.toLowerCase();
      _lowerWords.add(lower);
      _wordToIndexes.putIfAbsent(lower, () => <int>[]).add(index);

      lineNo += 1;
      if (lineNo % 9000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  DictWord _toDictWord(_IndexEntry entry, {required int score}) {
    return DictWord(
      word: entry.word,
      ipa: entry.ipa,
      meaning: entry.preview,
      score: score,
      offset: entry.offset,
      length: entry.length,
      partOfSpeech: entry.partOfSpeech,
    );
  }

  String _sanitizeField(String value) {
    return value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
  }
}

class DictWord {
  final String word;
  final String ipa;
  final String meaning;
  final int score;
  final int offset;
  final int length;
  final String partOfSpeech;

  const DictWord({
    required this.word,
    required this.ipa,
    required this.meaning,
    required this.score,
    required this.offset,
    required this.length,
    required this.partOfSpeech,
  });

  @override
  String toString() {
    return 'DictWord($word, $ipa, $partOfSpeech, score: $score, offset: $offset, length: $length)';
  }
}

class _IndexEntry {
  final String word;
  final int offset;
  final int length;
  final String ipa;
  final String preview;
  final String partOfSpeech;

  const _IndexEntry({
    required this.word,
    required this.offset,
    required this.length,
    required this.ipa,
    required this.preview,
    required this.partOfSpeech,
  });
}
