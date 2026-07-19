import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import 'app_database.dart';

class PronunciationService {
  AudioPlayer? _player;
  FlutterTts? _tts;

  Future<void> prefetchWordAudio(String word) async {
    final String normalizedWord = word.trim().toLowerCase();
    if (normalizedWord.isEmpty) {
      return;
    }

    final File localFile = await _getCachedFile(normalizedWord);
    if (await localFile.exists()) {
      return;
    }

    await _downloadAndCacheAudio(normalizedWord, localFile);
  }

  Future<void> playWord(String word) async {
    _player ??= AudioPlayer();
    final String normalizedWord = word.trim().toLowerCase();
    if (normalizedWord.isEmpty) {
      throw Exception('Word is empty.');
    }

    final File localFile = await _getCachedFile(normalizedWord);
    if (await localFile.exists()) {
      await _playLocal(localFile);
      return;
    }

    // File not cached — try to download it now before falling back to TTS.
    final bool downloaded = await _downloadAndCacheAudio(normalizedWord, localFile);
    if (await localFile.exists()) {
      await _playLocal(localFile);
      return;
    }

    final bool synthesized =
        await _synthesizeAndCacheAudio(normalizedWord, localFile);
    if (synthesized && await localFile.exists()) {
      await _playLocal(localFile);
      return;
    }

    if (!downloaded) {
      debugPrint('Could not download audio file for "$normalizedWord". Falling back to TTS.');
    }

    final bool spoke = await _speakWithFallback(normalizedWord);
    if (!spoke) {
      throw Exception('Unable to play pronunciation right now.');
    }
  }

  Future<bool> _downloadAndCacheAudio(String word, File localFile) async {
    final List<String> candidates = await _buildAudioCandidates(word);
    if (candidates.isEmpty) {
      return false;
    }

    for (final String audioUrl in candidates) {
      try {
        final http.Response response = await _safeGet(
          Uri.parse(audioUrl),
          headers: <String, String>{
            'User-Agent':
                'Mozilla/5.0 (Android; Mobile; rv:120.0) Gecko/120.0 Firefox/120.0',
          },
        );
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          debugPrint(
            'Audio candidate rejected for "$word": $audioUrl (status ${response.statusCode}, bytes ${response.bodyBytes.length})',
          );
          continue;
        }

        await localFile.writeAsBytes(response.bodyBytes, flush: true);
        await AppDatabase.instance.upsertCachedAudio(word, localFile.path);
        return true;
      } catch (error) {
        debugPrint('Audio download failed for "$word" from $audioUrl: $error');
      }
    }

    return false;
  }

  Future<bool> _synthesizeAndCacheAudio(String word, File localFile) async {
    _tts ??= FlutterTts();
    try {
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.45);
      await _tts!.setPitch(1.0);
      await _tts!.synthesizeToFile(word, localFile.path, true);

      for (int attempt = 0; attempt < 10; attempt++) {
        if (await localFile.exists() && await localFile.length() > 0) {
          await AppDatabase.instance.upsertCachedAudio(word, localFile.path);
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('Audio synthesize failed for "$word": $error');
    }
    return false;
  }

  Future<void> _playLocal(File localFile) async {
    try {
      await _player!.play(DeviceFileSource(localFile.path));
    } on MissingPluginException {
      throw Exception(
        'Audio plugin is not registered. Fully stop the app and run again.',
      );
    }
  }

  Future<File> _getCachedFile(String word) async {
    final Directory docsDir = await getApplicationDocumentsDirectory();
    final Directory cacheDir = Directory(p.join(docsDir.path, 'audio_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final String safeWord = word.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return File(p.join(cacheDir.path, '$safeWord.mp3'));
  }

  Future<void> rebuildCacheIndexFromFiles() async {
    final Directory docsDir = await getApplicationDocumentsDirectory();
    final Directory cacheDir = Directory(p.join(docsDir.path, 'audio_cache'));
    if (!await cacheDir.exists()) {
      return;
    }

    final List<FileSystemEntity> entities = await cacheDir.list().toList();
    for (final FileSystemEntity entity in entities) {
      if (entity is! File) {
        continue;
      }

      final String extension = p.extension(entity.path).toLowerCase();
      if (extension != '.mp3') {
        continue;
      }

      final String rawName = p.basenameWithoutExtension(entity.path);
      final String normalizedWord = rawName.trim().toLowerCase();
      if (normalizedWord.isEmpty) {
        continue;
      }

      try {
        await AppDatabase.instance.upsertCachedAudio(normalizedWord, entity.path);
      } catch (_) {
        // Continue indexing other files.
      }
    }
  }

  Future<List<String>> _fetchAudioUrls(String word) async {
    final Uri uri =
        Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
    final http.Response response = await _safeGet(uri);

    if (response.statusCode != 200) {
      return <String>[];
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) {
      return <String>[];
    }

    final Set<String> urls = <String>{};

    for (final dynamic entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }

      final dynamic phonetics = entry['phonetics'];
      if (phonetics is! List) {
        continue;
      }

      for (final dynamic phonetic in phonetics) {
        if (phonetic is! Map<String, dynamic>) {
          continue;
        }

        final String audio = (phonetic['audio'] ?? '').toString().trim();
        if (audio.isEmpty) {
          continue;
        }

        if (audio.startsWith('//')) {
          urls.add('https:$audio');
          continue;
        }
        urls.add(audio);
      }
    }

    return urls.toList();
  }

  Future<List<String>> _buildAudioCandidates(String word) async {
    final Set<String> candidates = <String>{};
    final List<String> apiUrls = await _fetchAudioUrls(word);
    candidates.addAll(apiUrls);

    final String encodedWord = Uri.encodeComponent(word);

    // Direct DictionaryAPI media URLs often work even when phonetics JSON has no audio.
    candidates.add(
      'https://api.dictionaryapi.dev/media/pronunciations/en/$encodedWord-us.mp3',
    );
    candidates.add(
      'https://api.dictionaryapi.dev/media/pronunciations/en/$encodedWord-uk.mp3',
    );
    candidates.add(
      'https://api.dictionaryapi.dev/media/pronunciations/en/$encodedWord.mp3',
    );

    // Fallback source to increase hit rate if API phonetics has no audio URL.
    candidates.add(
      'https://translate.google.com/translate_tts?ie=UTF-8&tl=en&client=tw-ob&q=$encodedWord',
    );

    return candidates.toList();
  }

  Future<bool> isAudioCached(String word) async {
    final String normalizedWord = word.trim().toLowerCase();
    if (normalizedWord.isEmpty) {
      return false;
    }
    // Check DB first (fast), then confirm the file actually exists on disk.
    final bool inDb = await AppDatabase.instance.hasCachedAudio(normalizedWord);
    if (inDb) {
      return true;
    }
    // Fallback: file might exist on disk without a DB record.
    final File file = await _getCachedFile(normalizedWord);
    return file.exists();
  }

  Future<void> deleteAudio(String word) async {
    final String normalizedWord = word.trim().toLowerCase();
    final File file = await _getCachedFile(normalizedWord);
    if (await file.exists()) {
      await file.delete();
    }
    await AppDatabase.instance.deleteCachedAudio(normalizedWord);
  }

  Future<void> speakSlow(String word) async {
    _tts ??= FlutterTts();
    try {
      try {
        await _tts!.stop();
      } on MissingPluginException {
        // Continue.
      }
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.25);
      await _tts!.setPitch(1.0);
      await _tts!.speak(word.trim().toLowerCase());
    } on MissingPluginException {
      // Platform does not support TTS.
    } catch (_) {
      // Ignore errors.
    }
  }

  Future<void> dispose() async {
    await _player?.dispose();
    if (_tts != null) {
      try {
        await _tts!.stop();
      } on MissingPluginException {
        // Some platforms do not implement stop for flutter_tts.
      }
    }
  }

  Future<bool> _speakWithFallback(String word) async {
    _tts ??= FlutterTts();

    try {
      await _player?.stop();
      try {
        await _tts!.stop();
      } on MissingPluginException {
        // Continue even if stop is unsupported on this platform.
      }
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.45);
      await _tts!.setPitch(1.0);

      await _tts!.speak(word);
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _safeGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      return await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } on HandshakeException catch (error) {
      debugPrint('HandshakeException for $uri: $error');
      return http.Response('', 503);
    } on SocketException catch (error) {
      debugPrint('SocketException for $uri: $error');
      return http.Response('', 503);
    } on TimeoutException catch (error) {
      debugPrint('TimeoutException for $uri: $error');
      return http.Response('', 504);
    } on HttpException catch (error) {
      debugPrint('HttpException for $uri: $error');
      return http.Response('', 503);
    } on FormatException catch (error) {
      debugPrint('FormatException for $uri: $error');
      return http.Response('', 502);
    }
  }
}
