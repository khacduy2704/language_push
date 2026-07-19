import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/pronunciation_service.dart';

class CachedAudioScreen extends StatefulWidget {
  const CachedAudioScreen({super.key});

  @override
  State<CachedAudioScreen> createState() => _CachedAudioScreenState();
}

class _CachedAudioScreenState extends State<CachedAudioScreen> {
  final PronunciationService _pronunciationService = PronunciationService();
  late Future<List<CachedAudio>> _listFuture;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _pronunciationService.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _listFuture = _loadCachedAudio();
    });
  }

  Future<List<CachedAudio>> _loadCachedAudio() async {
    await _pronunciationService.rebuildCacheIndexFromFiles();
    return AppDatabase.instance.getCachedAudioList();
  }

  Future<void> _play(String word) async {
    if (_isPlaying) {
      return;
    }
    setState(() => _isPlaying = true);
    try {
      await _pronunciationService.playWord(word);
    } catch (_) {
      // Ignore playback errors.
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  Future<void> _delete(CachedAudio item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete audio'),
        content: Text('Remove cached audio for "${item.word}"?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE65A67),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _pronunciationService.deleteAudio(item.word);
    _reload();
  }

  Future<void> _deleteAll(List<CachedAudio> items) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete all audio'),
        content: Text(
          'Remove all ${items.length} cached audio file${items.length == 1 ? '' : 's'}?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE65A67),
            ),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    for (final CachedAudio item in items) {
      await _pronunciationService.deleteAudio(item.word);
    }
    _reload();
  }

  String _formatDate(DateTime dt) {
    final String d = dt.day.toString().padLeft(2, '0');
    final String m = dt.month.toString().padLeft(2, '0');
    final String y = dt.year.toString();
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _fileSize(String path) {
    try {
      final int bytes = File(path).lengthSync();
      if (bytes < 1024) {
        return '${bytes}B';
      }
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2E6EB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFE2E6EB),
        centerTitle: true,
        title: const Text(
          'Cached Audio',
          style: TextStyle(
            color: Color(0xFF3B4957),
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3B4957)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FutureBuilder<List<CachedAudio>>(
        future: _listFuture,
        builder:
            (BuildContext context, AsyncSnapshot<List<CachedAudio>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<CachedAudio> items = snapshot.data ?? <CachedAudio>[];

          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.volume_off_rounded,
                    size: 56,
                    color: Color(0xFFB0B8C1),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No audio files downloaded yet.\nOpen a word detail to download its audio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8994A3),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: <Widget>[
                    Text(
                      '${items.length} file${items.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8994A3),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _deleteAll(items),
                      icon: const Icon(
                        Icons.delete_sweep_rounded,
                        size: 18,
                        color: Color(0xFFE65A67),
                      ),
                      label: const Text(
                        'Delete all',
                        style: TextStyle(
                          color: Color(0xFFE65A67),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final CachedAudio item = items[index];
                    final String size = _fileSize(item.filePath);

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE8F0FF),
                          child: Icon(
                            Icons.volume_up_rounded,
                            color: const Color(0xFF4B7BE5),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          item.word,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF3B4957),
                          ),
                        ),
                        subtitle: Text(
                          '${_formatDate(item.downloadedAt)}${size.isNotEmpty ? '  •  $size' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8994A3),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: Icon(
                                _isPlaying
                                    ? Icons.hourglass_top_rounded
                                    : Icons.play_circle_rounded,
                                color: const Color(0xFF4B7BE5),
                                size: 28,
                              ),
                              onPressed:
                                  _isPlaying ? null : () => _play(item.word),
                              tooltip: 'Play',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFFE65A67),
                                size: 24,
                              ),
                              onPressed: () => _delete(item),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
