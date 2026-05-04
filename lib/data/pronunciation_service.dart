import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PronunciationService {
  AudioPlayer? _player;

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

    final bool hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      throw Exception('No internet connection and no cached audio found.');
    }

    final String? audioUrl = await _fetchAudioUrl(normalizedWord);
    if (audioUrl == null || audioUrl.isEmpty) {
      throw Exception('No pronunciation audio found for "$normalizedWord".');
    }

    final http.Response response =
        await http.get(Uri.parse(audioUrl)).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('Failed to download pronunciation audio.');
    }

    await localFile.writeAsBytes(response.bodyBytes, flush: true);
    await _playLocal(localFile);
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

  Future<bool> _hasInternetConnection() async {
    try {
      final List<InternetAddress> result =
          await InternetAddress.lookup('api.dictionaryapi.dev')
              .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _fetchAudioUrl(String word) async {
    final Uri uri =
        Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
    final http.Response response =
        await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      return null;
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }

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
          return 'https:$audio';
        }
        return audio;
      }
    }

    return null;
  }

  Future<void> dispose() async {
    await _player?.dispose();
  }
}
