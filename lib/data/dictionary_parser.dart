import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import 'app_database.dart';

class DictionaryParser {
  static Future<List<DictionaryEntry>> parseFile(String filePath) async {
    final List<DictionaryEntry> entries = <DictionaryEntry>[];
    
    try {
      late List<String> lines;

      // Try to load as asset first
      if (filePath.startsWith('assets/')) {
        try {
          final String content = await rootBundle.loadString(filePath);
          lines = content.split('\n');
        } catch (_) {
          // Asset not found, try as file path
          final File file = File(filePath);
          if (!await file.exists()) {
            return entries;
          }
          lines = await file.readAsLines();
        }
      } else {
        // Load as regular file
        final File file = File(filePath);
        if (!await file.exists()) {
          return entries;
        }
        lines = await file.readAsLines();
      }
      
      String? currentWord;
      String currentIpa = '';
      final List<String> meanings = <String>[];

      for (final String line in lines) {
        final String trimmed = line.trim();

        // Skip empty lines and database info lines
        if (trimmed.isEmpty || trimmed.startsWith('@00-')) {
          continue;
        }

        // New word entry starts with @
        if (trimmed.startsWith('@')) {
          // Save previous entry if exists
          if (currentWord != null && currentWord.isNotEmpty) {
            final DictionaryEntry entry = DictionaryEntry(
              word: currentWord,
              ipa: currentIpa,
              partOfSpeech: meanings.isNotEmpty ? meanings.first : '',
              meaning: meanings.join('\n').trim(),
            );
            entries.add(entry);
          }

          // Parse new word entry: @word /ipa/
          final int slashStart = trimmed.indexOf('/');
          final int slashEnd = trimmed.lastIndexOf('/');

          if (slashStart > 0 && slashEnd > slashStart) {
            currentWord = trimmed.substring(1, slashStart).trim();
            currentIpa = trimmed.substring(slashStart, slashEnd + 1).trim();
            meanings.clear();
          }
          continue;
        }

        // Part of speech line starts with * - KEEP IT in meanings
        if (trimmed.startsWith('*')) {
          meanings.add(trimmed);
          continue;
        }

        // Meaning/example lines start with - or =
        if (trimmed.startsWith('-') || trimmed.startsWith('=')) {
          final String content = trimmed;
          if (content.isNotEmpty) {
            meanings.add(content);
          }
          continue;
        }
      }

      // Save last entry
      if (currentWord != null && currentWord.isNotEmpty) {
        final DictionaryEntry entry = DictionaryEntry(
          word: currentWord,
          ipa: currentIpa,
          partOfSpeech: meanings.isNotEmpty ? meanings.first : '',
          meaning: meanings.join('\n').trim(),
        );
        entries.add(entry);
      }
    } catch (e) {
      print('Error parsing dictionary file: $e');
    }

    return entries;
  }

  static Future<void> insertParsedEntries(
    String filePath,
    AppDatabase db,
  ) async {
    try {
      final List<DictionaryEntry> entries = await parseFile(filePath);
      
      // Insert in batches of 500 to avoid memory issues
      for (int i = 0; i < entries.length; i += 500) {
        final int end = (i + 500 < entries.length) ? i + 500 : entries.length;
        final List<DictionaryEntry> batch = entries.sublist(i, end);
        await db.insertDictionaryBatch(batch);
      }
    } catch (e) {
      print('Error inserting parsed entries: $e');
    }
  }

  static Future<int> parseAndInsertInBatches(
    String filePath,
    AppDatabase db, {
    int batchSize = 500,
  }) async {
    int inserted = 0;

    try {
      late Iterable<String> lines;

      if (filePath.startsWith('assets/')) {
        try {
          final String content = await rootBundle.loadString(filePath);
          lines = LineSplitter.split(content);
        } catch (_) {
          final File file = File(filePath);
          if (!await file.exists()) {
            return 0;
          }
          final String content = await file.readAsString();
          lines = LineSplitter.split(content);
        }
      } else {
        final File file = File(filePath);
        if (!await file.exists()) {
          return 0;
        }
        final String content = await file.readAsString();
        lines = LineSplitter.split(content);
      }

      String? currentWord;
      String currentIpa = '';
      final List<String> meanings = <String>[];
      final List<DictionaryEntry> batch = <DictionaryEntry>[];

      Future<void> flushBatch() async {
        if (batch.isEmpty) {
          return;
        }
        await db.insertDictionaryBatch(List<DictionaryEntry>.from(batch));
        inserted += batch.length;
        batch.clear();

        // Yield to event loop so UI remains responsive while loading large data.
        await Future<void>.delayed(Duration.zero);
      }

      int processedLines = 0;
      for (final String line in lines) {
        processedLines += 1;
        if (processedLines % 2000 == 0) {
          // Keep the main isolate responsive while processing large files.
          await Future<void>.delayed(Duration.zero);
        }

        final String trimmed = line.trim();

        if (trimmed.isEmpty || trimmed.startsWith('@00-')) {
          continue;
        }

        if (trimmed.startsWith('@')) {
          if (currentWord != null && currentWord.isNotEmpty) {
            batch.add(
              DictionaryEntry(
                word: currentWord,
                ipa: currentIpa,
                partOfSpeech: meanings.isNotEmpty ? meanings.first : '',
                meaning: meanings.join('\n').trim(),
              ),
            );

            if (batch.length >= batchSize) {
              await flushBatch();
            }
          }

          final int slashStart = trimmed.indexOf('/');
          final int slashEnd = trimmed.lastIndexOf('/');

          if (slashStart > 0 && slashEnd > slashStart) {
            currentWord = trimmed.substring(1, slashStart).trim();
            currentIpa = trimmed.substring(slashStart, slashEnd + 1).trim();
            meanings.clear();
          }
          continue;
        }

        // Keep * markers in meanings to preserve POS sections
        if (trimmed.startsWith('*')) {
          meanings.add(trimmed);
          continue;
        }

        // Keep - and = lines in meanings
        if (trimmed.startsWith('-') || trimmed.startsWith('=')) {
          meanings.add(trimmed);
        }
      }

      if (currentWord != null && currentWord.isNotEmpty) {
        batch.add(
          DictionaryEntry(
            word: currentWord,
            ipa: currentIpa,
            partOfSpeech: meanings.isNotEmpty ? meanings.first : '',
            meaning: meanings.join('\n').trim(),
          ),
        );
      }

      await flushBatch();
      return inserted;
    } catch (e) {
      print('Error parsing and inserting dictionary: $e');
      return 0;
    }
  }
}
